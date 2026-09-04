@testset "independent equilibrium validation" begin
    network = ACNetwork(
        [Bus(1; reference = true), Bus(2)],
        [Branch(1, 1, 2; resistance = 0.01, reactance = 0.1, thermal_limit = 5.0)],
    )
    generator = Generator(
        1,
        1;
        p_min = 0.0,
        p_max = 2.0,
        q_min = -1.0,
        q_max = 1.0,
        initial_p = 0.5,
        initial_q = 0.0,
    )
    load = Load(1, 2; p = 0.5, q = 0.2)
    schedule = VoltageSchedule(1.0; v_db_low = 0.99, v_db_high = 1.01)
    capability = ReactiveCapability(p_min = 0.0, p_max = 2.0, q_min = -1.0, q_max = 1.0)
    droop = VoltVarDroop(schedule, 0.05, 0.0, capability)
    attachment = GeneratorControlAttachment(1, 1, RegulatedLocation(:bus, 1))
    case = Case(
        "two-bus-validation";
        base_power = 100.0,
        base_frequency = 50.0,
        network = network,
        loads = [load],
        generators = [generator],
        controls = [droop],
        attachments = [attachment],
    )

    result = solve_opf(case; smooth_epsilon = 1.0e-3, silent = true)
    report = validate_equilibrium(case, result)

    @test report.valid
    @test isempty(report.violations)
    @test report.power_balance_max < 1.0e-6
    @test report.droop_residual_max < 5.0e-3
    @test report.smooth_exact_droop_gap >= 0.0

    structured = equilibrium_report(case, result)
    @test structured.valid
    @test structured.validation.valid
    rendered = markdown_report(structured)
    @test occursin("# Equilibrium report", rendered)
    @test occursin("Maximum AC power-balance residual", rendered)

    state = result.state
    perturbed = ACState(state.vm, state.va, [state.pg[1] + 0.1], state.qg)
    bad_report = validate_equilibrium(case, perturbed)
    @test !bad_report.valid
    @test :power_balance in bad_report.violations
end
