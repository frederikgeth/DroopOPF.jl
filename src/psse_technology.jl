"""Read confidential generator metadata CSV. Required columns: bus_number,
bus_name, technology; optional generator_id is the RAW machine ID (not internal
integer ID). Supports quoted commas, escaped quotes, BOM and multiline fields.
"""
function read_psse_generator_csv(path::AbstractString)
    text=chopprefix(read(path,String),"\ufeff")
    isvalid(text) || throw(ArgumentError("generator CSV must be UTF-8"))
    rows=Vector{String}[];row=String[];buf=IOBuffer();quoted=false;closed=false;started=false
    chars=collect(text);i=1
    while i<=length(chars)
        ch=chars[i]
        if quoted
            if ch=='"'
                if i<length(chars) && chars[i+1]=='"';write(buf,'"');i+=1
                else;quoted=false;closed=true;end
            else;write(buf,ch);end
        elseif ch=='"'
            !started && !closed || throw(ArgumentError("invalid CSV quote"))
            quoted=true;started=true
        elseif ch==','
            push!(row,String(take!(buf)));started=false;closed=false
        elseif ch in ('\n','\r')
            push!(row,String(take!(buf)))
            all(isempty(strip(x)) for x in row) || push!(rows,row)
            row=String[];started=false;closed=false
            ch=='\r' && i<length(chars) && chars[i+1]=='\n' && (i+=1)
        else
            closed && !isspace(ch) && throw(ArgumentError("characters after CSV quote"))
            !closed && write(buf,ch);started=true
        end
        i+=1
    end
    quoted && throw(ArgumentError("unterminated CSV quote"))
    if started || closed || !isempty(row)
        push!(row,String(take!(buf)));all(isempty(strip(x)) for x in row)||push!(rows,row)
    end
    length(rows)>=2 || throw(ArgumentError("generator CSV requires a header and data"))
    aliases=Dict("bus"=>"bus_number","bus_id"=>"bus_number","name"=>"bus_name","id"=>"generator_id","machine_id"=>"generator_id")
    headers=[get(aliases,h,h) for h in [replace(lowercase(strip(x)),r"[^a-z0-9]+"=>"_") for x in rows[1]]]
    length(unique(headers))==length(headers) || throw(ArgumentError("duplicate generator CSV column"))
    all(k in headers for k in ("bus_number","bus_name","technology")) ||
        throw(ArgumentError("generator CSV needs bus_number, bus_name, technology"))
    allowed=Set(["ibr_unidentified","synchronous_generator","synchronous_condenser"])
    result=NamedTuple[];identities=Set{Tuple{Int,String}}()
    for (n,fields) in enumerate(rows[2:end])
        length(fields)==length(headers) || throw(ArgumentError("generator CSV column count mismatch"))
        d=Dict(zip(headers,strip.(fields)));bus=tryparse(Int,d["bus_number"])
        !isnothing(bus) && bus>0 || throw(ArgumentError("CSV bus number must be a positive integer"))
        technology=lowercase(d["technology"]);technology in allowed || throw(ArgumentError("unsupported generator technology"))
        name=d["bus_name"];isempty(name) && throw(ArgumentError("CSV bus name required"))
        machine=get(d,"generator_id","");key=(bus,machine)
        key in identities && throw(ArgumentError("duplicate generator CSV identity"));push!(identities,key)
        push!(result,(;bus_number=bus,bus_name=name,generator_id=machine,technology,csv_row=n+1))
    end
    result
end

_psse_busname(x)=lowercase(join(split(strip(x))," "))

function _psse_technology_map(imports,metadata)
    matched=Set{Int}();mapping=Dict{Int,Dict{String,Any}}[]
    for r in imports
        names=Dict(Int(b.fields[:I])=>get(b.fields,:NAME,"") for b in r.raw.sections[:bus])
        entries=Dict{Int,Dict{String,Any}}()
        for g in r.case.generators
            bus,machine=r.source_ids[:generator][g.id]
            candidates=findall(x->x.bus_number==bus && (isempty(x.generator_id)||x.generator_id==machine),metadata)
            length(candidates)==1 || throw(ArgumentError("missing or ambiguous generator CSV mapping; inspect locally"))
            j=only(candidates);m=metadata[j]
            isempty(m.generator_id) && count(x->x.bus_id==bus,r.case.generators)>1 &&
                throw(ArgumentError("multiple generators at CSV bus require explicit RAW generator_id"))
            _psse_busname(m.bus_name)==_psse_busname(names[bus]) || throw(ArgumentError("CSV and RAW bus names disagree; inspect locally"))
            push!(matched,j)
            entries[g.id]=Dict("source_id"=>_json_data((bus,machine)),"bus_name"=>names[bus],
                "technology"=>m.technology,"csv_row"=>m.csv_row)
        end
        push!(mapping,entries)
    end
    mapping,[m for (j,m) in enumerate(metadata) if !(j in matched)]
end

# Least-squares candidate for the existing equal-slope, deadband VoltVarDroop.
# Grid-selected deadband locations are an approximation, not certified settings.
function _psse_fit_voltvar(v,q,qmin,qmax;minimum_points=6,minimum_voltage_span=.005,
    relative_rmse_tolerance=.02,maximum_grid_points=15)
    minimum_points isa Integer && minimum_points>=3 || throw(ArgumentError("minimum_points must be at least three"))
    isfinite(minimum_voltage_span) && minimum_voltage_span>0 || throw(ArgumentError("positive finite voltage span required"))
    isfinite(relative_rmse_tolerance) && relative_rmse_tolerance>=0 || throw(ArgumentError("invalid fit residual tolerance"))
    maximum_grid_points isa Integer && 3<=maximum_grid_points<=41 || throw(ArgumentError("grid size must be 3 to 41"))
    n=length(v);span=n==0 ? 0. : maximum(v)-minimum(v)
    report=Dict{String,Any}("status"=>"insufficient_data","candidate_curve"=>nothing,
        "online_usable_points"=>n,"voltage_span_pu"=>span,"full_curve_identified"=>false,
        "method"=>"bounded deadband grid plus least squares on unsaturated samples; equal slopes; source Q box",
        "assumptions"=>Dict("minimum_points"=>minimum_points,"minimum_voltage_span_pu"=>minimum_voltage_span,
            "relative_rmse_tolerance"=>relative_rmse_tolerance,"maximum_grid_points"=>maximum_grid_points),
        "scope"=>"exploratory static Q(V) association; not proof of Volt-VAR control, causality or manufacturer settings")
    n>=minimum_points && length(unique(v))>=3 && span>=minimum_voltage_span || return report
    qmax>qmin || (report["status"]="fixed_q_capability";return report)
    scale=qmax-qmin;tol=max(1e-9,scale*1e-6)
    active=findall(i->qmin+tol<q[i]<qmax-tol,eachindex(q))
    report["unsaturated_points"]=length(active)
    length(active)>=3 && length(unique(v[active]))>=2 || (report["status"]="insufficient_unsaturated_data";return report)
    distinct=sort(unique(v))
    grid=sort(unique(vcat(distinct,[(distinct[i]+distinct[i+1])/2 for i in 1:length(distinct)-1])))
    if length(grid)>maximum_grid_points
        grid=grid[unique(round.(Int,range(1,length(grid);length=maximum_grid_points)))]
    end
    best=nothing;besterr=Inf
    for lo in grid, hi in grid
        hi>=lo || continue
        h=[max(lo-x,0.)-max(x-hi,0.) for x in v]
        ha=h[active];qa=q[active];hm=sum(ha)/length(ha);qm=sum(qa)/length(qa)
        denom=sum((x-hm)^2 for x in ha);denom>1e-16 || continue
        gain=sum((x-hm)*(y-qm) for (x,y) in zip(ha,qa))/denom
        gain>1e-10 || continue
        ref=qm-gain*hm;qmin<=ref<=qmax || continue
        predicted=clamp.(ref .+ gain.*h,qmin,qmax)
        err=sum((predicted.-q).^2)
        if err<besterr
            besterr=err;best=(;lo,hi,gain,ref,predicted)
        end
    end
    isnothing(best) && (report["status"]="no_negative_droop_fit";return report)
    rmse=sqrt(besterr/n);report["rmse_q_pu"]=rmse
    report["max_abs_error_q_pu"]=maximum(abs.(best.predicted.-q))
    rmse<=relative_rmse_tolerance*scale || (report["status"]="inconsistent_with_static_droop";return report)
    slope=1/best.gain
    # A reference at a Q bound cannot yield the library's strictly ordered curve.
    qmin<best.ref<qmax || (report["status"]="degenerate_candidate";return report)
    lower=best.lo-slope*(qmax-best.ref);upper=best.hi+slope*(best.ref-qmin)
    lower>0 || (report["status"]="nonphysical_extrapolation";return report)
    curve=Dict("slope_v_per_q_pu"=>slope,"v_db_low"=>best.lo,"v_db_high"=>best.hi,
        "q_ref_pu"=>best.ref,"q_min_pu"=>qmin,"q_max_pu"=>qmax,
        "voltage_breakpoints_pu"=>best.lo==best.hi ? [lower,best.lo,upper] : [lower,best.lo,best.hi,upper],
        "q_breakpoints_pu"=>best.lo==best.hi ? [qmax,best.ref,qmin] : [qmax,best.ref,best.ref,qmin])
    regions=Dict("upper_q_limit"=>count(>=(qmax-tol),q),"lower_q_limit"=>count(<=(qmin+tol),q),
        "low_voltage_slope"=>count(i->v[i]<best.lo && qmin+tol<q[i]<qmax-tol,eachindex(v)),
        "deadband"=>count(i->best.lo<=v[i]<=best.hi,eachindex(v)),
        "high_voltage_slope"=>count(i->v[i]>best.hi && qmin+tol<q[i]<qmax-tol,eachindex(v)))
    report["regime_sample_counts"]=regions
    covered=regions["upper_q_limit"]>=1 && regions["lower_q_limit"]>=1 &&
        regions["low_voltage_slope"]>=2 && regions["high_voltage_slope"]>=2 && regions["deadband"]>=2
    report["status"]=covered ? "candidate_full_regime_coverage" : "candidate_partial_range"
    report["candidate_curve"]=curve
    report["deadband_grid_resolution_pu"]=maximum(diff(grid))
    report["unverified_parameters"]=["actual controller mode","deadband edges between samples","extrapolation outside observed voltages",
        "dynamic/P-dependent capability","control timing","plant-level aggregation"]
    report
end

function _psse_ibr_fits(imports,built,mappings;kwargs...)
    fits=Dict{String,Any}[]
    for g in built[1].case.generators
        mappings[1][g.id]["technology"]=="ibr_unidentified" || continue
        source=imports[1].source_ids[:generator][g.id]
        observations=Dict{String,Any}[];v=Float64[];q=Float64[];settings=Any[];limits=Any[]
        for (t,r) in enumerate(imports)
            record=only(x for x in r.raw.sections[:generator] if
                (Int(x.fields[:I]),get(x.fields,:ID,"1"))==source)
            f=record.fields;available=get(f,:STAT,1)!=0
            remote=Int(get(f,:IREG,0));voltage_bus=remote==0 ? source[1] : remote
            buses=filter(x->get(x.fields,:I,nothing)==voltage_bus,r.raw.sections[:bus])
            complete=length(buses)==1 && haskey(only(buses).fields,:VM) && haskey(f,:PG) && haskey(f,:QG)
            valid=available && complete
            p=get(f,:PG,nothing);reactive=get(f,:QG,nothing)
            voltage=complete ? only(buses).fields[:VM] : nothing
            reason=!available ? "offline" : !complete ? "missing_saved_fields" : "used"
            if valid && !(g.p_min<=p/r.case.base_power<=g.p_max && g.q_min<=reactive/r.case.base_power<=g.q_max)
                valid=false;reason="outside_source_capability"
            end
            push!(observations,Dict("period"=>t,"online"=>available,"voltage_bus"=>voltage_bus,
                "voltage_pu"=>voltage,"p_mw"=>p,"q_mvar"=>reactive,"used"=>valid,"reason"=>reason))
            if valid
                push!(v,voltage);push!(q,reactive/r.case.base_power)
                push!(settings,Tuple(get(f,k,nothing) for k in (:IREG,:VS,:WMOD,:WPF)))
                push!(limits,Tuple(get(f,k,nothing) for k in (:QT,:QB)))
            end
        end
        fit=_psse_fit_voltvar(v,q,g.q_min,g.q_max;kwargs...)
        if length(unique(settings))>1 || length(unique(limits))>1
            fit["status"]="control_settings_or_limits_changed";fit["candidate_curve"]=nothing
        end
        fit["generator_id"]=g.id;fit["source_id"]=_json_data(source)
        fit["technology"]="ibr_unidentified";fit["observations"]=observations
        fit["base_power_mva"]=built[1].case.base_power
        fit["control_settings"]=_json_data(settings)
        fit["controls_installed"]=false
        fit["warnings"]=["Q versus voltage can also reflect dispatch, AVR, power factor or plant control; technology alone does not establish droop",
            "fits do not establish validity of source saved power flows; inspect saved_reports",
            "candidate parameters require engineering review before use as a shared controller"]
        haskey(fit,"rmse_q_pu") && (fit["rmse_mvar"]=fit["rmse_q_pu"]*built[1].case.base_power)
        push!(fits,fit)
    end
    fits
end

function _psse_ibr_fit_html(fits)
    io=IOBuffer()
    for fit in fits
        print(io,"<details><summary>IBR ",_psse_html(fit["source_id"])," — ",_psse_html(fit["status"]),"</summary>")
        observations=[x for x in fit["observations"] if x["used"]]
        if !isempty(observations)
            vs=[x["voltage_pu"] for x in observations];qs=[x["q_mvar"] for x in observations]
            xmin,xmax=extrema(vs);xmax-xmin<1e-6 && (xmin-=.0005;xmax+=.0005)
            candidate=fit["candidate_curve"]
            predictions=Float64[]
            if !isnothing(candidate)
                model=PiecewiseLinearCurve(Float64.(candidate["voltage_breakpoints_pu"]),Float64.(candidate["q_breakpoints_pu"]))
                predictions=[evaluate(model,x)*fit["base_power_mva"] for x in range(xmin,xmax;length=100)]
            end
            ymin,ymax=extrema(vcat(qs,predictions));pad=max((ymax-ymin)*.1,.01);ymin-=pad;ymax+=pad
            xx(x)=60+540*(x-xmin)/(xmax-xmin);yy(y)=240-200*(y-ymin)/(ymax-ymin)
            print(io,"<svg viewBox=\"0 0 640 300\" role=\"img\" aria-label=\"Saved Q versus voltage and exploratory candidate curve\" style=\"width:100%;max-width:800px\">")
            print(io,"<path d=\"M60 40 V240 H600\" fill=\"none\" stroke=\"currentColor\"/>")
            for (x,y,text) in ((60,260,round(xmin;digits=5)),(560,260,round(xmax;digits=5)),
                (5,50,round(ymax;digits=2)),(5,240,round(ymin;digits=2)),(270,285,"Voltage (pu)"),(5,25,"Q (MVAr)"))
                print(io,"<text x=\"$x\" y=\"$y\" fill=\"currentColor\" font-size=\"13\">",_psse_html(text),"</text>")
            end
            curve=fit["candidate_curve"]
            if !isnothing(curve)
                model=PiecewiseLinearCurve(Float64.(curve["voltage_breakpoints_pu"]),Float64.(curve["q_breakpoints_pu"]))
                points=join(["$(xx(x)),$(yy(evaluate(model,x)*fit["base_power_mva"]))" for x in range(xmin,xmax;length=100)]," ")
                print(io,"<polyline points=\"$points\" fill=\"none\" stroke=\"currentColor\" stroke-dasharray=\"6 4\"/>")
            end
            for obs in observations
                print(io,"<circle cx=\"",xx(obs["voltage_pu"]),"\" cy=\"",yy(obs["q_mvar"]),"\" r=\"4\" fill=\"currentColor\"><title>Period ",obs["period"],"; V ",obs["voltage_pu"],"; Q ",obs["q_mvar"]," MVAr</title></circle>")
            end
            print(io,"</svg><p>Dots: usable online snapshots. Dashed line: exploratory candidate over the observed voltage range only. No controls installed.</p>")
        end
        print(io,"<pre>",_psse_html(JSON.json(_json_data(fit);pretty=true)),"</pre></details>")
    end
    String(take!(io))
end

# User-declared technology policy: synchronous units use static, capability-limited AVR.
function _psse_avr_assignments(imports,built,mappings)
    assignments=Vector{ReactiveControlAssignment}[];policies=Dict{String,Any}[]
    for (t,b) in enumerate(built)
        r=imports[t];a=ReactiveControlAssignment[];rows=Dict{String,Any}[]
        buses=Set(x.id for x in b.case.network.buses)
        for g in b.case.generators
            technology=mappings[t][g.id]["technology"]
            technology in ("synchronous_generator","synchronous_condenser") || continue
            source=r.source_ids[:generator][g.id]
            f=only(x.fields for x in r.raw.sections[:generator] if
                (Int(x.fields[:I]),get(x.fields,:ID,"1"))==source)
            remote=Int(get(f,:IREG,0));regulated=remote==0 ? g.bus_id : remote
            target=get(f,:VS,nothing);status="configured"
            if !haskey(f,:VS)
                status="missing_voltage_target"
            elseif get(f,:NREG,0)!=0
                status="unsupported_regulated_node"
            elseif !(regulated in buses)
                status="regulated_bus_outside_model"
            else
                bus=only(x for x in b.case.network.buses if x.id==regulated)
                bus.v_min<=target<=bus.v_max || (status="target_outside_voltage_bounds")
            end
            condenser_valid=technology!="synchronous_condenser" ||
                (g.p_max<=0 && get(f,:PG,0.)<=0)
            if status=="configured"
                push!(a,ReactiveControlAssignment(g.id,AVR(Float64(target)),RegulatedLocation(:bus,regulated)))
            end
            push!(rows,Dict("generator_id"=>g.id,"source_id"=>_json_data(source),"technology"=>technology,
                "mode"=>"AVR","online"=>g.available,"regulated_bus"=>regulated,"source_ireg"=>remote,
                "source_nreg"=>get(f,:NREG,0),"source_rmpct"=>get(f,:RMPCT,nothing),"voltage_target_pu"=>target,"status"=>status,
                "q_min_pu"=>g.q_min,"q_max_pu"=>g.q_max,
                "condenser_active_capability_qualified"=>condenser_valid,
                "active_policy"=>technology=="synchronous_condenser" ?
                    "source active limits/loss range retained; no automatic active-response participation; positive active capability requires correction" :
                    "source active capabilities and limit-aware response retained"))
        end
        validation_error=nothing
        try
            validate_reactive_assignments(b.case,a)
        catch e
            e isa ArgumentError || rethrow()
            validation_error=sprint(showerror,e)
        end
        qualified=isnothing(validation_error) && all(x["status"]=="configured" && x["condenser_active_capability_qualified"] for x in rows)
        push!(assignments,a)
        push!(policies,Dict("qualified"=>qualified,"assignments"=>rows,"validation_error"=>validation_error,
            "reactive_sharing"=>"existing AVR group model: equal effective Q-range fractions at a common bus; source RMPCT retained for inspection, not enforced",
            "scope"=>"user-declared static AVR with Q-limit release; fixed supplied VS per period and across outages; no exciter dynamics"))
    end
    assignments,policies
end
