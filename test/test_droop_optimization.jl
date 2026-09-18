@testset "M3 bounded droop-parameter optimization" begin
    case = m2_case()
    study = Study(
        case;
        contingencies = [
            Contingency(:line_22; branch_ids = [22]),
            Contingency(:generator_9; generator_ids = [9]),
        ],
        participation = Dict(7 => 1.0, 9 => 1.0),
    )
    reference = solve_scopf(study; smooth_epsilon = 1e-5)
    @test equilibrium_report(study, reference).valid

    fixed = optimize_droop_parameters(
        study,
        2;
        slope_bounds = (0.075, 0.075),
        smooth_epsilon = 1e-5,
        reference_result = reference,
    )
    @test validate_droop_design(study, fixed).valid
    @test fixed.settings.slope == 0.075
    @test fixed.result.objective ≈ reference.objective atol = 1e-10

    slope_design = optimize_droop_parameters(
        study,
        2;
        slope_bounds = (0.04, 0.10),
        smooth_epsilon = 1e-5,
        reference_result = reference,
    )
    @test validate_droop_design(study, slope_design).valid
    @test 0.04 <= slope_design.settings.slope <= 0.10
    @test abs(slope_design.settings.slope - 0.05) < 0.005
    @test slope_design.result.objective < reference.objective
    comparison_sweep = sweep_droop_slope(
        study,
        2,
        [0.045, 0.05, 0.055];
        reference_slope = 0.075,
        smooth_epsilon = 1e-5,
    )
    sampled_best = best_droop_slope(comparison_sweep)
    @test sampled_best.slope == 0.05
    @test abs(slope_design.settings.slope - sampled_best.slope) < 0.005
    @test slope_design.result.objective <= sampled_best.objective + 1e-10

    generalized = optimize_droop_parameters(
        study,
        2;
        slope_bounds = (0.04, 0.10),
        v_ref_bounds = (0.995, 1.005),
        deadband_low_bounds = (0.005, 0.015),
        deadband_high_bounds = (0.005, 0.015),
        smooth_epsilon = 1e-5,
        reference_result = reference,
    )
    @test validate_droop_design(study, generalized).valid
    optimized = with_droop_settings(study, generalized)
    @test optimized.case.controls[2].slope == generalized.settings.slope
    @test optimized.case.controls[2].schedule.v_db_low ≈
        generalized.settings.v_ref - generalized.settings.deadband_low
    @test optimized.case.controls[2].schedule.v_db_high ≈
        generalized.settings.v_ref + generalized.settings.deadband_high
    @test study.case.controls[2].slope == 0.075
    mktempdir() do directory
        path = write_droop_design(joinpath(directory, "design.json"), generalized)
        restored = read_droop_design(path)
        @test restored.control_id == generalized.control_id
        @test restored.settings == generalized.settings
        @test restored.result.states[:base].pg == generalized.result.states[:base].pg
        @test validate_droop_design(study, restored).valid
    end

    held_out = evaluate_held_out_contingencies(
        study,
        generalized,
        [Contingency(:line_33; branch_ids = [33])],
    )
    @test held_out.report.valid
    @test held_out.report.physical_valid
    @test_throws ArgumentError evaluate_held_out_contingencies(
        study,
        generalized,
        [Contingency(:line_22; branch_ids = [22])],
    )

    @test_throws ArgumentError DroopSettings(0.0, 1.0, 0.01, 0.01)
    @test_throws ArgumentError DroopSettings(0.05, 1.0, 0.0, 0.0)
    @test_throws ArgumentError optimize_droop_parameters(
        study,
        2;
        slope_bounds = (0.10, 0.04),
        smooth_epsilon = 1e-5,
        reference_result = reference,
    )
    @test_throws ArgumentError optimize_droop_parameters(
        study,
        2;
        deadband_low_bounds = (1.0, 1.1),
        smooth_epsilon = 1e-5,
        reference_result = reference,
    )
end
