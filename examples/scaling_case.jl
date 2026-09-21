using DroopOPF
include("m7_2_case.jl")

"""Connected synthetic modules; heterogeneity is an explicit load perturbation, not a public benchmark."""
function scaling_case(n::Integer;heterogeneous=false)
    n>0 || throw(ArgumentError("module count must be positive"))
    c=m72_case(); buses=Bus[];branches=Branch[];loads=Load[];generators=Generator[]
    shunts=FixedShunt[];banks=ShuntBank[];controls=VoltVarDroop[];attachments=GeneratorControlAttachment[]
    for k in 0:n-1
        offset=1000*k
        for b in c.network.buses
            push!(buses,Bus(b.id+offset;v_min=b.v_min,v_max=b.v_max,reference=k==0 && b.reference))
        end
        for b in c.network.branches
            push!(branches,Branch(b.id+offset,b.from_bus+offset,b.to_bus+offset;resistance=b.resistance,reactance=b.reactance,charging=b.charging,thermal_limit=b.thermal_limit,tap_ratio=b.tap_ratio,phase_shift=b.phase_shift))
        end
        for l in c.loads
            factor=heterogeneous ? 1+.1*sin(k+1) : 1.
            push!(loads,Load(l.id+offset,l.bus_id+offset;p=l.p*factor,q=l.q*factor))
        end
        for g in c.generators
            push!(generators,Generator(g.id+offset,g.bus_id+offset;p_min=g.p_min,p_max=g.p_max,q_min=g.q_min,q_max=g.q_max,initial_p=g.initial_p,initial_q=g.initial_q))
        end
        append!(controls,c.controls)
        for a in c.attachments
            push!(attachments,GeneratorControlAttachment(a.generator_id+offset,a.control_id+2*k,RegulatedLocation(a.location.kind,a.location.bus_id+offset)))
        end
        for s in c.network.shunts
            push!(shunts,FixedShunt(s.id+offset,s.bus_id+offset;conductance=s.conductance,susceptance=s.susceptance))
        end
        for b in c.network.banks
            push!(banks,ShuntBank(b.id+offset,b.bus_id+offset;step_conductances=b.step_conductances,step_susceptances=b.step_susceptances,legal_states=b.legal_states,state=b.state,nominal_state=b.nominal_state))
        end
        k>0 && push!(branches,Branch(900+offset,10+offset-1000,10+offset;resistance=.02,reactance=.2,thermal_limit=2.))
    end
    Case("connected-$n-$(heterogeneous ? "heterogeneous" : "uniform")";base_power=100.,base_frequency=50.,network=ACNetwork(buses,branches;shunts,banks),loads,generators,controls,attachments)
end

scaling_start(s,n)=ACState(repeat(s.vm,n),repeat(s.va,n),repeat(s.pg,n),repeat(s.qg,n))
function scaling_policies(n)
    (tap_controls=[TapControl(11+1000*k;lower=.95,upper=1.05) for k in 0:n-1],
     shunt_controls=[ShuntControl(id+1000*k) for k in 0:n-1 for id in (201,202)],
     droop_controls=[DroopControl(i;slope_bounds=(.04,.1)) for i in 1:2*n])
end
