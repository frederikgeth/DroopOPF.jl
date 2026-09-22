include("s1_ccopt_policy_matrix.jl")

"""Exact droop-only feasibility ladder for frozen cells without a local witness.

For each target, taps and shunts are fixed to an admissible source design while
the target's droop parameters remain free. A validated result is a feasible
witness for the original joint problem, because fixing free controls defines a
subset of that problem. A failed attempt is deliberately reported as unknown.
"""
function s1_ccopt_droop_feasibility(frozen_out,out)
    frozen=JSON.parsefile(joinpath(frozen_out,"summary.json"))
    frozen_rows=frozen["rows"]
    targets=[c for c in s1_ccopt_policy_cells() if !any(get(r,"name","")=="public$(c.n)-load$(c.load_factor)-ccopt-$(c.start)" && get(r,"valid",false) for r in frozen_rows)]
    witnesses=Dict{Int,Vector{String}}()
    for n in (118,300)
        witnesses[n]=[r["name"] for r in frozen_rows if r["case_key"]["buses"]==n && get(r,"valid",false)]
    end
    mkpath(out); summary_path=joinpath(out,"summary.json")
    rows=isfile(summary_path) ? [Dict{String,Any}(string(k)=>v for (k,v) in r) for r in JSON.parsefile(summary_path)["rows"]] : Dict{String,Any}[]
    profile=Dict{String,Any}("max_iter"=>1000,"max_wall_time"=>60.,"sigma_min"=>1e-14,"tol"=>1e-11,"acceptable_tol"=>1e-11)
    options=Dict{String,Any}("relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14),"tol"=>1e-11,"acceptable_tol"=>1e-11)
    for target in targets
        target_name="public$(target.n)-load$(target.load_factor)-ccopt-$(target.start)"
        sources=["public$(target.n)-baseline-design"; witnesses[target.n]]
        for source_name in sources
            name="$(target_name)-droop-only-from-$(source_name)"
            any(get(r,"name",nothing)==name for r in rows) && continue
            source_path=source_name=="public$(target.n)-baseline-design" ?
                joinpath(@__DIR__,"..","artifacts","s1_public_controls",source_name*".json") :
                joinpath(frozen_out,source_name*"-design.json")
            source_design=read_joint_design(source_path)
            source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case$(target.n)_ieee.m")
            original=load_matpower_case(source;base_frequency=60.)
            anchor=read_joint_design(joinpath(@__DIR__,"..","artifacts","s1_public_controls","public$(target.n)-baseline-design.json"))
            case,policies,_=s1_public_overlay(original,anchor,source;bank_count=target.n==118 ? 12 : 32)
            case=s1_load(case,target.load_factor)
            fixed_case=with_joint_settings(case,source_design)
            droop_only=(tap_controls=TapControl[],shunt_controls=ShuntControl[],droop_controls=policies.droop_controls)
            # A same-size accepted state is a useful seed; the anchor state is used otherwise.
            initial=!isnothing(source_design.opf.state) ? source_design.opf.state : anchor.opf.state
            tags=Dict{String,Any}("matrix"=>"s1_ccopt_droop_feasibility_v1","target"=>target_name,
                "fixed_tap_shunt_source"=>source_name,"free_controls"=>"droop only",
                "interpretation"=>"valid result proves a local feasible witness for the full joint problem; invalid result is unknown, not infeasible")
            row,_=s1_ccopt_attempt(out,name,fixed_case,initial;policies=droop_only,tags,option_overrides=options)
            row["solution_status"]=get(row,"valid",false) ? "yes: validated conditional witness, hence joint-feasible" : "unknown: this fixed-setting droop-only attempt did not validate"
            push!(rows,row)
            write(summary_path,JSON.json(Dict("schema"=>"s1-ccopt-droop-feasibility-v1","profile"=>profile,"rows"=>rows);pretty=true)*"\n")
            println("DROOP FEASIBILITY ",name," valid=",get(row,"valid",false)); flush(stdout)
        end
    end
    s1_ccopt_droop_feasibility_report(out,rows)
end

function s1_ccopt_droop_feasibility_report(out,rows)
    open(joinpath(out,"report.md"),"w") do io
        println(io,"# CCOpt frozen droop-only feasibility ladder\n")
        println(io,"Taps and shunts are fixed to an admissible source design and exact PWL droop parameters are optimized. **Accepted** means a validated conditional witness and therefore a solution of the full joint problem. **Unknown** is not evidence of infeasibility.\n")
        println(io,"| Target / fixed source | Status | Accepted | Does this establish a full-joint local witness? | Exact droop max |\n|---|---|---:|---|---:|")
        for r in rows
            a=get(r,"exact_droop_audit",Dict{String,Any}()); proof=get(r,"valid",false) ? "yes" : "no — unknown"
            println(io,"| ",r["name"]," | ",get(r,"status","ERROR")," | ",get(r,"valid",false)," | ",proof," | ",get(a,"max_residual_pu","—")," |")
        end
    end
end

abspath(PROGRAM_FILE)==(@__FILE__) && s1_ccopt_droop_feasibility(abspath(ARGS[1]),abspath(ARGS[2]))
