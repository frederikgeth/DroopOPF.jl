import SHA

"""Validate the voltages, angles and generator P/Q saved in RAW, without solving.

Returns a JSON-compatible report separating AC balance, known operating limits,
and missing thermal ratings. Default balance thresholds are 0.01 MW/MVAr per
bus, explicitly allowing ordinary RAW export rounding; core equilibrium
validation tolerances are unchanged. A pass covers the imported AC subset,
not PSS/E convergence, automatic controls, dynamics or external branch-flow data.
"""
function validate_psse_saved_solution(imported::PSSEImport;
    power_tolerance_mw=0.01,reactive_tolerance_mvar=0.01,limit_tolerance_pu=1e-6,
    top_buses=10)
    all(x->isfinite(x)&&x>=0,(power_tolerance_mw,reactive_tolerance_mvar,limit_tolerance_pu)) ||
        throw(ArgumentError("validation tolerances must be finite and nonnegative"))
    top_buses isa Integer && top_buses>0 || throw(ArgumentError("top_buses must be a positive integer"))
    c=imported.case;s=imported.initial_state;raw=imported.raw;base=c.base_power
    missing=String[]
    busdata=Dict(r.fields[:I]=>r for r in raw.sections[:bus])
    gendata=Dict((r.fields[:I],get(r.fields,:ID,"1"))=>r for r in get(raw.sections,:generator,PSSERecord[]))
    for b in c.network.buses, key in (:VM,:VA)
        haskey(busdata[b.id].fields,key) || push!(missing,"bus $(b.id): $key not saved")
    end
    for g in c.generators, key in (:PG,:QG)
        r=gendata[imported.source_ids[:generator][g.id]]
        haskey(r.fields,key) || push!(missing,"generator $(imported.source_ids[:generator][g.id]): $key not saved")
    end
    balance=power_balance(c,s);flows=branch_flows(c.network,s)
    rows=[Dict{String,Any}("bus_id"=>b.id,"name"=>get(busdata[b.id].fields,:NAME,""),
        "p_mismatch_mw"=>balance.active[i]*base,"q_mismatch_mvar"=>balance.reactive[i]*base,
        "voltage_pu"=>s.vm[i]) for (i,b) in enumerate(c.network.buses)]
    peak_p=maximum(abs(r["p_mismatch_mw"]) for r in rows)
    peak_q=maximum(abs(r["q_mismatch_mvar"]) for r in rows)
    consistent=isempty(missing)&&peak_p<=power_tolerance_mw&&peak_q<=reactive_tolerance_mvar
    score(r)=max(power_tolerance_mw==0 ? (r["p_mismatch_mw"]==0 ? 0. : Inf) : abs(r["p_mismatch_mw"])/power_tolerance_mw,
        reactive_tolerance_mvar==0 ? (r["q_mismatch_mvar"]==0 ? 0. : Inf) : abs(r["q_mismatch_mvar"])/reactive_tolerance_mvar)
    worst=sort(rows;by=r->-score(r))
    records=Dict{Any,PSSERecord}()
    for r in get(raw.sections,:branch,PSSERecord[])
        records[(:line,abs(r.fields[:I]),abs(r.fields[:J]),get(r.fields,:CKT,"1"))]=r
    end
    for r in get(raw.sections,:transformer,PSSERecord[])
        records[(:transformer,r.fields[:I],r.fields[:J],get(r.fields,:CKT,"1"))]=r
    end
    branch_rows=Dict{String,Any}[];unrated=Any[];thermal_violations=Any[]
    for (i,b) in enumerate(c.network.branches)
        identity=imported.source_ids[:branch][b.id];r=records[identity]
        rate=get(r.fields,b.kind==:transformer ? :RATE1_1 : :RATE1,0.)
        known=rate>0
        from=flows.from[i]*base;to=flows.to[i]*base
        margin=known ? rate-max(abs(from),abs(to)) : nothing
        b.available&&!known&&push!(unrated,identity)
        b.available&&known&&margin < -limit_tolerance_pu*base&&push!(thermal_violations,identity)
        push!(branch_rows,Dict("branch_id"=>b.id,"source_id"=>_json_data(identity),"available"=>b.available,
            "p_from_mw"=>real(from),"q_from_mvar"=>imag(from),"p_to_mw"=>real(to),"q_to_mvar"=>imag(to),
            "active_loss_mw"=>real(from+to),"normal_rating_mva"=>known ? rate : nothing,
            "thermal_margin_mva"=>margin))
    end
    # Reuse the independent original-network validator for nonthermal bounds;
    # thermal checks above use RAW ratings, never an import placeholder.
    eq=validate_equilibrium(c,s;limit_tolerance=limit_tolerance_pu)
    violations=Symbol[v for v in eq.violations if !(v in (:power_balance,:branch_thermal))]
    isempty(thermal_violations)||push!(violations,:branch_thermal)
    known_limits_valid=isempty(violations)
    complete=isempty(unrated)
    valid=consistent&&known_limits_valid&&complete
    status=!isempty(missing) ? "missing_saved_solution" : !consistent ? "power_flow_mismatch" :
        !known_limits_valid ? "limits_violated" : !complete ? "limits_unassessed" : "passed"
    Dict{String,Any}("schema_version"=>1,"kind"=>"DroopOPF.PSSESavedSolutionValidation",
        "source"=>raw.source,"source_text_sha256"=>bytes2hex(SHA.sha256(codeunits(raw.text))),
        "revision"=>raw.revision,"status"=>status,"valid"=>valid,
        "power_flow_consistent"=>consistent,"saved_state_complete"=>isempty(missing),
        "missing_saved_fields"=>missing,"known_limits_valid"=>known_limits_valid,
        "thermal_coverage_complete"=>complete,"unrated_branches"=>_json_data(unrated),
        "limit_violations"=>string.(violations),"thermal_violations"=>_json_data(thermal_violations),
        "tolerances"=>Dict("power_mw"=>power_tolerance_mw,"reactive_mvar"=>reactive_tolerance_mvar,
            "limits_pu"=>limit_tolerance_pu),
        "max_p_mismatch_mw"=>peak_p,"max_q_mismatch_mvar"=>peak_q,
        "total_active_branch_loss_mw"=>sum((r["active_loss_mw"] for r in branch_rows);init=0.),
        "bus_count"=>length(rows),"branch_count"=>length(branch_rows),
        "worst_buses"=>first(worst,min(top_buses,length(worst))),"bus_mismatches"=>rows,"branch_flows"=>branch_rows,
        "diagnostics"=>copy(imported.diagnostics),"optimization_performed"=>false,
        "scope"=>"Saved-state AC consistency and supported normal limits only; no original solver/control/dynamic certification; branch flows are recomputed, not compared with an external PSS/E flow listing.")
end

function _psse_report_destination(source,output)
    isnothing(output)&&return
    canonical(p)=ispath(p) ? realpath(p) : abspath(p)
    canonical(source)==canonical(output) && throw(ArgumentError("validation report must not overwrite the source RAW file"))
end
"""Write a local JSON report. Nonfinite diagnostic values become JSON null."""
function write_psse_validation_report(path::AbstractString,report::AbstractDict)
    haskey(report,"source")&&_psse_report_destination(report["source"],path)
    open(path,"w") do io
        JSON.json(io,_json_data(report);pretty=true);println(io)
    end
    path
end
function _psse_validation_notice(report)
    message="PSS/E saved solution: $(report["status"])"
    if get(report,"power_flow_consistent",nothing)!==nothing
        message*="; max bus mismatch $(round(report["max_p_mismatch_mw"];sigdigits=4)) MW / $(round(report["max_q_mismatch_mvar"];sigdigits=4)) MVAr"
    end
    if report["valid"]
        @info message
    else
        @warn message
    end
end

"""Check a RAW saved power-flow solution and optionally save a JSON report.

This check-only path never exposes a case with invented thermal ratings. It uses
an internal finite adapter placeholder for zero/omitted ratings solely to replay
AC physics, excludes those placeholders from every thermal check, and reports
incomplete thermal coverage. Ordinary `load_psse_case` still requires an explicit
`unrated_limit` before it can return such a case. Unsupported data return
`status="unsupported"`; malformed input returns `status="invalid_file"`.
"""
function check_psse_file(path::AbstractString;encoding=:utf8,report_path=nothing,
    verbose=true,kwargs...)
    # Validate options before catching file/model errors; misspelled keywords or
    # invalid tolerances are programmer errors, not misleading file diagnoses.
    allowed=Set([:power_tolerance_mw,:reactive_tolerance_mvar,:limit_tolerance_pu,:top_buses])
    all(k in allowed for k in keys(kwargs))||throw(ArgumentError("unknown validation option"))
    for k in (:power_tolerance_mw,:reactive_tolerance_mvar,:limit_tolerance_pu)
        value=get(kwargs,k,0.)
        value isa Real&&isfinite(value)&&value>=0 || throw(ArgumentError("invalid validation tolerance"))
    end
    get(kwargs,:top_buses,10) isa Integer&&get(kwargs,:top_buses,10)>0 || throw(ArgumentError("top_buses must be positive integer"))
    _psse_report_destination(path,report_path)
    stage="parse";raw=nothing
    report=try
        raw=parse_psse_raw(path;encoding);stage="import"
        # Placeholder is internal to this report-only function, never a returned
        # engineering limit. validate_psse_saved_solution reads original ratings.
        imported=import_psse_case(raw;unrated_limit=1e100)
        stage="validate"
        result=validate_psse_saved_solution(imported;kwargs...)
        result["diagnostics"]=[x for x in result["diagnostics"] if !startswith(x,"explicit unrated_limit=")]
        if !result["thermal_coverage_complete"]
            push!(result["diagnostics"],"Unrated branches were excluded from thermal-limit checks; no engineering rating assigned.")
        end
        result["source_file_sha256"]=bytes2hex(SHA.sha256(read(path)))
        result
    catch err
        (err isa ArgumentError||err isa SystemError||err isa Base.IOError) || rethrow()
        Dict{String,Any}("schema_version"=>1,"kind"=>"DroopOPF.PSSESavedSolutionValidation",
            "source"=>String(path),"revision"=>isnothing(raw) ? nothing : raw.revision,
            "status"=>stage=="parse" ? "invalid_file" : "unsupported","valid"=>false,
            "power_flow_consistent"=>nothing,"error"=>sprint(showerror,err),"failed_stage"=>stage,
            "optimization_performed"=>false)
    end
    isnothing(report_path)||write_psse_validation_report(report_path,report)
    verbose&&_psse_validation_notice(report)
    report
end
