"""Physical-unit failure locations; mirrors validate_equilibrium default tolerances."""
function s1_failure_details(case,state;power_tolerance=1e-6,droop_tolerance=1e-5,
    limit_tolerance=1e-6,unavailable_tolerance=1e-8)
    rows=Dict{String,Any}[]
    function record(category,kind,id,component,error,tolerance)
        if !isfinite(error) || error>tolerance
            push!(rows,Dict("category"=>category,"equipment"=>kind,"id"=>id,
                "component"=>component,"violation_pu"=>error,"tolerance_pu"=>tolerance,
                "exceedance_pu"=>error-tolerance))
        end
    end
    b=power_balance(case,state)
    for (i,bus) in enumerate(case.network.buses)
        record("power_balance","bus",bus.id,"P",abs(b.active[i]),power_tolerance)
        record("power_balance","bus",bus.id,"Q",abs(b.reactive[i]),power_tolerance)
        record("voltage_min","bus",bus.id,"V",max(bus.v_min-state.vm[i],0),limit_tolerance)
        record("voltage_max","bus",bus.id,"V",max(state.vm[i]-bus.v_max,0),limit_tolerance)
    end
    for (i,g) in enumerate(case.generators)
        if g.available
            for (label,value,lo,hi) in (("p",state.pg[i],g.p_min,g.p_max),("q",state.qg[i],g.q_min,g.q_max))
                record("generator_$(label)_min","generator",g.id,label,max(lo-value,0),limit_tolerance)
                record("generator_$(label)_max","generator",g.id,label,max(value-hi,0),limit_tolerance)
            end
        else
            record("unavailable_generator","generator",g.id,"P/Q",max(abs(state.pg[i]),abs(state.qg[i])),unavailable_tolerance)
        end
    end
    flows=branch_flows(case.network,state)
    for (i,branch) in enumerate(case.network.branches)
        branch.available || continue
        for (terminal,s) in (("from",flows.from[i]),("to",flows.to[i]))
            record("branch_thermal","branch",branch.id,terminal,max(abs(s)-branch.thermal_limit,0),limit_tolerance)
        end
    end
    bi=Dict(b.id=>i for (i,b) in enumerate(case.network.buses))
    gi=Dict(g.id=>i for (i,g) in enumerate(case.generators))
    for a in case.attachments
        i=gi[a.generator_id];case.generators[i].available || continue
        c=case.controls[a.control_id]
        exact=clamp(evaluate(droop_curve(c),state.vm[bi[a.location.bus_id]]),c.capability.q_min,c.capability.q_max)
        record("droop","generator",a.generator_id,"control $(a.control_id), regulated bus $(a.location.bus_id)",abs(state.qg[i]-exact),droop_tolerance)
        record("control_active_power","generator",a.generator_id,"P",max(c.capability.p_min-state.pg[i],state.pg[i]-c.capability.p_max,0),limit_tolerance)
    end
    sort!(rows;by=x->isfinite(x["exceedance_pu"]) ? -x["exceedance_pu"] : -Inf)
end
