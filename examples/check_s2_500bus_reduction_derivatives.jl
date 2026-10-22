# Independent finite differences of the assembled nonlinear constraints.
# This file builds a model and evaluates derivatives; it never optimizes.
include("s2_500bus_network_reduction.jl")

function nr_check_derivatives()
    rows=Any[];x=el_context()
    seed=el_read_point(joinpath(EL_OUT,"dispatch-recovery/demand-1.05/zero-shedding");stage="feasibility")
    for mode in ("all","independent-degree3")
        ENV["NR_ELIMINATION_MODE"]=mode
        b=el_build(x,(1.05,),Contingency[];seed,fixed_controller=true,restore=false,
            zero_dr=true,zero_shedding=true,penalty_proxies=false,ac_builder=nr_build_ac)
        m=b.m;@objective(m,Min,0.)
        ev=JuMP.NLPEvaluator(m);JuMP.MOI.initialize(ev,[:Jac])
        structure=JuMP.MOI.jacobian_structure(ev)
        nc=maximum(first,structure);vars=all_variables(m)
        point=[something(start_value(v),0.) for v in vars]
        j0=zeros(length(structure));JuMP.MOI.eval_constraint_jacobian(ev,j0,point)
        controlled=Set(a.location.bus_id for a in seed.study.case.attachments)
        retained=nr_map(b.blocks[1].case).r
        # Test the new voltage reconstruction, away from the pre-existing
        # extremely narrow soft-clipping transitions in generator droop.
        buses=filter(i->!(seed.study.case.network.buses[i].id in controlled),retained)[1:2]
        choices=unique([findfirst(==(a),vars) for i in buses for a in (b.blocks[1].v.vm[i],b.blocks[1].v.va[i])])
        append!(choices,[findfirst(v->occursin("tap_",name(v)),vars),findfirst(v->occursin("shunt_B",name(v)),vars)])
        errors=Float64[]
        for col in choices
            h=1e-7;xp=copy(point);xm=copy(point);xp[col]+=h;xm[col]-=h
            cp=zeros(nc);cm=zeros(nc)
            JuMP.MOI.eval_constraint(ev,cp,xp);JuMP.MOI.eval_constraint(ev,cm,xm)
            exact=zeros(nc)
            for (k,(row,j)) in enumerate(structure);j==col && (exact[row]+=j0[k]);end
            delta=(cp-cm)/(2h)-exact
            push!(errors,maximum(abs.(delta)./(1 .+abs.(exact))))
        end
        passed=maximum(errors)<1e-5
        push!(rows,(;mode,columns=[name(vars[i]) for i in choices],scaled_jacobian_errors=errors,passed))
        passed || error("Finite-difference reconstruction derivative regression failed")
    end
    fd_save(joinpath(NR_OUT,"derivative_checks.json"),(;optimizer_calls=0,rows,passed=all(r.passed for r in rows)))
    println("NETWORK REDUCTION DERIVATIVE CHECKS ",rows)
end

abspath(PROGRAM_FILE)==(@__FILE__) && nr_check_derivatives()
