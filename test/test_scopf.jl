include(joinpath(@__DIR__, "..", "examples", "m2_case.jl"))
using JSON

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
    @test Study(case; contingencies=[line]).participation == default_participation(case)
    @test_throws ArgumentError Study(case; contingencies=[gen], participation=Dict(9=>1.0))
    @test_throws ArgumentError Study(case; participation=Dict(1=>1.0))
    @test_throws ArgumentError Study(case; participation=Dict(7=>NaN))
    @test_throws ArgumentError Study(case; redispatch_limits=Dict(7=>-0.1))
    @test_throws ArgumentError Study(case; mode=:corrective, participation=Dict(7=>1.0))

    catalog = contingency_catalog(case)
    @test length(catalog.entries) == length(case.network.branches) + length(case.generators)
    @test length(eligible_contingencies(catalog)) == length(catalog.entries)
    @test isempty(excluded_contingencies(catalog))
    @test occursin("Candidates are structurally classified", markdown_report(catalog))
    mktempdir() do directory
        path = write_contingency_catalog(joinpath(directory, "catalog.json"), catalog)
        @test occursin("DroopOPF.ContingencyCatalog", read(path, String))
    end

    island_case = Case("catalog-island"; base_power=100.0, base_frequency=50.0,
        controls=VoltVarDroop[], attachments=GeneratorControlAttachment[],
        network=ACNetwork([Bus(1; reference=true), Bus(2)],
            [Branch(1, 1, 2; resistance=0.01, reactance=0.1, thermal_limit=5.0)]),
        loads=[Load(1, 2; p=0.2, q=0.1)],
        generators=[Generator(1, 1; p_min=0.0, p_max=1.0, q_min=-1.0,
            q_max=1.0, initial_p=0.2, initial_q=0.0)])
    island_catalog = contingency_catalog(island_case; include_generators=false)
    @test isempty(eligible_contingencies(island_catalog))
    @test only(excluded_contingencies(island_catalog)).reason == :islanding_unsupported
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

    catalog = contingency_catalog(case)
    line_entry = only(filter(entry -> entry.device_kind == :line &&
        entry.device_id == 22, catalog.entries))
    rank_study = Study(case; contingencies=[line_entry.contingency],
        participation=Dict(7=>1.0, 9=>1.0))
    rank_result = solve_scopf(rank_study; smooth_epsilon=1e-5)
    ranks = rank_contingencies(catalog, equilibrium_report(rank_study, rank_result))
    @test length(ranks) == 1
    @test only(ranks).contingency_id == :branch_22
    @test all(rank.classification == :accepted for rank in ranks)
    @test occursin("Evaluated contingency ranking", markdown_report(ranks))
    mktempdir() do directory
        path = write_contingency_ranking(joinpath(directory, "ranking.json"), ranks)
        @test occursin("DroopOPF.ContingencyRanking", read(path, String))
    end

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

@testset "M9.1 equipment timing and independent replay" begin
    source = m2_case()
    bank = ShuntBank(201, 30; step_susceptances=(0.02,),
        step_conductances=(0.0,), legal_states=((0,), (1,), (2,), (3,)),
        state=(1,), nominal_state=(1,))
    case = Case("m9-equipment"; base_power=source.base_power,
        base_frequency=source.base_frequency,
        network=ACNetwork(source.network.buses, source.network.branches;
            shunts=source.network.shunts, banks=[bank]), loads=source.loads,
        generators=source.generators, controls=source.controls,
        attachments=source.attachments)
    taps = [TapControl(11; lower=0.95, upper=1.05, initial=1.0, nominal=1.0)]
    shunts = [ShuntControl(201; lower=0.0, upper=0.06, initial=0.02, nominal=0.02)]
    contingencies = [Contingency(:line_22; branch_ids=[22]),
        Contingency(:generator_9; generator_ids=[9])]
    assignments = reactive_control_assignments(case)
    policy = SCOPFControlPolicy(taps=:preventive, shunts=:preventive)
    study = Study(case; contingencies, participation=Dict(7=>2.0, 9=>1.0),
        reactive_assignments=assignments, tap_controls=taps,
        shunt_controls=shunts, control_policy=policy)
    # Stage the enlarged nonlinear solve from the established fixed-equipment
    # SCOPF. This is deliberately part of the regression contract: an unseeded
    # equipment solve can select an infeasible Ipopt restoration point.
    seed_study = Study(source; contingencies,
        participation=Dict(7=>2.0, 9=>1.0),
        reactive_assignments=reactive_control_assignments(source))
    seed = solve_scopf(seed_study; smooth_epsilon=1e-5)
    @test equilibrium_report(seed_study, seed).valid
    result = solve_scopf(study; smooth_epsilon=1e-5, initial_states=seed.states)
    report = equilibrium_report(study, result)
    @test report.valid
    phase1 = solve_scopf(study; smooth_epsilon=1e-5,
        initial_states=result.states,_phase1_power_balance=true)
    @test phase1.objective <= 1e-7
    @test equilibrium_report(study,phase1).physical_valid
    @test result.control_policy == policy
    @test result.reactive_assignments == assignments
    @test result.tap_controls == taps
    @test result.shunt_controls == shunts
    @test all(isapprox(result.tap_settings[id][11], result.tap_settings[:base][11];
        atol=1e-8) for id in (:line_22, :generator_9))
    @test all(isapprox(result.shunt_settings[id][201], result.shunt_settings[:base][201];
        atol=1e-8) for id in (:line_22, :generator_9))
    @test maximum(values(report.equipment_coupling_violation)) < 1e-8
    plot_ids, plot_cases, plot_states = DroopOPF._scopf_plot_data(study, result)
    for (id, physical, state) in zip(plot_ids, plot_cases, plot_states)
        declared = id == :base ? case : scenario_case(case, only(filter(c -> c.id == id, contingencies)))
        expected = with_shunt_settings(with_tap_settings(declared,
            result.tap_settings[id]), result.shunt_settings[id])
        @test branch_flows(physical.network,state) == branch_flows(expected.network,state)
    end

    exact_taps = [TapControl(11; lower=0.95, upper=1.05,
        initial=result.tap_settings[:base][11], nominal=1.0)]
    exact_shunts = [ShuntControl(201; lower=0.0, upper=0.06,
        initial=result.shunt_settings[:base][201], nominal=0.02)]
    exact_study = Study(case; contingencies,
        participation=Dict(7=>2.0, 9=>1.0),
        reactive_assignments=assignments, tap_controls=exact_taps,
        shunt_controls=exact_shunts,
        control_policy=SCOPFControlPolicy(taps=:preventive, shunts=:preventive))
    exact = solve_scopf(exact_study; encoding=:complementarity,
        initial_states=result.states)
    @test exact.termination_status in (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED)
    @test equilibrium_report(exact_study, exact; power_tolerance=1e-5,
        droop_tolerance=1e-4, limit_tolerance=1e-5,
        coupling_tolerance=1e-5).valid

    corrupted = deepcopy(result)
    corrupted.tap_settings[:line_22][11] += 0.01
    bad = equilibrium_report(study, corrupted)
    @test :equipment_response in bad.violations[:line_22]
    @test :power_balance in bad.violations[:line_22]

    corrective_taps = [TapControl(11; lower=0.95, upper=1.05,
        initial=result.tap_settings[:base][11], nominal=1.0)]
    corrective_shunts = [ShuntControl(201; lower=0.0, upper=0.06,
        initial=result.shunt_settings[:base][201], nominal=0.02)]
    corrective = Study(case; contingencies, mode=:corrective,
        redispatch_limits=Dict(7=>0.8, 9=>0.8), tap_controls=corrective_taps,
        shunt_controls=corrective_shunts,
        control_policy=SCOPFControlPolicy(taps=:corrective, shunts=:corrective))
    corrected = solve_scopf(corrective; smooth_epsilon=1e-5,
        initial_states=result.states)
    @test equilibrium_report(corrective, corrected).valid

    movement_policy = SCOPFControlPolicy(taps=:corrective, shunts=:corrective,
        tap_movement_limits=Dict(11=>0.005),
        shunt_movement_limits=Dict(201=>0.01))
    settled_study = Study(case; contingencies,
        participation=Dict(7=>2.0, 9=>1.0), reactive_assignments=assignments,
        tap_controls=corrective_taps, shunt_controls=corrective_shunts,
        control_policy=movement_policy)
    stages = assess_scopf_response_stages(study, settled_study, result;
        immediate_solve_kwargs=(; smooth_epsilon=1e-5,
            initial_states=result.states),
        validation_kwargs=(; coupling_tolerance=1e-5))
    @test stages.immediate_report.valid
    @test stages.settled_report.valid
    @test all(m.immediate_movement.tap < 1e-8 &&
        m.immediate_movement.shunt < 1e-8 for m in values(stages.scenario_metrics))
    @test all(m.settled_movement.tap <= 0.005 + 1e-6 &&
        m.settled_movement.shunt <= 0.01 + 1e-6
        for m in values(stages.scenario_metrics))
    assembled = assemble_scopf_response_stages(study, settled_study,
        stages.immediate, stages.settled;
        validation_kwargs=(; coupling_tolerance=1e-5))
    @test assembled.immediate_report.valid == stages.immediate_report.valid
    @test assembled.settled_report.valid == stages.settled_report.valid
    @test assembled.scenario_metrics == stages.scenario_metrics
    @test occursin("paired steady-state", markdown_report(stages))
    over_budget = deepcopy(stages.settled)
    over_budget.tap_settings[:line_22][11] =
        over_budget.tap_settings[:base][11] + 0.006
    @test :equipment_response in
        equilibrium_report(settled_study, over_budget).violations[:line_22]

    outaged = Study(case; contingencies=[Contingency(:line_11; branch_ids=[11])],
        participation=Dict(7=>1.0, 9=>1.0), tap_controls=taps,
        shunt_controls=shunts,
        control_policy=SCOPFControlPolicy(taps=:preventive, shunts=:preventive))
    outaged_seed_study = Study(source;
        contingencies=[Contingency(:line_11; branch_ids=[11])],
        participation=Dict(7=>1.0, 9=>1.0))
    outaged_seed = solve_scopf(outaged_seed_study; smooth_epsilon=1e-5)
    outaged_result = solve_scopf(outaged; smooth_epsilon=1e-5,
        initial_states=outaged_seed.states)
    @test !haskey(outaged_result.tap_settings[:line_11], 11)
    @test equilibrium_report(outaged, outaged_result).valid

    @test_throws ArgumentError SCOPFControlPolicy(taps=:automatic)
    @test_throws ArgumentError SCOPFControlPolicy(shunts=:automatic)
    @test_throws ArgumentError SCOPFControlPolicy(reactive=:corrective)
    @test_throws ArgumentError SCOPFControlPolicy(
        taps=:preventive, tap_movement_limits=Dict(11=>0.01))
    @test_throws ArgumentError SCOPFControlPolicy(taps=:corrective,
        tap_movement_limits=Dict(11=>-0.01))
    @test_throws ArgumentError Study(case; tap_controls=taps,
        control_policy=SCOPFControlPolicy(taps=:corrective,
            tap_movement_limits=Dict(999=>0.01)))
    default_policy = SCOPFControlPolicy()
    @test default_policy.taps == :corrective
    @test default_policy.shunts == :corrective
    @test isnothing(default_policy.tap_movement_limits)
    @test isnothing(default_policy.shunt_movement_limits)
    default_timing_study = Study(case; tap_controls=taps,
        shunt_controls=shunts)
    @test default_timing_study.control_policy == default_policy
    @test_throws ArgumentError evaluate_contingencies(study, result.states[:base])
    policy_only = Study(source; control_policy=SCOPFControlPolicy(
        taps=:corrective, shunts=:corrective))
    fixed_policy = evaluate_contingencies(policy_only, seed.states[:base])
    @test fixed_policy.control_policy == policy_only.control_policy
    @test equilibrium_report(policy_only, fixed_policy).valid

    mktempdir() do dir
        restored_study = read_study(write_study(joinpath(dir, "m9-study.json"), study))
        @test restored_study.control_policy == study.control_policy
        @test restored_study.tap_controls == taps
        @test restored_study.shunt_controls == shunts
        restored_result = read_scopf_result(
            write_scopf_result(joinpath(dir, "m9-result.json"), result))
        @test restored_result.tap_settings == result.tap_settings
        @test restored_result.shunt_settings == result.shunt_settings
        @test equilibrium_report(restored_study, restored_result).valid
        nonfinite_equipment = deepcopy(result)
        nonfinite_equipment.tap_settings[:base][11] = NaN
        nonfinite_path = write_scopf_result(
            joinpath(dir,"m9-nonfinite-equipment.json"),nonfinite_equipment)
        @test isnan(read_scopf_result(nonfinite_path).tap_settings[:base][11])
        restored_budget = read_study(write_study(
            joinpath(dir, "m9-budget-study.json"), settled_study))
        @test restored_budget.control_policy == movement_policy
        stage_path = write_scopf_stage_assessment(
            joinpath(dir, "m9-stage-assessment.json"), stages)
        @test JSON.parsefile(stage_path)["kind"] == "DroopOPF.SCOPFStageAssessment"

        v7_study = JSON.parsefile(joinpath(dir, "m9-study.json"))
        v7_study["schema_version"] = 7
        delete!(v7_study["data"]["control_policy"], "tap_movement_limits")
        delete!(v7_study["data"]["control_policy"], "shunt_movement_limits")
        v7_path = joinpath(dir, "m9-v7-study.json")
        write(v7_path, JSON.json(v7_study))
        @test isnothing(read_study(v7_path).control_policy.tap_movement_limits)

        legacy_study = JSON.parsefile(joinpath(dir, "m9-study.json"))
        legacy_study["schema_version"] = 6
        for field in ("tap_controls", "shunt_controls", "control_policy")
            delete!(legacy_study["data"], field)
        end
        legacy_study_path = joinpath(dir, "m8-study.json")
        write(legacy_study_path, JSON.json(legacy_study))
        migrated_study = read_study(legacy_study_path)
        @test isempty(migrated_study.tap_controls)
        @test isempty(migrated_study.shunt_controls)
        @test migrated_study.control_policy == SCOPFControlPolicy(
            taps=:preventive, shunts=:preventive)

        legacy_result = JSON.parsefile(joinpath(dir, "m9-result.json"))
        legacy_result["schema_version"] = 2
        for field in ("tap_settings", "shunt_settings", "tap_controls",
            "shunt_controls", "control_policy")
            delete!(legacy_result["data"], field)
        end
        legacy_result_path = joinpath(dir, "m8-result.json")
        write(legacy_result_path, JSON.json(legacy_result))
        migrated_result = read_scopf_result(legacy_result_path)
        @test isempty(migrated_result.tap_settings)
        @test isempty(migrated_result.shunt_settings)
        @test migrated_result.control_policy == SCOPFControlPolicy(
            taps=:preventive, shunts=:preventive)
    end
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
        inputs = read(paths.inputs,String)
        @test occursin("line 22",inputs)
        network = read(paths.network,String)
        @test occursin("Declared AC network",network)
        @test occursin("Bus 10",network)
        @test occursin("B22 line",network)
        @test occursin("generator 9",inputs)
        @test occursin("preventive",inputs)
        margins = read(paths.margins,String)
        @test occursin("Thermal",margins)
        @test occursin("Q max",margins)
        deltas = read(paths.response_deltas,String)
        @test occursin("max |ΔV|",deltas)
        @test occursin("max |ΔP|",deltas)
        matrix = read(paths.validation_matrix,String)
        @test occursin("AC balance",matrix)
        @test occursin("PASS",matrix)
        missing = deepcopy(result)
        missing.states[:line_22] = nothing
        @test_throws ArgumentError write_scopf_droop_plot(joinpath(directory,"bad.svg"),study,missing)
        missing_paths = write_scopf_validation_plots(joinpath(directory,"missing"), study, missing)
        @test occursin("NOT EVALUATED", read(missing_paths.validation_matrix, String))
        @test occursin("NOT EVALUATED", read(missing_paths.branch_loading, String))
        @test occursin("Branch 11", read(missing_paths.branch_loading, String))
        @test occursin("Bus 10", read(missing_paths.voltage, String))
        @test !occursin("<polyline", read(missing_paths.voltage, String))
        @test occursin("G7 generator_9", read(missing_paths.droop, String))
        no_base = deepcopy(result)
        no_base.states[:base] = nothing
        no_base_paths = write_scopf_validation_plots(joinpath(directory,"no-base"),study,no_base)
        @test occursin("Bus 10", read(no_base_paths.voltage,String))
        @test occursin("base state unavailable", read(no_base_paths.response_deltas,String))
        @test isfile(write_scopf_evaluation_report(joinpath(directory,"missing","evaluation.md"), study, missing))
        corrupted = deepcopy(result)
        corrupted.states[:generator_9].qg[2] = 0.1
        invalid_matrix = write_scopf_validation_matrix_plot(
            joinpath(directory,"invalid-matrix.svg"),study,corrupted)
        @test occursin("FAIL",read(invalid_matrix,String))
        invalid_margins = write_scopf_margin_plot(
            joinpath(directory,"invalid-margins.svg"),study,corrupted)
        @test startswith(read(invalid_margins,String),"<svg")
        evaluation = write_scopf_evaluation_report(
            joinpath(directory,"evaluation.md"),study,result; plot_paths=paths)
        evaluation_text = read(evaluation,String)
        @test occursin("Declared scenario inputs",evaluation_text)
        @test occursin("Numerical validation",evaluation_text)
        @test occursin("Assumptions and interpretation", evaluation_text)
        @test occursin("Validation tolerances", evaluation_text)
        @test isfile(joinpath(directory,"evaluation-inputs.json"))
        @test equilibrium_report(read_study(joinpath(directory,"evaluation-inputs.json")),
            read_scopf_result(joinpath(directory,"evaluation-outputs.json"))).valid
    end
end
