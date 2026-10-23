using DroopOPF
# New held-out family. This specification is saved before any base/outage solves.
function p2_fresh_inputs()
    inputs=[]
    for n in (7,8), topology in (:ring,:chord,:two_chords), stress in (:light,:reactive_high,:reactive_low,:loaded)
        p=stress==:loaded ? 0.83 : n==7 ? 0.37 : 0.43
        q=stress==:reactive_high ? 0.68 : stress==:reactive_low ? -0.62 : stress==:loaded ? 0.19 : 0.13
        pairs=[(i,mod1(i+1,n)) for i in 1:n]
        topology!=:ring && push!(pairs,(1,div(n,2)+1))
        topology==:two_chords && push!(pairs,(2,n-1))
        gbuses=(1,div(n,2)+1);load_buses=[b for b in 1:n if !(b in gbuses)]
        qmin=stress==:reactive_low ? -(abs(q)+0.09)/2 : -0.7
        qmax=stress==:reactive_high ? (q+0.08)/2 : 0.75
        branches=[Branch(i,f,t;resistance=n==7 ? .014 : .018,reactance=n==7 ? .137 : .157,
            thermal_limit=stress==:loaded ? .64 : 1.4,kind=i==length(pairs) ? :transformer : :line,
            tap_ratio=i==length(pairs) ? (topology==:ring ? .985 : 1.025) : 1.)
            for (i,(f,t)) in enumerate(pairs)]
        generators=[Generator(i,b;p_min=0.,p_max=.95,q_min=qmin,q_max=qmax,
            initial_p=p/2,initial_q=q/2) for (i,b) in enumerate(gbuses)]
        case=Case("p2-new-$n-$topology-$stress";base_power=100.,base_frequency=50.,
            network=ACNetwork([Bus(i;reference=i==1) for i in 1:n],branches;
                shunts=[FixedShunt(100,n;conductance=.0003,susceptance=q>=0 ? .004 : -.004)]),
            generators,loads=[Load(i,b;p=p/length(load_buses),q=q/length(load_buses)) for (i,b) in enumerate(load_buses)],
            controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
        push!(inputs,(;case,split=:new_heldout,width=n==7 ? .0015 : .0045,
            voltage_span=topology==:ring ? .03 : topology==:chord ? .05 : .06,
            anchor_regime=n==7 ? :deadband : :proportional))
    end
    inputs
end

function p2_overlay(case,base; width,voltage_span,anchor_regime)
    validate_equilibrium(case,base).valid || error("anchor AC state is invalid")
    idx=Dict(b.id=>i for (i,b) in enumerate(case.network.buses));controls=VoltVarDroop[];attachments=GeneratorControlAttachment[]
    for (i,g) in enumerate(case.generators)
        v=base.vm[idx[g.bus_id]];q=clamp(base.qg[i],g.q_min,g.q_max);slope=voltage_span/(g.q_max-g.q_min)
        direction=q>=0 ? 1. : -1.
        shift=anchor_regime==:proportional ? direction*2width : 0.
        q0=anchor_regime==:proportional ? q-direction*width/slope : q
        g.q_min<=q0<=g.q_max || error("predeclared proportional anchor is outside Q capability")
        push!(controls,VoltVarDroop(VoltageSchedule(v+shift;v_db_low=v+shift-width,v_db_high=v+shift+width),
            slope,q0,ReactiveCapability(p_min=g.p_min,p_max=g.p_max,q_min=g.q_min,q_max=g.q_max)))
        push!(attachments,GeneratorControlAttachment(g.id,length(controls),RegulatedLocation(:bus,g.bus_id)))
    end
    over=Case(case.id*"-droop";base_power=case.base_power,base_frequency=case.base_frequency,network=case.network,
        generators=case.generators,loads=case.loads,controls,attachments)
    validate_equilibrium(over,base).valid || error("frozen overlay does not reproduce anchor")
    over
end
