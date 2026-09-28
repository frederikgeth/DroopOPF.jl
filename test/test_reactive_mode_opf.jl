@testset "FreeQ and FixedQ OPF integration" begin
    network = ACNetwork(
        [Bus(1; reference=true), Bus(2)],
        [Branch(1, 1, 2; resistance=0.01, reactance=0.1, thermal_limit=5.0)],
    )
    generator = Generator(1, 1; p_min=0.0, p_max=2.0, q_min=-1.0, q_max=1.0,
        initial_p=0.5, initial_q=0.0)
    load = Load(1, 2; p=0.5, q=0.2)
    droop = VoltVarDroop(VoltageSchedule(1.0; v_db_low=0.99, v_db_high=1.01),
        0.05, 0.0, ReactiveCapability(p_min=0.0, p_max=2.0, q_min=-1.0, q_max=1.0))
    case = Case("reactive-mode-opf"; base_power=100.0, base_frequency=50.0,
        network, loads=[load], generators=[generator], controls=[droop],
        attachments=[GeneratorControlAttachment(1, 1, RegulatedLocation(:bus, 1))])

    free = [ReactiveControlAssignment(1, FreeQ())]
    free_result = solve_opf(case; reactive_assignments=free)
    free_check = validate_equilibrium(case, free_result; reactive_assignments=free)
    @test free_check.valid
    @test free_check.droop_residual_max == 0.0

    q_schedule = free_result.state.qg[1]
    fixed = [ReactiveControlAssignment(1, FixedQ(q_schedule))]
    fixed_result = solve_opf(case; reactive_assignments=fixed,
        initial_state=free_result.state)
    fixed_check = validate_equilibrium(case, fixed_result; reactive_assignments=fixed)
    @test fixed_check.valid
    @test fixed_result.state.qg[1] ≈ q_schedule atol=1e-8
    @test fixed_check.droop_residual_max < 1e-8
    wrong_schedule = [ReactiveControlAssignment(1, FixedQ(q_schedule + 0.01))]
    mismatch = validate_equilibrium(case, fixed_result; reactive_assignments=wrong_schedule)
    @test :fixed_q in mismatch.violations
    @test !mismatch.valid
    for assignments in (free, fixed)
        exact = solve_opf_complementarity(case; reactive_assignments=assignments,
            initial_state=fixed_result.state)
        @test exact.termination_status in (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED, :OPTIMAL)
        @test validate_equilibrium(case, exact; reactive_assignments=assignments).valid
        if assignments === fixed
            @test exact.state.qg[1] ≈ q_schedule atol=1e-8
        end
    end

    explicit_droop = [ReactiveControlAssignment(1, droop, RegulatedLocation(:bus, 1))]
    droop_result = solve_opf(case; smooth_epsilon=1e-3,
        reactive_assignments=explicit_droop)
    @test validate_equilibrium(case, droop_result;
        reactive_assignments=explicit_droop).valid
    exact_droop = solve_opf_complementarity(case;
        reactive_assignments=explicit_droop, initial_state=droop_result.state)
    # Match the existing exact-solver compatibility contract; do not relax defaults.
    exact_check = validate_equilibrium(case, exact_droop;
        reactive_assignments=explicit_droop, droop_tolerance=5e-4,
        power_tolerance=1e-5)
    @test isempty(exact_check.violations)
end
