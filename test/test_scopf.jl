include(joinpath(@__DIR__, "..", "examples", "m2_case.jl"))

@testset "M2 contingency data and physics" begin
    case = m2_case()
    @test [control.slope for control in case.controls] == [0.05, 0.075]
    @test case.controls[1].curve.breakpoints != case.controls[2].curve.breakpoints
    line = Contingency(:line_22; branch_ids=[22])
    gen = Contingency(:generator_9; generator_ids=[9])
    overlay = scenario_case(case, line)
    @test case.network.branches[2].available
    @test !overlay.network.branches[2].available
    state = ACState(ones(3), zeros(3), [0.3, 0.3], [0.0, 0.0])
    flows = branch_flows(overlay.network, state)
    @test flows.from[2] == flows.to[2] == 0.0
    @test !scenario_case(case, gen).generators[2].available
    @test case.generators[2].available
    @test_throws ArgumentError Contingency(:base; branch_ids=[22])
    @test_throws ArgumentError Contingency(:empty)
    @test_throws ArgumentError Contingency(:duplicate; branch_ids=[22,22])
    @test_throws ArgumentError scenario_case(case, Contingency(:unknown; generator_ids=[1]))
    @test_throws ArgumentError scenario_case(case, Contingency(:unknown; branch_ids=[1]))
    @test_throws ArgumentError scenario_case(case, Contingency(:island; branch_ids=[22,33]))
    @test_throws ArgumentError Study(case; contingencies=[line,line])
    @test_throws ArgumentError Study(case; contingencies=[line])
    @test_throws ArgumentError Study(case; contingencies=[gen], participation=Dict(9=>1.0))
    @test_throws ArgumentError Study(case; participation=Dict(1=>1.0))
    @test_throws ArgumentError Study(case; participation=Dict(7=>NaN))
    @test_throws ArgumentError Study(case; redispatch_limits=Dict(7=>-0.1))
    @test_throws ArgumentError Study(case; mode=:corrective, participation=Dict(7=>1.0))
end

@testset "M2 full enumeration and independent validation" begin
    case = m2_case()
    contingencies = [Contingency(:line_22; branch_ids=[22]),
                     Contingency(:generator_9; generator_ids=[9])]
    study = Study(case; contingencies=contingencies, participation=Dict(7=>2.0,9=>1.0))
    result = solve(study; smooth_epsilon=1e-5)
    @test result.termination_status == :LOCALLY_SOLVED
    @test Set(keys(result.states)) == Set([:base,:line_22,:generator_9])
    report = equilibrium_report(study, result)
    @test report.valid
    @test report.physical_valid
    @test report.encoded_physical_valid
    @test all(r -> r.power_balance_max < 1e-6, values(report.scenarios))
    @test all(r -> r.droop_residual_max < 1e-5, values(report.scenarios))
    @test result.states[:generator_9].pg[2] ≈ 0 atol=1e-8
    @test result.states[:generator_9].qg[2] ≈ 0 atol=1e-8
    @test result.states[:generator_9].pg[1] > result.states[:base].pg[1]
    @test result.states[:line_22].pg[1] - result.states[:base].pg[1] ≈
        2 * (result.states[:line_22].pg[2] - result.states[:base].pg[2]) atol=1e-7
    @test occursin("generator_9", markdown_report(report))
    @test all(g.available for g in case.generators)
    @test all(b.available for b in case.network.branches)

    baseline = solve_opf(case)
    empty = solve_scopf(Study(case))
    @test empty.objective ≈ baseline.objective atol=1e-8
    @test empty.states[:base].pg ≈ baseline.state.pg atol=1e-6
    @test result.objective >= baseline.objective - 1e-7
    fixed_only = evaluate_contingencies(Study(case), baseline.state)
    @test fixed_only.termination_status == :NOT_RUN
    @test equilibrium_report(Study(case),fixed_only).valid
    invalid_base = deepcopy(baseline.state)
    invalid_base.pg[1] += 0.1
    @test !equilibrium_report(Study(case),evaluate_contingencies(Study(case),invalid_base)).valid
    evaluation = evaluate_contingencies(study, result.states[:base])
    @test equilibrium_report(study, evaluation).valid
    @test evaluation.states[:base].pg ≈ result.states[:base].pg atol=1e-7

    corrupted = deepcopy(result)
    corrupted.states[:generator_9].qg[2] = 0.1
    bad = equilibrium_report(study, corrupted)
    @test !bad.valid
    @test :unavailable_generator in bad.violations[:generator_9]
    corrupted = deepcopy(result)
    corrupted.states[:line_22].pg[1] += 0.01
    bad = equilibrium_report(study, corrupted)
    @test :power_balance in bad.violations[:line_22]
    @test :active_power_response in bad.violations[:line_22]
    corrupted = deepcopy(result)
    corrupted.balancing_power[:line_22] += 0.1
    @test !equilibrium_report(study, corrupted).valid
    corrupted = deepcopy(result)
    delete!(corrupted.states, :line_22)
    @test :missing_state in equilibrium_report(study, corrupted).violations[:line_22]
    @test_throws ArgumentError equilibrium_report(study, result; coupling_tolerance=-1.0)

    corrective = Study(case; contingencies=contingencies, mode=:corrective,
        redispatch_limits=Dict(7=>0.8,9=>0.8))
    # Anchor the nonconvex corrective solve at the validated preventive states;
    # an unseeded start can select a different local point across Ipopt builds.
    corrected = solve_scopf(corrective; initial_states=result.states)
    @test equilibrium_report(corrective, corrected).valid
    @test isempty(corrected.balancing_power)
    @test !equilibrium_report(study, corrected).valid
    # Restrict response to zero: the positive generator outage cannot be replaced.
    restricted = Study(case; contingencies=[last(contingencies)], mode=:corrective)
    impossible = evaluate_contingencies(restricted, result.states[:base];
        optimizer_attributes=Dict("max_iter"=>150))
    @test !equilibrium_report(restricted, impossible).valid

    continuation = solve_scopf_continuation(study; smooth_epsilons=[1e-3,1e-4])
    @test length(continuation) == 2
    @test equilibrium_report(study, last(continuation)).valid
    @test_throws ArgumentError solve_scopf_continuation(study; smooth_epsilons=Float64[])
    @test_throws ArgumentError solve_scopf(study; smooth_epsilon=Inf)
    smooth = solve_scopf(study; smooth_epsilon=1e-2)
    smooth_report = equilibrium_report(study,smooth)
    @test smooth_report.encoded_physical_valid
    @test !smooth_report.physical_valid
    # A policy violation is rejected even when each scenario remains physically valid.
    tighter = Study(case; contingencies=contingencies, mode=:corrective,
        redispatch_limits=Dict(7=>0.0,9=>0.0))
    tighter_report = equilibrium_report(tighter,corrected)
    @test all(r.valid for r in values(tighter_report.scenarios))
    @test :active_power_response in tighter_report.violations[:generator_9]
end

@testset "M2 security changes base dispatch" begin
    original = m2_case()
    branches = [Branch(b.id,b.from_bus,b.to_bus; resistance=b.resistance,
        reactance=b.reactance, charging=b.charging,
        thermal_limit=b.id == 11 ? 0.2 : b.thermal_limit) for b in original.network.branches]
    case = Case("constrained-m2"; base_power=original.base_power,base_frequency=original.base_frequency,
        network=ACNetwork(original.network.buses,branches),loads=original.loads,
        generators=original.generators,controls=original.controls,attachments=original.attachments)
    study = Study(case; contingencies=[Contingency(:line_33;branch_ids=[33])],
        participation=Dict(7=>1.0,9=>1.0))
    base = solve_opf(case)
    secured = solve_scopf(study)
    @test equilibrium_report(study,secured).valid
    @test secured.states[:base].pg[1] < base.state.pg[1] - 0.05
    @test secured.objective > base.objective + 1e-3
    @test abs(equilibrium_report(study,secured).scenarios[:line_33].branch_thermal_min_margin) < 1e-5
    unsecured = evaluate_contingencies(study,base.state; optimizer_attributes=Dict("max_iter"=>150))
    @test !equilibrium_report(study,unsecured).valid
    repeated = solve_scopf(study;initial_states=secured.states)
    @test equilibrium_report(study,repeated).valid
    @test repeated.objective ≈ secured.objective atol=1e-6
end

@testset "M2 serialization and exact encoding" begin
    case = m2_case()
    study = Study(case; contingencies=[Contingency(:line_22;branch_ids=[22]),
        Contingency(:generator_9;generator_ids=[9])], participation=Dict(7=>1.0,9=>1.0))
    result = solve_scopf(study; smooth_epsilon=1e-5)
    mktempdir() do dir
        saved_study = write_study(joinpath(dir,"study.json"),study)
        restored = read_study(saved_study)
        @test restored.case.id == study.case.id
        @test restored.participation == study.participation
        @test restored.contingencies[2].generator_ids == [9]
        restored_result = read_scopf_result(write_scopf_result(joinpath(dir,"result.json"),result))
        @test restored_result.states[:base].pg == result.states[:base].pg
        @test restored_result.balancing_power == result.balancing_power
        @test equilibrium_report(restored,restored_result).valid
        path = write_scopf_report(joinpath(dir,"report.json"),equilibrium_report(restored,restored_result))
        @test occursin("schema_version",read(path,String))
        @test_throws ArgumentError read_study(path)
        missing = deepcopy(result)
        missing.states[:line_22] = nothing
        saved = read_scopf_result(write_scopf_result(joinpath(dir,"missing.json"),missing))
        @test !equilibrium_report(restored,saved).valid
    end
    exact = solve_scopf(study; encoding=:complementarity, initial_states=result.states)
    @test exact.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED)
    @test equilibrium_report(study,exact;power_tolerance=1e-5,droop_tolerance=1e-4,
        limit_tolerance=1e-5,coupling_tolerance=1e-5).valid
    @test abs(exact.objective-result.objective) < 1e-4
end

@testset "M2 visual validation" begin
    case = m2_case()
    study = Study(case; contingencies=[Contingency(:line_22;branch_ids=[22]),
        Contingency(:generator_9;generator_ids=[9])], participation=Dict(7=>1.0,9=>1.0))
    result = solve_scopf(study; smooth_epsilon=1e-5)
    points = scopf_operating_points(study,result)
    @test length(points) == 5
    @test Set(point.scenario for point in points) == Set([:base,:line_22,:generator_9])
    mktempdir() do directory
        paths = write_scopf_validation_plots(directory,study,result)
        @test all(isfile,path for path in paths)
        @test all(path -> startswith(read(path,String),"<svg"),paths)
        droop = read(paths.droop,String)
        @test occursin("G7 line_22",droop)
        @test occursin("G9 base",droop)
        voltage = read(paths.voltage,String)
        @test occursin("Bus 10",voltage)
        @test occursin("generator_9",voltage)
        loading = read(paths.branch_loading,String)
        @test occursin("Branch 22",loading)
        @test occursin("× = outaged",loading)
        dispatch = read(paths.dispatch,String)
        @test occursin("Active P",dispatch)
        @test occursin("G9",dispatch)
        residuals = read(paths.residuals,String)
        @test occursin("Residual / tolerance",residuals)
        @test occursin("PASS",residuals)
        missing = deepcopy(result)
        missing.states[:line_22] = nothing
        @test_throws ArgumentError write_scopf_droop_plot(joinpath(directory,"bad.svg"),study,missing)
    end
end
