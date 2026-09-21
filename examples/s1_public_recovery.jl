include("s1_public_controls.jl")

"""Conservative uniform smooth/exact Q bound for the declared slope envelope."""
function s1_epsilon_bound(case,p;droop_tolerance=1e-5,fraction=.1)
    droop_tolerance>0 && 0<fraction<1 || throw(ArgumentError("invalid smoothing budget"))
    byid=Dict(c.control_id=>c for c in p.droop_controls)
    coefficients=Float64[]
    for (i,c) in enumerate(case.controls)
        m=haskey(byid,i) ? DroopOPF._joint_droop_policy(case,byid[i]).ranges.slope[1] : c.slope
        qscale=min(c.q_at_deadband-c.capability.q_min,c.capability.q_max-c.q_at_deadband)
        push!(coefficients,2log(2.)*(1/m+qscale))
    end
    coefficient=maximum(coefficients;init=0.)
    epsilon=coefficient==0 ? 1e-6 : min(1e-6,fraction*droop_tolerance/coefficient)
    (epsilon=epsilon,coefficient=coefficient,max_curve_gap=coefficient*epsilon)
end

function s1_public_recovery(out)
    mkpath(out);rows=[]
    for n in (118,300)
        source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case$(n)_ieee.m")
        case=load_matpower_case(source;base_frequency=60.)
        anchor=read_joint_design(joinpath(@__DIR__,"..","artifacts","s1_public_controls","public$n-baseline-design.json"))
        c,p,metadata=s1_public_overlay(case,anchor,source;bank_count=n==118 ? 12 : 32)
        budget=s1_epsilon_bound(c,p)
        write(joinpath(out,"public$n-smoothing-budget.json"),JSON.json(DroopOPF._json_data(budget);pretty=true))
        for solver in (:ipopt,:madnlp)
            # Bound push changes initialization only; it neither relaxes nor tightens a bound.
            options=Dict{String,Any}("bound_push"=>1e-8,"bound_frac"=>1e-8)
            row,r=s1_attempt(out,"public$n-$solver-smallpush",c,anchor.opf.state;policies=p,solver,options,
                tags=Dict("study"=>"bound_push"))
            get(row,"physical_valid",false) && (row["source_audit"]=s1_source_audit(c,r,source))
            push!(rows,row);s1_summary(out,rows)
            state=anchor.opf.state;policies=p
            for epsilon in (1e-4,1e-5,1e-6,budget.epsilon)
                row,r=s1_attempt(out,"public$n-$solver-cont-$epsilon",c,state;policies,solver,epsilon,options,
                    tags=Dict("study"=>"public_continuation","final"=>epsilon==budget.epsilon))
                get(row,"physical_valid",false) && (row["source_audit"]=s1_source_audit(c,r,source))
                push!(rows,row);s1_summary(out,rows)
                if !isnothing(r) && !isnothing(r.opf.state) && get(row,"solver_valid",false) && get(row,"policy_valid",false)
                    state=r.opf.state;policies=s1_reseed(c,p;result=r)
                end
            end
            # Keep the installed control family/reference fixed while increasing demand.
            for factor in (1.025,1.05)
                stressed=s1_load(c,factor)
                row,r=s1_attempt(out,"public$n-$solver-load-$factor",stressed,state;policies,solver,
                    epsilon=budget.epsilon,options,tags=Dict("study"=>"load_continuation","load_factor"=>factor))
                get(row,"physical_valid",false) && (row["source_audit"]=s1_source_audit(stressed,r,source))
                push!(rows,row);s1_summary(out,rows)
                if row["valid"]
                    state=r.opf.state;policies=s1_reseed(c,p;result=r)
                end
            end
        end
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && s1_public_recovery(abspath(ARGS[1]))
