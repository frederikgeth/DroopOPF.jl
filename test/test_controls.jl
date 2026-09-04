@testset "volt-var droop" begin
    schedule = VoltageSchedule(1.0; v_db_low = 0.99, v_db_high = 1.01)
    capability = ReactiveCapability(p_min = 0.0, p_max = 1.0, q_min = -0.5, q_max = 0.5)
    control = VoltVarDroop(schedule, 0.05, 0.0, capability)

    @test droop_response(control, 1.0; p = 0.5) == 0.0
    @test droop_response(control, 0.99; p = 0.5) == 0.0
    @test droop_response(control, 1.01; p = 0.5) == 0.0
    @test droop_response(control, 0.98; p = 0.5) ≈ 0.2
    @test droop_response(control, 1.02; p = 0.5) ≈ -0.2
    @test droop_response(control, 0.8; p = 0.5) == 0.5
    @test droop_response(control, 1.2; p = 0.5) == -0.5
    @test slope_at(droop_curve(control), 0.98) ≈ -20.0

    @test_throws DomainError droop_response(control, 1.0; p = 2.0)
    @test_throws ArgumentError VoltVarDroop(schedule, 0.0, 0.0, capability)
    @test_throws ArgumentError VoltageSchedule(1.0; v_db_low = 1.01, v_db_high = 1.02)
end
