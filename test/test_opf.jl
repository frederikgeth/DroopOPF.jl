@testset "AC OPF solve" begin
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
        "two-bus-opf";
        base_power = 100.0,
        base_frequency = 50.0,
        network = network,
        loads = [load],
        generators = [generator],
        controls = [droop],
        attachments = [attachment],
    )

    result = solve_opf(case; smooth_epsilon = 1.0e-3, silent = true)

    @test result.state !== nothing
    @test result.termination_status in (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED)
    @test result.objective >= 0.0
    @test maximum(abs, equilibrium_residual(case, result.state).power.vector) < 1.0e-6
    @test maximum(abs, equilibrium_residual(case, result.state).droop) < 5.0e-3

    warm_result = solve_opf(
        case;
        smooth_epsilon = 1.0e-3,
        initial_state = result.state,
        silent = true,
    )
    @test warm_result.state !== nothing
    @test warm_result.termination_status in (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED)
end
