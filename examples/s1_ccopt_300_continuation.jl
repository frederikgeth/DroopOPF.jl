include("s1_ccopt_droop_feasibility.jl")

"""Continue the validated IEEE-300 nominal droop-only witness to +5% load."""
function s1_ccopt_300_continuation(frozen_out,droop_out,out;factors=1.01:0.01:1.05)
    seed_name="public300-load1.0-ccopt-anchor-droop-only-from-public300-baseline-design"
    seed=read_joint_design(joinpath(droop_out,seed_name*"-design.json"))
    source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case300_ieee.m")
    original=load_matpower_case(source;base_frequency=60.)
    anchor=read_joint_design(joinpath(@__DIR__,"..","artifacts","s1_public_controls","public300-baseline-design.json"))
    base,policies,_=s1_public_overlay(original,anchor,source;bank_count=32)
    fixed_base=with_joint_settings(base,anchor)
    droop_only=(tap_controls=TapControl[],shunt_controls=ShuntControl[],droop_controls=policies.droop_controls)
    options=Dict{String,Any}("relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14),"tol"=>1e-11,"acceptable_tol"=>1e-11)
    mkpath(out); summary_path=joinpath(out,"summary.json")
    rows=isfile(summary_path) ? [Dict{String,Any}(string(k)=>v for (k,v) in r) for r in JSON.parsefile(summary_path)["rows"]] : Dict{String,Any}[]
    current=seed.opf.state
    for factor in factors
        name="ieee300-droop-only-continuation-load$(factor)"
        retained=findfirst(r->get(r,"name",nothing)==name,rows)
        if !isnothing(retained)
            design_path=joinpath(out,name*"-design.json")
            if get(rows[retained],"valid",false) && isfile(design_path)
                current=read_joint_design(design_path).opf.state
                continue
            end
            break
        end
        case=s1_load(fixed_base,factor)
        tags=Dict{String,Any}("matrix"=>"s1_ccopt_300_continuation_v1","load_factor"=>factor,
            "initialization"=>"previous validated continuation state","free_controls"=>"droop only",
            "fixed_tap_shunt_source"=>"public300-baseline-design",
            "interpretation"=>"accepted 1.05 result establishes a full-joint local witness; failure stops this continuation path only")
        row,result=s1_ccopt_attempt(out,name,case,current;policies=droop_only,tags,option_overrides=options)
        row["solution_status"]=get(row,"valid",false) ? "yes: validated continuation witness" : "unknown: continuation path stopped"
        push!(rows,row)
        write(summary_path,JSON.json(Dict("schema"=>"s1-ccopt-300-continuation-v1","rows"=>rows);pretty=true)*"\n")
        println("CONTINUATION load=",factor," valid=",get(row,"valid",false)); flush(stdout)
        get(row,"valid",false) || break
        current=result.opf.state
    end
    s1_ccopt_300_continuation_report(out,rows)
end

function s1_ccopt_300_continuation_report(out,rows)
    open(joinpath(out,"report.md"),"w") do io
        println(io,"# IEEE 300 +5% exact-droop continuation\n")
        println(io,"Starts from the validated 1.00-load droop-only witness, fixes admissible anchor taps/shunts, and increases load by 1% per accepted step. A valid 1.05 result proves a local witness for the free joint model. A stop identifies only a failed continuation path.\n")
        println(io,"| Load factor | Status | Accepted | Exact droop max |\n|---:|---|---:|---:|")
        for r in rows
            a=get(r,"exact_droop_audit",Dict{String,Any}()); println(io,"| ",get(get(r,"tags",Dict()),"load_factor","—")," | ",get(r,"status","ERROR")," | ",get(r,"valid",false)," | ",get(a,"max_residual_pu","—")," |")
        end
    end
end

abspath(PROGRAM_FILE)==(@__FILE__) && s1_ccopt_300_continuation(abspath(ARGS[1]),abspath(ARGS[2]),abspath(ARGS[3]))
