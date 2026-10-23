using DroopOPF

"""Two-bus, two-circuit fixtures with explicit line/transformer identity."""
function scopf_parallel_case(kind::Symbol=:benign)
    kind in (:benign, :thermal, :voltage, :reactive, :transformer) ||
        throw(ArgumentError("unknown small-network scenario"))
    tight_voltage = kind == :voltage
    q = kind == :reactive ? 0.3 : tight_voltage ? 0.15 : 0.1
    qmax = kind == :reactive ? 0.2 : 1.0
    limit = kind == :thermal ? 0.25 : 2.0
    network = ACNetwork([Bus(1; reference=true,
        v_min=tight_voltage ? 0.99 : 0.9, v_max=tight_voltage ? 1.01 : 1.1),
        Bus(2; v_min=tight_voltage ? 0.99 : 0.9, v_max=tight_voltage ? 1.01 : 1.1)],
        [Branch(1, 1, 2; resistance=0.02, reactance=0.15, thermal_limit=limit),
         Branch(2, 1, 2; resistance=0.02, reactance=0.15, thermal_limit=limit,
            kind=:transformer, tap_ratio=kind == :transformer ? 1.01 : 1.0)])
    Case("parallel-$kind"; base_power=100.0, base_frequency=50.0, network,
        generators=[Generator(i, 1; p_min=0.0, p_max=0.8, q_min=-1.0,
            q_max=qmax, initial_p=0.15, initial_q=q/2) for i in 1:2],
        loads=[Load(1, 2; p=0.3, q)], controls=VoltVarDroop[],
        attachments=GeneratorControlAttachment[])
end

"""Create a validated interior-voltage base; subsequent assessment uses FreeQ.

AVR is used only to choose the base operating point. It is not an assumed
post-contingency control: the fixture's declared case has free reactive power.
"""
function scopf_validation_base(case::Case)
    setpoint = case.id == "parallel-voltage" ? 1.009 : 1.0
    assignments = [ReactiveControlAssignment(g.id, AVR(setpoint),
        RegulatedLocation(:bus,g.bus_id)) for g in case.generators]
    solve_opf(case; reactive_assignments=assignments)
end

"""Loaded radial network with predictable lost load and reference reassignment."""
function scopf_loaded_island_case()
    network = ACNetwork([Bus(i; reference=i == 1) for i in 1:5],
        [Branch(10i, i, i+1; resistance=0.01, reactance=0.1, thermal_limit=2.0,
            kind=i == 1 ? :transformer : :line) for i in 1:4])
    Case("loaded-islands"; base_power=100.0, base_frequency=50.0, network,
        generators=[Generator(i, bus; p_min=0.0, p_max=cap, q_min=-1.0,
            q_max=1.0) for (i,bus,cap) in ((1,1,0.5),(2,3,1.5),(3,5,1.0))],
        loads=[Load(1,1;p=0.03,q=0.01), Load(2,5;p=0.12,q=0.03)],
        controls=VoltVarDroop[], attachments=GeneratorControlAttachment[])
end
