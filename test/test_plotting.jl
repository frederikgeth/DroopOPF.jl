@testset "droop plotting" begin
    control = VoltVarDroop(
        VoltageSchedule(1.0; v_db_low = 0.99, v_db_high = 1.01),
        0.05,
        0.0,
        ReactiveCapability(p_min = 0.0, p_max = 2.0, q_min = -1.0, q_max = 1.0),
    )
    @test droop_regime(control, 1.0) == :deadband
    @test droop_regime(control, 0.98) == :proportional
    @test droop_regime(control, 0.9) == :saturation_qmax
    @test droop_regime(control, 1.2) == :saturation_qmin

    point = droop_operating_point(control, 7, 1, 0.98; p = 0.5)
    @test point.generator_id == 7
    @test point.control_id == 1
    @test point.reactive_power ≈ droop_response(control, 0.98; p = 0.5)
    @test point.regime == :proportional

    path = joinpath(mktempdir(), "droop.svg")
    write_droop_plot(path, [control], [point])
    @test isfile(path)
    svg = read(path, String)
    @test startswith(svg, "<svg")
    @test endswith(strip(svg), "</svg>")
    @test occursin("G7: proportional", svg)
end
