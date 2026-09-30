import JSON

function m10_radial_case()
    buses = [Bus(i; reference=i == 1) for i in 1:5]
    branches = [
        Branch(10, 1, 2; resistance=0.01, reactance=0.1, thermal_limit=2.0),
        Branch(20, 2, 3; resistance=0.01, reactance=0.1, thermal_limit=2.0),
        Branch(30, 3, 4; resistance=0.01, reactance=0.1, thermal_limit=2.0),
        Branch(40, 4, 5; resistance=0.01, reactance=0.1, thermal_limit=2.0),
    ]
    generators = [
        Generator(1, 1; p_min=0.0, p_max=0.5, q_min=-1.0, q_max=1.0),
        Generator(2, 3; p_min=0.0, p_max=1.5, q_min=-1.0, q_max=1.0),
        Generator(3, 5; p_min=0.0, p_max=1.0, q_min=-1.0, q_max=1.0),
    ]
    Case("m10-radial-five"; base_power=100.0, base_frequency=50.0,
        network=ACNetwork(buses, branches), loads=Load[], generators,
        controls=VoltVarDroop[], attachments=GeneratorControlAttachment[])
end

function m10_filter_mesh_case()
    buses = [Bus(i; reference=i == 1) for i in 1:4]
    branches = [
        Branch(1, 1, 2; resistance=0.01, reactance=0.1, thermal_limit=2.0),
        Branch(2, 2, 3; resistance=0.01, reactance=0.1, thermal_limit=2.0),
        Branch(3, 3, 4; resistance=0.01, reactance=0.1, thermal_limit=2.0),
        Branch(4, 4, 1; resistance=0.01, reactance=0.1, thermal_limit=2.0),
        Branch(5, 1, 3; resistance=0.01, reactance=0.15, thermal_limit=2.0),
    ]
    generators = [
        Generator(1, 1; p_min=0.0, p_max=1.0, q_min=-1.0, q_max=1.0),
        Generator(2, 3; p_min=0.0, p_max=1.0, q_min=-1.0, q_max=1.0),
    ]
    Case("m10-filter-mesh"; base_power=100.0, base_frequency=50.0,
        network=ACNetwork(buses, branches), loads=Load[], generators,
        controls=VoltVarDroop[], attachments=GeneratorControlAttachment[])
end

@testset "M10 island-aware retained-component policy" begin
    case = m10_radial_case()
    flat = ACState(ones(5), zeros(5), zeros(3), zeros(3))

    split_reference = islanded_scenario_case(case,
        Contingency(:split_reference; branch_ids=[10]), flat)
    @test split_reference.selection.retained_bus_ids == [2, 3, 4, 5]
    @test split_reference.selection.discarded_bus_ids == [1]
    @test split_reference.selection.reference_reassigned
    @test split_reference.selection.selected_reference_bus_id == 3
    @test only(bus.id for bus in split_reference.case.network.buses if bus.reference) == 3

    split_spur = islanded_scenario_case(case,
        Contingency(:split_spur; branch_ids=[40]), flat)
    @test split_spur.selection.retained_bus_ids == [1, 2, 3, 4]
    @test split_spur.selection.discarded_bus_ids == [5]
    @test !split_spur.selection.reference_reassigned
    @test split_spur.selection.selected_reference_bus_id == 1
    @test split_spur.selection.discarded_generation_p_max == 1.0

    assessment = evaluate_islanding_contingency(case,
        Contingency(:split_spur; branch_ids=[40]), flat)
    @test assessment.selection == split_spur.selection
    @test assessment.report.valid
end

@testset "M10 conservative production filtering on a small mesh" begin
    case = m10_filter_mesh_case()
    flat = ACState(ones(4), zeros(4), zeros(2), zeros(2))
    @test validate_equilibrium(case, flat).valid
    decisions = filter_contingencies(case, flat; loading_threshold=0.8)
    @test count(decision -> decision.action == :screened, decisions) == 5
    @test count(decision -> decision.action == :exact, decisions) == 2
    @test all(decision.reason == :below_loading_threshold for decision in decisions
        if decision.device_kind == :branch)
    @test all(decision.reason == :generator_outage for decision in decisions
        if decision.device_kind == :generator)
    exact_assessments = evaluate_contingency_catalog(case, flat)
    exact_by_id = Dict(item.contingency.id => item for item in exact_assessments)
    @test all(exact_by_id[decision.contingency_id].rank.classification == :accepted
        for decision in decisions if decision.action == :screened)

    radial = m10_radial_case()
    radial_flat = ACState(ones(5), zeros(5), zeros(3), zeros(3))
    radial_decisions = filter_contingencies(radial, radial_flat)
    @test count(decision -> decision.action == :island_aware, radial_decisions) == 4
    @test count(decision -> decision.action == :exact, radial_decisions) == 3
    @test_throws ArgumentError filter_contingencies(case, flat; loading_threshold=0.0)
end

@testset "M10 integrated contingency pipeline checks and rankings" begin
    case = m10_filter_mesh_case()
    flat = ACState(ones(4), zeros(4), zeros(2), zeros(2))
    pipeline = assess_contingency_pipeline(case, flat;
        audit_screened_ids=[:branch_1])
    @test pipeline.checks.complete
    @test pipeline.checks.coverage_complete
    @test pipeline.checks.route_consistent
    @test pipeline.checks.screening_audit_pass
    @test !pipeline.checks.full_ac_coverage
    @test !pipeline.checks.all_outcomes_accepted
    @test pipeline.checks.screened_count == 4
    @test pipeline.checks.audited_screened_count == 1
    @test pipeline.checks.exact_evaluated_count == 2
    @test length(pipeline.assessments) == 7
    @test length(pipeline.branch_ranking) == 5
    @test length(pipeline.generator_ranking) == 2
    audited = only(filter(a -> a.entry.contingency.id == :branch_1,
        pipeline.assessments))
    @test audited.outcome == :screened_audited
    @test audited.rank.classification == :screening_audit_pass
    @test !isnothing(audited.exact_assessment)
    @test occursin("screened-not-evaluated", markdown_report(pipeline))

    exact = assess_contingency_pipeline(case, flat; screening_enabled=false)
    @test exact.checks.complete
    @test exact.checks.full_ac_coverage
    @test exact.checks.all_outcomes_accepted
    @test exact.checks.screened_count == 0
    @test exact.checks.exact_evaluated_count == 7
    @test all(a -> a.outcome == :exact_evaluated, exact.assessments)
    @test_throws ArgumentError assess_contingency_pipeline(case, flat;
        audit_screened_ids=[:unknown])
    @test_throws ArgumentError assess_contingency_pipeline(case, flat;
        audit_screened_ids=[:generator_1])
    @test_throws ArgumentError assess_contingency_pipeline(case, flat;
        screening_enabled=false, audit_screened_ids=[:branch_1])

    mktempdir() do directory
        path = write_contingency_pipeline(joinpath(directory, "pipeline.json"), pipeline)
        document = JSON.parsefile(path)
        @test document["kind"] == "DroopOPF.ContingencyPipelineResult"
        @test document["data"]["checks"]["complete"]
    end

    radial = m10_radial_case()
    radial_flat = ACState(ones(5), zeros(5), zeros(3), zeros(3))
    island_pipeline = assess_contingency_pipeline(radial, radial_flat)
    @test island_pipeline.checks.complete
    @test island_pipeline.checks.island_evaluated_count == 4
    @test island_pipeline.checks.exact_evaluated_count == 3
    reassigned = only(filter(a -> a.entry.contingency.id == :branch_10,
        island_pipeline.assessments))
    @test reassigned.island_assessment.selection.reference_reassigned
    @test reassigned.island_assessment.selection.selected_reference_bus_id == 3

    no_generator_island = Case("m10-no-generator-island"; base_power=100.0,
        base_frequency=50.0,
        network=ACNetwork([Bus(1; reference=true), Bus(2), Bus(3)], [
            Branch(10, 1, 2; resistance=0.01, reactance=0.1, thermal_limit=2.0),
            Branch(20, 1, 3; resistance=0.01, reactance=0.1, thermal_limit=2.0),
        ]), loads=Load[], generators=[
            Generator(1, 3; p_min=0.0, p_max=1.0, q_min=-1.0, q_max=1.0),
        ], controls=VoltVarDroop[], attachments=GeneratorControlAttachment[])
    no_generator_flat = ACState(ones(3), zeros(3), zeros(1), zeros(1))
    branch_catalog = contingency_catalog(no_generator_island;
        include_generators=false)
    retained_error = assess_contingency_pipeline(no_generator_island,
        no_generator_flat; catalog=branch_catalog)
    @test !retained_error.checks.complete
    @test retained_error.checks.error_count == 1
    @test first(retained_error.combined_ranking).classification == :evaluation_error
    @test_throws ArgumentError assess_contingency_pipeline(no_generator_island,
        no_generator_flat; catalog=branch_catalog, continue_on_error=false)
end
