using DroopOPF

# Synthetic declarations, not manufacturer data. All network powers are on 100 MVA.
case = Case("fixed-frequency-qv"; base_power=100., base_frequency=50.,
    network=ACNetwork([Bus(1;reference=true,v_min=.9,v_max=1.1),
        Bus(2;v_min=.9,v_max=1.1)],
        [Branch(1,1,2;resistance=.01,reactance=.05,thermal_limit=3.)]),
    loads=[Load(1,1;p=1.,q=.3)],
    generators=[Generator(1,1;p_min=0.,p_max=3.,q_min=-2.,q_max=2.),
        Generator(2,2;p_min=-.5,p_max=.5,q_min=-.5,q_max=.5)],
    controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])

# GFM here means an aggregate terminal Q–V characteristic; no P–f response.
# Negative p_ref is also supported for BESS charging within the source P box.
plant = qv_inverter(generator_id=2,terminal_bus=2,mode=:gfm,priority=:active,
    base_mva=50.,terminal_base_kv=20.,s_max=1.,i_max=1.1,
    p_available=.9,p_ref=.8,q_ref=0.,v_ref=1.,q_droop=.05,
    reactive_available=true,frequency_hz=case.base_frequency,q_cap_fraction=.395)
result = solve_inverter_opf(case,[plant])
report = validate_inverter_opf(case,result)
@assert report.valid
println("Fixed-frequency Q–V equilibrium validated; cap fraction = ",plant.q_cap_fraction)
println("P/Q (MW/MVAr): ",case.base_power .* [result.opf.state.pg[2],result.opf.state.qg[2]])
