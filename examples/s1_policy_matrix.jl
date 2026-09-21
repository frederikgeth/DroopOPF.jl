include("s1_restart_policy.jl")
function s1_policy_matrix(out,solver;control_normalization=:none,droop_q_bounds=:explicit,
    droop_q_formulation=:explicit)
    mkpath(out);rows=[]
    for n in (118,300),factor in (1.,1.05),start_kind in (:anchor,:flat_low,:flat_high)
        source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case$(n)_ieee.m")
        original=load_matpower_case(source;base_frequency=60.)
        anchor=read_joint_design(joinpath(@__DIR__,"..","artifacts","s1_public_controls","public$n-baseline-design.json"))
        case,p,_=s1_public_overlay(original,anchor,source;bank_count=n==118 ? 12 : 32)
        case=s1_load(case,factor)
        state=start_kind==:anchor ? anchor.opf.state : s1_flat(case)
        policies=start_kind==:anchor ? p : s1_reseed(case,p;fraction=start_kind==:flat_low ? .2 : .8)
        name="public$n-load$factor-$solver-$start_kind"
        row,result=s1_run_policy(out,name,case,state;policies,solver,control_normalization,
            droop_q_bounds,droop_q_formulation,
            tags=Dict("load_factor"=>factor,"start"=>string(start_kind)))
        row["valid"] && (row["source_audit"]=s1_source_audit(case,result,source))
        push!(rows,row);write(joinpath(out,"summary.json"),JSON.json(rows;pretty=true))
        println("POLICY ",name," valid=",row["valid"]," events=",row["events"]);flush(stdout)
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && s1_policy_matrix(abspath(ARGS[1]),Symbol(ARGS[2]);
    control_normalization=length(ARGS)>=3 ? Symbol(ARGS[3]) : :none,
    droop_q_bounds=length(ARGS)>=4 ? Symbol(ARGS[4]) : :explicit,
    droop_q_formulation=length(ARGS)>=5 ? Symbol(ARGS[5]) : :explicit)
