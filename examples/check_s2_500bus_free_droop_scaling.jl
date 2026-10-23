# Optimizer-free equivalence and Jacobian checks for droop-only scaling.
include("s2_500bus_network_reduction.jl")
function fdc_scaling_check()
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    x=el_context();seed=el_read_point(joinpath(S2500_OUT,"response_continuation/demand-10625-a06");stage="feasibility")
    models=Any[];checks=Any[]
    for normalized in (false,true)
        b=el_build(x,(1.0625,),Contingency[];seed,fixed_controller=false,restore=false,
            zero_dr=true,zero_shedding=true,penalty_proxies=false,
            ac_builder=nr_build_ac,droop_normalization=normalized)
        m=b.m;@objective(m,Min,0.)
        # Only droop parameters are normalized; all equipment is still physical.
        for (id,p) in b.parameters
            reference=DroopSettings(seed.study.case.controls[id])
            ranges=DroopOPF._joint_droop_policy(x.study.case,x.controls[id]).ranges
            for key in keys(p)
                q=getfield(p,key);expected=getfield(reference,key)
                got=q isa Real ? q : JuMP.value(v->something(start_value(v),0.),q)
                @assert isapprox(got,expected;atol=1e-12,rtol=1e-12)
                if !(q isa Real)
                    lo=q isa VariableRef ? lower_bound(q) : JuMP.value(lower_bound,q)
                    hi=q isa VariableRef ? upper_bound(q) : JuMP.value(upper_bound,q)
                    @assert isapprox(lo,first(getfield(ranges,key));atol=1e-12,rtol=1e-12)
                    @assert isapprox(hi,last(getfield(ranges,key));atol=1e-12,rtol=1e-12)
                end
            end
        end
        ev=JuMP.NLPEvaluator(m);JuMP.MOI.initialize(ev,[:Jac])
        structure=JuMP.MOI.jacobian_structure(ev);nc=maximum(first,structure)
        vars=all_variables(m);point=[something(start_value(v),0.) for v in vars]
        values=zeros(nc);JuMP.MOI.eval_constraint(ev,values,point)
        jac=zeros(length(structure));JuMP.MOI.eval_constraint_jacobian(ev,jac,point)
        cols=findall(v->startswith(name(v),"shared_"),vars)
        choices=unique([first(cols),cols[2],cols[end-1],last(cols)])
        errors=Float64[]
        for col in choices
            h=normalized ? 1e-7 : max(1e-9,abs(point[col])*1e-7)
            xp=copy(point);xm=copy(point);xp[col]+=h;xm[col]-=h
            cp=zeros(nc);cm=zeros(nc);JuMP.MOI.eval_constraint(ev,cp,xp);JuMP.MOI.eval_constraint(ev,cm,xm)
            exact=zeros(nc)
            for (i,(row,j)) in enumerate(structure);j==col && (exact[row]+=jac[i]);end
            push!(errors,maximum(abs.((cp-cm)/(2h)-exact)./(1 .+abs.(exact))))
        end
        @assert maximum(errors)<1e-4
        @assert !has_values(m)
        push!(checks,(;normalized,shared_parameter_variables=length(cols),
            columns=[name(vars[i]) for i in choices],scaled_jacobian_errors=errors,passed=true))
        push!(models,(;values,variables=num_variables(m),constraints=num_constraints(m;count_variable_in_set_constraints=true)))
    end
    difference=maximum(abs.(models[1].values-models[2].values))
    @assert difference<1e-9
    @assert models[1].variables==models[2].variables
    @assert models[1].constraints==models[2].constraints
    out=joinpath(S2500_OUT,"free_droop_continuation");mkpath(out)
    fd_save(joinpath(out,"scaling_checks.json"),(;optimizer_calls=0,checks,
        nonlinear_start_values_max_difference=difference,physical_parameter_bounds_unchanged=true,
        equipment_normalization=false,passed=true))
    println("FREE DROOP SCALING CHECK ",checks," max difference=",difference)
end
abspath(PROGRAM_FILE)==(@__FILE__) && fdc_scaling_check()
