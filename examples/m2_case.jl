using DroopOPF

"""Small meshed network with two controlled generators and non-consecutive IDs."""
function m2_case(; thermal_limit=2.0, demand=0.6)
    network = ACNetwork(
        [Bus(10; reference=true), Bus(20), Bus(30)],
        [Branch(id, f, t; resistance=0.01, reactance=0.1, thermal_limit=thermal_limit)
         for (id, f, t) in [(11, 10, 20), (22, 20, 30), (33, 10, 30)]])
    generators = [Generator(id, bus; p_min=0.0, p_max=1.2, q_min=-1.0, q_max=1.0,
        initial_p=0.3, initial_q=0.0) for (id, bus) in [(7, 10), (9, 20)]]
    droop_slopes = [0.05, 0.075]
    controls = [VoltVarDroop(VoltageSchedule(1.0; v_db_low=0.99, v_db_high=1.01),
        slope, 0.0, ReactiveCapability(p_min=0.0, p_max=1.2, q_min=-1.0, q_max=1.0))
        for slope in droop_slopes]
    attachments = [GeneratorControlAttachment(g.id, i, RegulatedLocation(:bus, g.bus_id))
        for (i, g) in enumerate(generators)]
    return Case("m2-three-bus"; base_power=100.0, base_frequency=50.0,
        network=network, loads=[Load(1, 30; p=demand, q=0.15)],
        generators=generators, controls=controls, attachments=attachments)
end
