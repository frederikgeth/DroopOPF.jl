@testset "M3 fixed droop-slope sweep" begin
    case = m2_case()
    study = Study(
        case;
        contingencies = [
            Contingency(:line_22; branch_ids = [22]),
            Contingency(:generator_9; generator_ids = [9]),
        ],
        participation = Dict(7 => 1.0, 9 => 1.0),
    )
    baseline = solve_scopf(study; smooth_epsilon = 1e-5)
    @test equilibrium_report(study, baseline).valid
    sweep = sweep_droop_slope(
        study,
        2,
        [0.08];
        reference_slope = 0.075,
        smooth_epsilon = 1e-5,
    )
    @test [point.slope for point in sweep.points] == [0.075, 0.08]
    @test all(point -> point.valid, sweep.points)
    reference = only(point for point in sweep.points if point.slope == 0.075)
    @test reference.objective ≈ baseline.objective atol = 1e-10
    @test reference.max_voltage_deviation > 0
    @test 0 < reference.max_branch_loading_percent < 100
    @test reference.max_exact_droop_residual < 1e-5
    @test best_droop_slope(sweep).slope == 0.075
    @test sweep_droop_slope(
        study,
        2,
        Float64[];
        reference_slope = 0.075,
        smooth_epsilon = 1e-5,
    ).points[1].objective ≈ baseline.objective atol = 1e-10
    mktempdir() do directory
        json = write_droop_slope_sweep(joinpath(directory, "sweep.json"), sweep)
        restored = read_droop_slope_sweep(json)
        @test restored.control_id == 2
        @test restored.reference_slope == 0.075
        @test [point.objective for point in restored.points] ==
            [point.objective for point in sweep.points]
        plot = write_droop_slope_sweep_plot(joinpath(directory, "sweep.svg"), restored)
        @test startswith(read(plot, String), "<svg")
        @test occursin("Best valid objective", read(plot, String))
    end
    @test_throws ArgumentError sweep_droop_slope(study, 3, [0.075])
    @test_throws ArgumentError sweep_droop_slope(study, 2, [0.0])
    @test_throws ArgumentError sweep_droop_slope(
        study,
        2,
        [0.075];
        initial_states = Dict(),
    )
    @test_throws ArgumentError best_droop_slope(DroopSlopeSweep(2, 0.075, DroopSlopeSweepPoint[]))
end
