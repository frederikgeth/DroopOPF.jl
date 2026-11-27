using DroopOPF

# Synthetic assumptions only; no manufacturer rating or dynamic qualification.
case = Case("static-inverter-example"; base_power=100.0, base_frequency=50.0,
    network=ACNetwork([Bus(1;reference=true),Bus(2)],
        [Branch(1,1,2;resistance=0.01,reactance=0.05,thermal_limit=3.0)]),
    loads=[Load(1,1;p=1.0,q=0.3)],
    generators=[Generator(1,1;p_min=0.0,p_max=3.0,q_min=-2.0,q_max=2.0,initial_p=1.0),
        Generator(2,2;p_min=0.0,p_max=1.0,q_min=-1.0,q_max=1.0,initial_p=0.4)],
    controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
plant = StaticInverter(generator_id=2,terminal_bus=2,poi_bus=1,
    mode=:gfl,priority=:active,q_control=:fixed_q,
    base_mva=50.0,terminal_base_kv=20.0,i_max=1.0,s_max=1.2,
    p_available=1.0,p_ref=0.8,q_ref=0.2,
    v_ref=1.0,q_droop=0.05,f_ref_hz=50.0,p_droop_hz=2.5,reactive_available=true)
result = solve_inverter_opf(case,[plant])
report = validate_inverter_opf(case,result)
report.valid || error("Static inverter example failed independent verification")
println("P = ",100result.opf.state.pg[2]," MW, Q = ",100result.opf.state.qg[2]," MVAr")
println("Native convergence, AC replay and inverter-law replay passed")
