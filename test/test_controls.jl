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

@testset "volt-var with no deadband" begin
    cap=ReactiveCapability(p_min=0.,p_max=1.,q_min=-.5,q_max=.5)
    c=VoltVarDroop(VoltageSchedule(1.),.04,0.,cap)
    @test length(droop_curve(c).breakpoints)==3
    for v in (.95,.98,.99,1.,1.01,1.02,1.05)
        @test droop_response(c,v;p=.5) ≈ clamp((1-v)/.04,-.5,.5) atol=1e-14
    end
    @test slope_at(droop_curve(c),1.) ≈ -25.
    @test DroopSettings(c).deadband_low == 0.
    @test DroopSettings(c).deadband_high == 0.
    @test droop_regime(c,1.) == :proportional
    @test droop_regime(c,1.01) == :proportional
    @test droop_regime(c,.95) == :saturation_qmax
    @test droop_regime(c,1.05) == :saturation_qmin
end
