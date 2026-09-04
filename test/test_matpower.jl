@testset "MATPOWER adapter" begin
    path = joinpath(@__DIR__, "data", "case3.m")
    case = load_matpower_case(path; base_frequency = 60.0)

    @test case.id == "case3"
    @test case.base_power == 100.0
    @test case.base_frequency == 60.0
    @test length(case.network.buses) == 3
    @test length(case.network.branches) == 3
    @test length(case.generators) == 2
    @test length(case.loads) == 2
    @test case.network.buses[1].reference
    @test case.loads[1].p ≈ 0.217
    @test case.loads[2].q ≈ 0.19
    @test case.generators[1].p_max ≈ 2.5
    @test case.generators[2].q_min ≈ -0.4
    @test case.network.branches[1].thermal_limit ≈ 2.5

    schedule = VoltageSchedule(1.0; v_db_low = 0.99, v_db_high = 1.01)
    capability = ReactiveCapability(p_min = -1.0, p_max = 3.0, q_min = -1.0, q_max = 1.0)
    control = VoltVarDroop(schedule, 0.05, 0.0, capability)
    attached = attach_controls(
        case,
        [control],
        [GeneratorControlAttachment(1, 1, RegulatedLocation(:bus, 1))],
    )
    @test length(attached.controls) == 1
    @test length(attached.attachments) == 1
    @test attached.generators == case.generators
end
