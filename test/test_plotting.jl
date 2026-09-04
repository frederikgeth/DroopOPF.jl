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

    state = ACState([1.0], [0.0], [0.5], [0.0])
    grouped = solver_operating_points(
        Case(
            "plot-case";
            base_power = 100.0,
            base_frequency = 50.0,
            network = ACNetwork([Bus(1; reference = true)], Branch[]),
            generators = [Generator(7, 1; p_min = 0.0, p_max = 2.0, q_min = -1.0, q_max = 1.0,
                                   initial_p = 0.5, initial_q = 0.0)],
            controls = [control],
            attachments = [GeneratorControlAttachment(7, 1, RegulatedLocation(:bus, 1))],
        ),
        Dict(:ipopt => (state = state,), :madnlp => (state = state,)),
    )
    @test length(grouped) == 2

    comparison_path = joinpath(mktempdir(), "comparison.svg")
    write_solver_comparison_plot(
        comparison_path,
        Case(
            "plot-case";
            base_power = 100.0,
            base_frequency = 50.0,
            network = ACNetwork([Bus(1; reference = true)], Branch[]),
            generators = [Generator(7, 1; p_min = 0.0, p_max = 2.0, q_min = -1.0, q_max = 1.0,
                                   initial_p = 0.5, initial_q = 0.0)],
            controls = [control],
            attachments = [GeneratorControlAttachment(7, 1, RegulatedLocation(:bus, 1))],
        ),
        Dict(:ipopt => (state = state,), :madnlp => (state = state,)),
    )
    comparison_svg = read(comparison_path, String)
    @test occursin("ipopt", comparison_svg)
    @test occursin("madnlp", comparison_svg)
end
