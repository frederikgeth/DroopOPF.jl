include("s1_public_recovery.jl")
function s1_droop_error_components(case,result)
    physical=with_joint_settings(case,result);state=result.opf.state
    bi=Dict(b.id=>i for (i,b) in enumerate(physical.network.buses))
    gi=Dict(g.id=>i for (i,g) in enumerate(physical.generators))
    rows=[]
    for a in physical.attachments
        i=gi[a.generator_id];physical.generators[i].available || continue
        c=physical.controls[a.control_id];v=state.vm[bi[a.location.bus_id]]
        exact=clamp(evaluate(droop_curve(c),v),c.capability.q_min,c.capability.q_max)
        eq=DroopOPF.reactive_smoothing_epsilon(c,result.opf.smooth_reactive_relative_epsilon;
            absolute_epsilon=result.opf.smooth_reactive_epsilon)
        smooth=DroopOPF._smooth_droop_value(c,v,result.opf.smooth_epsilon,eq)
        push!(rows,Dict("control_id"=>a.control_id,"generator_id"=>a.generator_id,
            "smooth_equation_residual"=>state.qg[i]-smooth,
            "approximation_gap"=>smooth-exact,"exact_residual"=>state.qg[i]-exact))
    end
    Dict("controllers"=>rows,"smooth_residual_max"=>maximum(abs(x["smooth_equation_residual"]) for x in rows;init=0.),
        "approximation_gap_max"=>maximum(abs(x["approximation_gap"]) for x in rows;init=0.))
end
function s1_normalization_refinement(out)
    mkpath(out);rows=[];audit=[]
    for solver in (:ipopt,:madnlp)
        folder=joinpath(@__DIR__,"..","artifacts","s1_normalized_$solver")
        policies=JSON.parsefile(joinpath(folder,"summary.json"))
        length(policies)==12 || error("complete normalization matrix first")
        for policy in policies
            last=policy["attempts"][end]
            physical=get(last,"physical",nothing)
            candidate=!policy["valid"] && get(last,"solver_valid",false) && !isnothing(physical) && Set(physical["violations"])==Set(["droop"])
            candidate || continue
            n=policy["buses"];factor=policy["tags"]["load_factor"]
            source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case$(n)_ieee.m")
            original=load_matpower_case(source;base_frequency=60.)
            anchor=read_joint_design(joinpath(@__DIR__,"..","artifacts","s1_public_controls","public$n-baseline-design.json"))
            case,p,_=s1_public_overlay(original,anchor,source;bank_count=n==118 ? 12 : 32)
            case=s1_load(case,factor)
            seed=read_joint_design(joinpath(folder,last["name"]*"-design.json"))
            components=s1_droop_error_components(case,seed)
            eligible=components["smooth_residual_max"]<=1e-6
            push!(audit,Dict("source_attempt"=>last["name"],"eligible"=>eligible,"components"=>components))
            eligible || continue
            row,result=s1_attempt(out,policy["name"]*"-refine",case,seed.opf.state;
                policies=s1_reseed(case,p;result=seed),solver,epsilon=1e-7,control_normalization=:bounds,
                deadline_ns=time_ns()+UInt64(60_000_000_000),
                options=Dict("bound_push"=>1e-8,"bound_frac"=>1e-8),
                tags=Dict("study"=>"separate_smoothing_refinement","source_attempt"=>last["name"],
                    "source_epsilon"=>1e-6,"load_factor"=>factor,"source_components"=>components,
                    "budget_note"=>"one extra 1000-iteration/60-second attempt; excluded from frozen normalization acceptance counts"))
            if !isnothing(result) && get(row,"policy_valid",false) && !isnothing(get(row,"physical",nothing))
                row["droop_error_components"]=s1_droop_error_components(case,result)
            end
            push!(rows,row);s1_summary(out,rows)
        end
    end
    write(joinpath(out,"eligibility.json"),JSON.json(audit;pretty=true))
    s1_summary(out,rows)
end
abspath(PROGRAM_FILE)==(@__FILE__) && s1_normalization_refinement(abspath(ARGS[1]))
