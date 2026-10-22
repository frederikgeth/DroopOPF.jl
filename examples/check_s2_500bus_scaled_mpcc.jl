# Optimizer-free warm-point and projection equivalence checks.
include("s2_500bus_scaled_mpcc.jl")
function sdq_scaled_check()
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    phase=JSON.parsefile(joinpath(SDQ_OUT,"summary-ipopt-10000.json"));folder=joinpath(S2500_OUT,phase["selected"])
    study=read_study(joinpath(folder,"optimized-1.0.json"));result=read_scopf_result(joinpath(folder,"result-1.0.json"))
    c=study.case;m=Model(CCOpt.Optimizer);DroopOPF.MathOptComplements.Bridges.add_all_bridges(m)
    controls=s214_multi_controls(fd_inputs(500).base);parameters=Dict{Int,NamedTuple}()
    for control in controls
        p=DroopOPF._joint_droop_policy(c,control);names=keys(p.ranges);initial=DroopSettings(c.controls[control.control_id])
        parameters[control.control_id]=NamedTuple{names}(Tuple(DroopOPF._droop_design_variable(m,"shared_$(control.control_id)_$k",getfield(p.ranges,k),getfield(initial,k);normalize=true) for k in names))
    end
    taps=[TapControl(t.branch_id;lower=t.lower,upper=t.upper,nominal=t.nominal,initial=result.tap_settings[:base][t.branch_id]) for t in study.tap_controls]
    banks=[ShuntControl(t.bank_id;lower=t.lower,upper=t.upper,nominal=t.nominal,initial=result.shunt_settings[:base][t.bank_id]) for t in study.shunt_controls]
    _,v=sdq_scaled_mpcc(c;silent=true,shared_model=m,scenario_prefix="base_",set_objective=false,
        initial_state=result.states[:base],reactive_assignments=nothing,tap_controls=taps,shunt_controls=banks,
        normalize_controls=false,droop_parameter_variables=parameters)
    # MOI's generic feasibility checker has no Complements distance method.
    # Check each pair directly, then use it for every remaining constraint.
    checked_pairs=0
    for (F,S) in list_of_constraint_types(m)
        S<:JuMP.MOI.Complements || continue
        for ref in all_constraints(m,F,S)
            pair=[start_value(q) for q in constraint_object(ref).func]
            @assert length(pair)==2 && minimum(pair)>=-1e-12 && abs(prod(pair))<=1e-12
            checked_pairs+=1;delete(m,ref)
        end
    end
    @assert checked_pairs==102
    violations=JuMP.primal_feasibility_report(x->something(start_value(x),0.),m;atol=1e-7)
    @assert isempty(violations)
    @assert !has_values(m)
    @assert count(x->startswith(JuMP.name(x),"shared_"),all_variables(m))==102
    maximum_equivalence_error=0.;samples=0
    for d in c.controls
        span=d.capability.q_max-d.capability.q_min
        for raw in (d.capability.q_min-2span,d.capability.q_min,d.capability.q_min+.37span,d.capability.q_max,d.capability.q_max+2span)
            q=clamp(raw,d.capability.q_min,d.capability.q_max)
            lo=max(q-raw,0.)/span;hi=max(raw-q,0.)/span
            sl=(q-d.capability.q_min)/span;su=(d.capability.q_max-q)/span
            reconstructed=q-span*lo+span*hi
            @assert min(sl,su,lo,hi)>=0 && sl*lo==0 && su*hi==0
            maximum_equivalence_error=max(maximum_equivalence_error,abs(raw-reconstructed));samples+=1
        end
    end
    @assert maximum_equivalence_error<1e-12
    fd_save(joinpath(SDQ_OUT,"scaled-mpcc-checks.json"),(;optimizer_calls=0,passed=true,base_warm_point_feasible=true,
        free_shared_parameters=102,checked_complementarity_pairs=checked_pairs,projection_samples=samples,maximum_equivalence_error,violated_constraints=length(violations)))
    println("SCALED MPCC CHECK PASSED; optimizer calls=0")
end
abspath(PROGRAM_FILE)==(@__FILE__) && sdq_scaled_check()
