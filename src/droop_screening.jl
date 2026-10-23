# Optional pre-solve risk predictor. It never replaces an exact AC audit.
function _droop_screening_diagnostics(case::Case, base::ACState, outage::Contingency;
    participation, voltage_guard, loading_threshold, reactive_guard)
    uncertain(reason) = (; safe=false, reason, iterations=0, residual=nothing,
        voltage_margin=nothing, q_reserve_fraction=nothing, predicted_loading=nothing)
    any(g->!isnothing(g.s_rated),case.generators) && return uncertain(:apparent_capability_guard_unsupported)
    isempty(case.controls) && return uncertain(:droop_guard_unsupported)
    net=case.network; n=length(net.buses)
    # Fixed-base branch prediction supports complete legacy droop assignments.
    # Mixed free-Q/explicit controls must go through their exact assessment path.
    active=[(i,g) for (i,g) in enumerate(case.generators) if g.available]
    attachments=Dict(a.generator_id=>a for a in case.attachments)
    all(haskey(attachments,g.id) for (_,g) in active) || return uncertain(:droop_guard_unsupported)
    isempty(outage.generator_ids) && length(outage.branch_ids)==1 || return uncertain(:droop_guard_unsupported)
    weights=[(_active_response_bounds(case,i)[2] > _active_response_bounds(case,i)[1] ? Float64(get(participation,g.id,0.0)) : 0.0) for (i,g) in active]
    all(isfinite,weights) && all(>=(0),weights) && sum(weights)>0 || return uncertain(:droop_guard_unsupported)
    weights ./=sum(weights)
    bounds=Dict(g.id=>(max(g.q_min,case.controls[attachments[g.id].control_id].capability.q_min),
        min(g.q_max,case.controls[attachments[g.id].control_id].capability.q_max)) for (_,g) in active)
    all(hi>lo for (lo,hi) in values(bounds)) || return uncertain(:droop_guard_unsupported)
    # Local headroom cannot be hidden by another generator's ample reserves.
    reserve=minimum(min(base.qg[i]-bounds[g.id][1],bounds[g.id][2]-base.qg[i])/(bounds[g.id][2]-bounds[g.id][1]) for (i,g) in active)
    reserve<=reactive_guard && return (;safe=false,reason=:droop_local_reserve_guard,
        iterations=0,residual=0.0,voltage_margin=nothing,q_reserve_fraction=reserve,predicted_loading=nothing)
    scenario=scenario_case(case,outage)
    idx=_bus_indices(net); ref=findfirst(b->b.reference,net.buses)
    isnothing(ref) && return uncertain(:droop_guard_unsupported)
    angles=[i for i in 1:n if i!=ref]
    x=vcat(base.va[angles],base.vm,0.0)
    function state_at(values)
        va=copy(base.va);va[angles]=values[1:n-1];vm=values[n:2n-1]
        all(>(0),vm) || throw(ArgumentError("nonpositive predicted voltage"))
        pg=copy(base.pg);qg=copy(base.qg)
        for ((i,g),weight) in zip(active,weights)
            pg[i]=weight == 0 ? base.pg[i] : clamp(base.pg[i]+weight*values[end],
                _active_response_bounds(case,i)...)
            a=attachments[g.id];control=case.controls[a.control_id]
            qg[i]=clamp(evaluate(droop_curve(control),vm[idx[a.location.bus_id]]),
                control.capability.q_min,control.capability.q_max)
        end
        ACState(vm,va,pg,qg)
    end
    residual(values)=power_balance(scenario,state_at(values)).vector
    iterations=0
    try
        for k in 1:8
            r=residual(x);iterations=k
            maximum(abs,r)<=1e-5 && break
            # Central differences follow the actual saturated/deadband law.
            J=zeros(length(r),length(x));h=1e-5
            for j in eachindex(x)
                plus=copy(x);minus=copy(x);plus[j]+=h;minus[j]-=h
                J[:,j]=(residual(plus)-residual(minus))/(2h)
            end
            all(isfinite,J) && cond(J)<1e10 || return uncertain(:droop_prediction_uncertain)
            step=-(J\r)
            all(isfinite,step) || return uncertain(:droop_prediction_uncertain)
            scale=min(1.0,0.04/max(maximum(abs,step[n:2n-1]),1e-12),
                0.3/max(maximum(abs,step[1:n-1]),1e-12))
            accepted=false
            for damping in (1.0,0.5,0.25,0.125,0.0625)
                trial=x+scale*damping*step
                minimum(trial[n:2n-1])>0 || continue
                if maximum(abs,residual(trial))<maximum(abs,r)
                    x=trial;accepted=true;break
                end
            end
            accepted || return uncertain(:droop_prediction_uncertain)
        end
        state=state_at(x);error=maximum(abs,residual(x))
        error<=1e-5 || return (;safe=false,reason=:droop_prediction_uncertain,
            iterations,residual=error,voltage_margin=nothing,q_reserve_fraction=nothing,predicted_loading=nothing)
        margin=minimum(min(state.vm[i]-b.v_min,b.v_max-state.vm[i]) for (i,b) in enumerate(net.buses))
        qreserve=minimum(min(state.qg[i]-bounds[g.id][1],bounds[g.id][2]-state.qg[i])/(bounds[g.id][2]-bounds[g.id][1]) for (i,g) in active)
        pmargin=minimum(min(state.pg[i]-g.p_min,g.p_max-state.pg[i]) for (i,g) in active)
        control_p_margin=minimum(min(state.pg[i]-case.controls[attachments[g.id].control_id].capability.p_min,
            case.controls[attachments[g.id].control_id].capability.p_max-state.pg[i]) for (i,g) in active)
        flow=branch_flows(scenario.network,state)
        loading=maximum(max(abs(flow.from[i]),abs(flow.to[i]))/b.thermal_limit
            for (i,b) in enumerate(scenario.network.branches) if b.available;init=0.0)
        regime_changed=any(begin
            a=attachments[g.id];control=case.controls[a.control_id];i=idx[a.location.bus_id]
            droop_regime(control,base.vm[i])!=droop_regime(control,state.vm[i])
        end for (_,g) in active)
        reason=regime_changed ? :droop_regime_transition_guard : margin<=voltage_guard ? :droop_voltage_guard :
            qreserve<=reactive_guard ? :droop_projected_reserve_guard :
            min(pmargin,control_p_margin)<=1e-4 ? :droop_active_limit_guard :
            loading>=loading_threshold ? :droop_apparent_guard : :droop_prediction_clear
        (;safe=reason==:droop_prediction_clear,reason,iterations,residual=error,
            voltage_margin=margin,q_reserve_fraction=qreserve,predicted_loading=loading,
            regime_changed, response_fraction=maximum(abs(state.qg[i]-base.qg[i])/(bounds[g.id][2]-bounds[g.id][1]) for (i,g) in active),
            voltage_shift=maximum(abs.(state.vm-base.vm)))
    catch error
        error isa InterruptException && rethrow()
        uncertain(:droop_prediction_uncertain)
    end
end
