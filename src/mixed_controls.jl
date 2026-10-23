"""Assign AVR to the largest fraction of online positive-Pmax generators.

Round half upward by count; ties use ascending generator ID. `ratings` must
explicitly supply positive system-base apparent ratings for every eligible unit.
`voltage_targets` must supply an AVR target for each selected generator.
Remaining online units retain their attached volt-var curves; offline records
remain offline and receive FreeQ (no active control equation).
"""
function mixed_reactive_controls(case::Case;avr_fraction=.30,ratings,voltage_targets)
    isfinite(avr_fraction)&&0<=avr_fraction<=1 || throw(ArgumentError("invalid AVR fraction"))
    eligible=sort([g for g in case.generators if g.available&&g.p_max>0];by=g->(-g.p_max,g.id))
    count=floor(Int,avr_fraction*length(eligible)+.5)
    selected=Set(g.id for g in eligible[1:count]);online=Set(g.id for g in eligible)
    Set(keys(ratings))==online || throw(ArgumentError("ratings must exactly cover online positive-capacity units"))
    Set(keys(voltage_targets))==selected || throw(ArgumentError("targets must exactly cover selected AVR generators"))
    generators=[Generator(g.id,g.bus_id;available=g.available,p_min=g.p_min,p_max=g.p_max,
        q_min=g.q_min,q_max=g.q_max,initial_p=g.initial_p,initial_q=g.initial_q,
        s_rated=get(ratings,g.id,g.s_rated)) for g in case.generators]
    c=Case(case.id*"/mixed-avr";base_power=case.base_power,base_frequency=case.base_frequency,
        network=case.network,loads=case.loads,generators,controls=case.controls,attachments=case.attachments)
    attached=Dict(a.generator_id=>a for a in c.attachments);assignments=ReactiveControlAssignment[]
    for g in c.generators
        if g.id in selected
            push!(assignments,ReactiveControlAssignment(g.id,AVR(voltage_targets[g.id]),RegulatedLocation(:bus,g.bus_id)))
        elseif g.id in online
            haskey(attached,g.id) || throw(ArgumentError("each remaining online generator requires a supplied droop"))
            a=attached[g.id];push!(assignments,ReactiveControlAssignment(g.id,c.controls[a.control_id],a.location))
        elseif g.available
            throw(ArgumentError("online zero-P-capacity records require an explicit study classification"))
        else
            push!(assignments,ReactiveControlAssignment(g.id,FreeQ()))
        end
    end
    validate_reactive_assignments(c,assignments)
    rows=[(;generator_id=g.id,bus_id=g.bus_id,available=g.available,p_max_mw=g.p_max*c.base_power,
        s_rated_mva=isnothing(g.s_rated) ? nothing : g.s_rated*c.base_power,
        mode=g.id in selected ? :AVR : g.id in online ? :VoltVarDroop : :offline,
        voltage_target=get(voltage_targets,g.id,nothing)) for g in c.generators]
    (;case=c,assignments,avr_ids=sort!(collect(selected)),droop_ids=sort!(collect(setdiff(online,selected))),rows)
end
