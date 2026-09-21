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

    simple_case = load_matpower_case(joinpath(@__DIR__, "data", "droop2.m"))
    control = VoltVarDroop(
        VoltageSchedule(1.0; v_db_low = 0.99, v_db_high = 1.01),
        0.05,
        0.0,
        ReactiveCapability(p_min = 0.0, p_max = 2.0, q_min = -1.0, q_max = 1.0),
    )
    droop_case = attach_controls(
        simple_case,
        [control],
        [GeneratorControlAttachment(1, 1, RegulatedLocation(:bus, 1))],
    )
    result = solve_opf(droop_case; smooth_epsilon = 1.0e-3, silent = true)
    @test result.state !== nothing
    @test result.termination_status in (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED)
    report = validate_equilibrium(droop_case, result; droop_tolerance = 5.0e-3)
    @test report.valid
    @test report.power_balance_max < 1.0e-6
    @test report.smooth_exact_droop_gap <= 5.0e-3
end

@testset "MATPOWER comments and public-case import" begin
    text = """
    mpc.gen = [
    % generator header
    1, 2, 3; % trailing comment must not hide the next record
    4 5 6; % another inline comment
    % standalone comment with a semicolon ; and numbers 99 99
    7 8 9; % last record
    ];
    """
    @test DroopOPF._matpower_array(text, "gen") == [1. 2. 3.; 4. 5. 6.; 7. 8. 9.]
    @test_throws ArgumentError DroopOPF._matpower_array("mpc.gen = [1 2; 3;];", "gen")
    source = joinpath(@__DIR__, "data", "pglib", "v23.07", "pglib_opf_case118_ieee.m")
    case = load_matpower_case(source; base_frequency=60.)
    @test length(case.network.buses) == 118
    @test length(case.generators) == 54
    @test length(case.network.branches) == 186
    @test count(b->b.reference, case.network.buses) == 1
    @test case.generators[end].bus_id == 116
    @test length(case.network.shunts) == 14
end
