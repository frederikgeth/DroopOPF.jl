import JSON

@testset "M10 general-network contingency assessment" begin
    case = m2_case()
    seed_study = Study(case; contingencies=[
        Contingency(:line_22; branch_ids=[22]),
        Contingency(:generator_9; generator_ids=[9])],
        participation=Dict(7 => 1.0, 9 => 1.0))
    seed = solve_scopf(seed_study; smooth_epsilon=1e-5)
    @test equilibrium_report(seed_study, seed).valid
    base_state = seed.states[:base]
    @test validate_equilibrium(case, base_state).valid

    catalog = contingency_catalog(case)
    @test [entry.contingency.id for entry in catalog.entries] ==
        [:branch_11, :branch_22, :branch_33, :generator_7, :generator_9]
    assessments = evaluate_contingency_catalog(case, base_state;
        catalog, participation=Dict(7 => 1.0, 9 => 1.0), smooth_epsilon=1e-5)
    @test length(assessments) == length(eligible_contingencies(catalog)) == 5
    @test [assessment.contingency.id for assessment in assessments] ==
        [entry.contingency.id for entry in catalog.entries]
    @test all(assessment.rank.contingency_id == assessment.contingency.id
        for assessment in assessments)
    @test all(assessment.report.scenario_ids == [:base, assessment.contingency.id]
        for assessment in assessments)
    @test all(assessment.rank.classification in (:accepted, :physical_only, :invalid)
        for assessment in assessments)

    scores = contingency_screening_scores(case, base_state; catalog)
    @test length(scores) == 5
    @test Set(score.contingency_id for score in scores) ==
        Set(entry.contingency.id for entry in catalog.entries)
    @test issorted([score.percentile_score for score in scores]; rev=true)
    @test all(0.0 <= score.percentile_score <= 1.0 for score in scores)
    @test count(score -> score.device_kind == :branch, scores) == 3
    @test count(score -> score.device_kind == :generator, scores) == 2

    invalid_base = deepcopy(base_state)
    invalid_base.pg[1] += 0.1
    @test_throws ArgumentError evaluate_contingency_catalog(case, invalid_base; catalog)
    other = Case("other"; base_power=case.base_power, base_frequency=case.base_frequency,
        network=case.network, loads=case.loads, generators=case.generators,
        controls=case.controls, attachments=case.attachments)
    @test_throws ArgumentError evaluate_contingency_catalog(other, base_state; catalog)
    @test_throws ArgumentError contingency_screening_scores(other, base_state; catalog)

    mktempdir() do directory
        catalog_path = write_contingency_catalog(joinpath(directory, "catalog.json"), catalog)
        ranking_path = write_contingency_ranking(joinpath(directory, "ranking.json"),
            [assessment.rank for assessment in assessments])
        @test JSON.parsefile(catalog_path)["data"]["case_id"] == case.id
        @test length(JSON.parsefile(ranking_path)["data"]) == 5
    end
end

@testset "M10 small-network exclusions and unresolved ranking" begin
    case = m2_case()
    catalog = contingency_catalog(case)
    seed_study = Study(case; contingencies=[Contingency(:line_22; branch_ids=[22])],
        participation=Dict(7 => 1.0, 9 => 1.0))
    seed = solve_scopf(seed_study; smooth_epsilon=1e-5)
    @test equilibrium_report(seed_study, seed).valid
    contingency = only(filter(c -> c.id == :generator_9, eligible_contingencies(catalog)))
    study = Study(case; contingencies=[contingency], mode=:corrective)
    result = evaluate_contingencies(study, seed.states[:base];
        smooth_epsilon=1e-5, optimizer_attributes=Dict("max_iter" => 150))
    rank = only(rank_contingencies(catalog, equilibrium_report(study, result)))
    @test rank.classification in (:invalid, :physical_only)

    island = Case("small-island"; base_power=100.0, base_frequency=50.0,
        network=ACNetwork([Bus(1; reference=true), Bus(2)],
            [Branch(4, 1, 2; resistance=0.01, reactance=0.1, thermal_limit=2.0)]),
        loads=[Load(1, 2; p=0.2, q=0.05)],
        generators=[Generator(3, 1; p_min=0.0, p_max=1.0,
            q_min=-1.0, q_max=1.0, initial_p=0.2, initial_q=0.0)],
        controls=VoltVarDroop[], attachments=GeneratorControlAttachment[])
    island_catalog = contingency_catalog(island; include_generators=false)
    @test isempty(eligible_contingencies(island_catalog))
    @test [(entry.contingency.id, entry.reason) for entry in
        excluded_contingencies(island_catalog)] == [(:branch_4, :islanding_unsupported)]
    island_scores = contingency_screening_scores(island,
        ACState([1.0, 1.0], [0.0, 0.0], [0.2], [0.05]))
    @test length(island_scores) == 1
    @test only(island_scores).contingency_id == :generator_3
    @test only(island_scores).percentile_score == 1.0
end
