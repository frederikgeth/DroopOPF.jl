include("s1_diagnostics.jl")
include("scaling_case.jl")
function s1_convergence(out)
    mkpath(out);rows=[]
    seed=solve_opf(m72_case();smooth_epsilon=1e-6,initial_state=m5_initial_state(m72_case()))
    for n in (4,32)
        case=scaling_case(n;heterogeneous=true)
        baseline=optimize_joint_design(case;initial_state=scaling_start(seed.state,n),smooth_epsilon=1e-6,
            optimizer_attributes=Dict("bound_relax_factor"=>0.,"mu_strategy"=>"adaptive","tol"=>1e-8))
        validate_joint_design(case,baseline).valid || error("baseline must validate")
        write_study(joinpath(out,"study-$n.json"),Study(case))
        write_joint_design(joinpath(out,"start-$n.json"),baseline)
        p=scaling_policies(n)
        for t in (false,true),s in (false,true),d in (false,true)
            policies=(tap_controls=t ? p.tap_controls : TapControl[],shunt_controls=s ? p.shunt_controls : ShuntControl[],droop_controls=d ? p.droop_controls : DroopControl[])
            row=s1_solve(out,"n$n-$(Int(t))$(Int(s))$(Int(d))",case,baseline.opf.state;policies)
            push!(rows,row)
        end
        # Equivalent scalar multiplication of the entire objective, not a design penalty.
        push!(rows,s1_solve(out,"n$n-111-scaled",case,baseline.opf.state;policies=p,options=Dict("obj_scaling_factor"=>1000.)))
        write(joinpath(out,"summary.json"),JSON.json([Dict(k=>v for (k,v) in r if k ∉ ("trace","bounds")) for r in rows];pretty=true))
    end
end
s1_convergence(abspath(ARGS[1]))
