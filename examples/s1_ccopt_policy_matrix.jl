using SHA

include("s1_ccopt_pilot.jl")

# Kept local so this runner does not import the Ipopt/MadNLP restart mechanism.
s1_ccopt_canonical(x::AbstractDict)="{"*join([JSON.json(string(k))*":"*s1_ccopt_canonical(x[k])
    for k in sort(collect(keys(x));by=string)],",")*"}"
s1_ccopt_canonical(x::AbstractVector)="["*join(s1_ccopt_canonical.(x),",")*"]"
s1_ccopt_canonical(x)=JSON.json(x)

"""The fixed, public S1 cells shared with the Ipopt/MadNLP policy matrix."""
function s1_ccopt_policy_cells()
    [(n=n, load_factor=f, start=start) for n in (118, 300) for f in (1.0, 1.05)
        for start in (:anchor, :flat_low, :flat_high)]
end

function s1_ccopt_policy_context(case, policies, options)
    policy_data=Dict(string(k)=>[Dict(string(f)=>DroopOPF._json_data(getfield(c,f))
        for f in fieldnames(typeof(c))) for c in cs] for (k,cs) in pairs(policies))
    bytes2hex(sha256(s1_ccopt_canonical(Dict(
        "schema"=>"s1-ccopt-frozen-v1", "case"=>DroopOPF._json_data(case),
        "policies"=>policy_data, "encoding"=>"complementarity", "options"=>options))))
end

"""
Run CCOpt's frozen S1 lane.

This is intentionally a *native direct* CCOpt profile: exact complementarity,
one solve per cell, 1000 CCOpt inner iterations and 60 seconds.  CCOpt exposes
no solver-independent dual-reset interface or outer-homotopy counter, so the
Ipopt/MadNLP one-reset recovery policy is neither applied nor emulated here.
The case IDs, network overlay, controls, load factors, starts, serialized
diagnostics, and physical acceptance checks are shared with `s1_policy_matrix`.
"""
function s1_ccopt_policy_matrix(out)
    mkpath(out)
    summary_path=joinpath(out,"summary.json")
    rows=Dict{String,Any}[]
    if isfile(summary_path)
        retained=JSON.parsefile(summary_path)
        for row in get(retained,"rows",Any[])
            push!(rows,Dict{String,Any}(string(k)=>v for (k,v) in row))
        end
    end
    profile=Dict{String,Any}("max_iter"=>1000, "max_wall_time"=>60.0,
        "sigma_min"=>1e-14, "tol"=>1e-11, "acceptable_tol"=>1e-11)
    ccopt_options=Dict{String,Any}(
        "relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=profile["sigma_min"]),
        "tol"=>profile["tol"], "acceptable_tol"=>profile["acceptable_tol"])
    for cell in s1_ccopt_policy_cells()
        source=joinpath(@__DIR__,"..","test","data","pglib","v23.07",
            "pglib_opf_case$(cell.n)_ieee.m")
        original=load_matpower_case(source;base_frequency=60.)
        anchor=read_joint_design(joinpath(@__DIR__,"..","artifacts","s1_public_controls",
            "public$(cell.n)-baseline-design.json"))
        case, policies, _=s1_public_overlay(original,anchor,source;bank_count=cell.n==118 ? 12 : 32)
        case=s1_load(case,cell.load_factor)
        start=cell.start==:anchor ? anchor.opf.state : s1_flat(case)
        selected=cell.start==:anchor ? policies : s1_reseed(case,policies;
            fraction=cell.start==:flat_low ? .2 : .8)
        name="public$(cell.n)-load$(cell.load_factor)-ccopt-$(cell.start)"
        any(get(row,"name",nothing)==name for row in rows) && begin
            println("FROZEN CCOPT ",name," retained; skipping"); flush(stdout)
            continue
        end
        context=s1_ccopt_policy_context(case,selected,profile)
        tags=Dict{String,Any}("matrix"=>"s1_ccopt_frozen_v1", "load_factor"=>cell.load_factor,
            "start"=>string(cell.start), "context"=>context,
            "acceptance"=>"solver, policy, AC physical, and direct exact-droop checks",
            "recovery"=>"none; native direct CCOpt profile")
        row,result=s1_ccopt_attempt(out,name,case,start;policies=selected,tags,
            option_overrides=ccopt_options)
        row["source_audit"]=!isnothing(result) && get(row,"valid",false) ?
            s1_source_audit(case,result,source) : nothing
        row["frozen_profile"]=profile
        row["case_key"]=Dict("buses"=>cell.n,"load_factor"=>cell.load_factor,"start"=>string(cell.start))
        push!(rows,row)
        write(summary_path,JSON.json(Dict("schema"=>"s1-ccopt-frozen-v1",
            "scope"=>"CCOpt exact-complementarity frozen S1 lane", "profile"=>profile,
            "rows"=>rows);pretty=true)*"\n")
        println("FROZEN CCOPT ",name," valid=",get(row,"valid",false)); flush(stdout)
    end
    s1_ccopt_policy_report(out,rows,profile)
    rows
end

function s1_ccopt_policy_report(out,rows,profile)
    open(joinpath(out,"report.md"),"w") do io
        sigma_min=profile["sigma_min"]; tol=profile["tol"]; acceptable_tol=profile["acceptable_tol"]
        println(io,"# Frozen S1 — CCOpt exact-complementarity lane\n")
        println(io,"This is the CCOpt counterpart to `examples/s1_policy_matrix.jl`: the same 12 public S1 cells (IEEE 118/300 × nominal/+5% load × anchor/flat-low/flat-high), overlay construction, controls, serialized design artifacts, and independent acceptance checks. CCOpt is evaluated with its native direct profile: one exact-complementarity solve per cell, 1000 inner iterations and 60 seconds. It has no portable dual-reset or outer-homotopy budget through MOI, therefore it is not assigned the Ipopt/MadNLP multiplier-reset recovery policy.\n")
        println(io,"Profile: `sigma_min=$sigma_min`, `tol=$tol`, `acceptable_tol=$acceptable_tol`. A result is accepted only when solver, policy, AC physical, and direct exact-droop validation all pass.\n")
        println(io,"| Case | Status | Accepted | Validated local witness? | Physical | Exact droop max | Inner iterations | Seconds | Objective |\n|---|---|---:|---|---:|---:|---:|---:|---:|")
        for r in rows
            d=get(r,"ccopt",Dict{String,Any}()); a=get(r,"exact_droop_audit",Dict{String,Any}())
            witness=get(r,"valid",false) ? "yes" : "unknown (not infeasible)"
            println(io,"| ",r["name"]," | ",get(r,"status","ERROR")," | ",get(r,"valid",false)," | ",witness,
                " | ",get(r,"physical_valid",false)," | ",get(a,"max_residual_pu","—"),
                " | ",get(d,"inner_iterations","—")," | ",get(r,"elapsed_seconds","—"),
                " | ",get(r,"objective","—")," |")
        end
        println(io,"\nCCOpt internal primal/dual/complementarity figures are retained in each `*-diagnostics.json`; they are relaxed-NLP diagnostics, not a certificate of the original MPCC. The direct curve audit is the physical droop acceptance criterion.")
    end
end

abspath(PROGRAM_FILE)==(@__FILE__) && s1_ccopt_policy_matrix(abspath(ARGS[1]))
