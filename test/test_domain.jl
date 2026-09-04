@testset "domain relations" begin
    generator = Generator(
        1,
        2;
        p_min = 0.0,
        p_max = 1.0,
        q_min = -0.5,
        q_max = 0.5,
        initial_p = 0.4,
        initial_q = 0.0,
    )
    schedule = VoltageSchedule(1.0; v_db_low = 0.99, v_db_high = 1.01)
    capability = ReactiveCapability(p_min = 0.0, p_max = 1.0, q_min = -0.5, q_max = 0.5)
    control = VoltVarDroop(schedule, 0.05, 0.0, capability)
    location = RegulatedLocation(:bus, 2)
    attachment = GeneratorControlAttachment(1, 1, location)
    case = Case(
        "two-bus-test";
        base_power = 100.0,
        base_frequency = 50.0,
        generators = [generator],
        controls = [control],
        attachments = [attachment],
    )

    @test validate_case(case)
    @test case.generators[1].bus_id == 2
    @test case.attachments[1].location.kind == :bus
    @test droop_response(case, 1, 0.98; p = 0.4) ≈ 0.2

    @test_throws ArgumentError Generator(1, 2; p_min = 1.0, p_max = 0.0, q_min = -1.0, q_max = 1.0)
    @test_throws ArgumentError RegulatedLocation(:branch_terminal, 2)
    @test_throws ArgumentError GeneratorControlAttachment(1, 1, location; priority = :invalid)
end
