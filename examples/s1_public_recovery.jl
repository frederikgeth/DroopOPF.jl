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
