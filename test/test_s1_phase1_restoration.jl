include(joinpath(@__DIR__, "..", "examples", "s1_phase1_restoration.jl"))

@testset "S1 Phase-I restoration separates slack families" begin
    network = ACNetwork(
        [Bus(1; reference=true), Bus(2)],
        [Branch(1, 1, 2; resistance=0.01, reactance=0.1, thermal_limit=5.0)],
    )
    generator = Generator(1, 1; p_min=0.0, p_max=2.0, q_min=-1.0, q_max=1.0,
        initial_p=0.5, initial_q=0.0)
    load = Load(1, 2; p=0.5, q=0.2)
    control = VoltVarDroop(VoltageSchedule(1.0; v_db_low=0.99, v_db_high=1.01),
        0.05, 0.0, ReactiveCapability(p_min=0.0, p_max=2.0, q_min=-1.0, q_max=1.0))
    case = Case("phase1-two-bus"; base_power=100.0, base_frequency=50.0,
        network, loads=[load], generators=[generator], controls=[control],
        attachments=[GeneratorControlAttachment(1, 1, RegulatedLocation(:bus, 1))])
    baseline = solve_opf(case)
    @test validate_equilibrium(case, baseline).valid
    phase1 = s1_phase1_restoration(case, baseline.state;
        optimizer_attributes=Dict("max_iter" => 300, "tol" => 1e-9))
    @test phase1["classification"] == "restored_zero_slack"
    @test phase1["max_slack"] <= 1e-7
    @test phase1["independent_validation"]["valid"]
    @test Set(keys(phase1["families"])) == Set(("active_balance", "reactive_balance",
        "voltage_limits", "generator_p_limits", "generator_q_limits",
        "thermal_limits", "droop_equalities"))
end
