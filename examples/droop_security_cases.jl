using DroopOPF

"""Three-bus full N-1 reference with a binding transfer limit and two droops."""
function droop_security_case(; demand=0.6, rating=0.36)
    network = ACNetwork([Bus(10;reference=true),Bus(20),Bus(30)], [
        Branch(11,10,20;resistance=.01,reactance=.1,thermal_limit=rating,
            kind=:transformer,tap_ratio=1.0),
        Branch(22,20,30;resistance=.01,reactance=.1,thermal_limit=2.0),
        Branch(33,10,30;resistance=.01,reactance=.1,thermal_limit=2.0)])
    generators = [Generator(id,bus;p_min=0.,p_max=1.2,q_min=-1.,q_max=1.,
        initial_p=p,initial_q=0.) for (id,bus,p) in [(7,10,.5),(9,20,.1)]]
    controls = [VoltVarDroop(VoltageSchedule(1.;v_db_low=.99,v_db_high=1.01),
        slope,0.,ReactiveCapability(p_min=0.,p_max=1.2,q_min=-1.,q_max=1.))
        for slope in (.05,.075)]
    Case("droop-security-three-bus";base_power=100.,base_frequency=50.,network,
        loads=[Load(1,30;p=demand,q=.15)],generators,controls,
        attachments=[GeneratorControlAttachment(g.id,i,RegulatedLocation(:bus,g.bus_id))
            for (i,g) in enumerate(generators)])
end

"""Declared synthetic droop overlay: exact base Q and voltage anchor, no network edits.

A reference selected by an AVR/FreeQ solve is an initialization convention,
not measured controller data. All selected available units receive saturated
Volt–VAr controls; unselected units retain free Q within their original limits.
"""
function security_droop_overlay(case, base; control_count=length(case.generators),
    width=0.003, voltage_span=0.04)
    validate_equilibrium(case,base).valid || error("overlay anchor failed AC validation")
    buses = Dict(b.id=>i for (i,b) in enumerate(case.network.buses))
    candidates = sort([g for g in case.generators if g.available && g.q_max>g.q_min];by=g->g.id)
    selected = candidates[1:min(control_count,length(candidates))]
    controls = VoltVarDroop[]
    attachments = GeneratorControlAttachment[]
    for g in selected
        i = findfirst(x->x.id==g.id,case.generators)
        v = base.vm[buses[g.bus_id]]
        q = clamp(base.qg[i],g.q_min,g.q_max)
        cap = ReactiveCapability(p_min=g.p_min,p_max=g.p_max,q_min=g.q_min,q_max=g.q_max)
        push!(controls,VoltVarDroop(VoltageSchedule(v;v_db_low=v-width,v_db_high=v+width),
            voltage_span/(g.q_max-g.q_min),q,cap))
        push!(attachments,GeneratorControlAttachment(g.id,length(controls),RegulatedLocation(:bus,g.bus_id)))
    end
    overlay = Case(case.id*"-droop-security";base_power=case.base_power,
        base_frequency=case.base_frequency,network=case.network,loads=case.loads,
        generators=case.generators,controls,attachments)
    validate_equilibrium(overlay,base).valid || error("exact droop anchor failed validation")
    overlay
end

"""Declared proportional-regime numerical start for the three-bus reference."""
function droop_security_start(case)
    ACState([.98,.98,.95],[0.,-.01,-.04],
        [g.initial_p for g in case.generators],
        [droop_response(case.controls[i],.98;p=g.initial_p) for (i,g) in enumerate(case.generators)])
end
