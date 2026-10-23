include(joinpath(@__DIR__, "..", "examples", "scopf_validation_cases.jl"))

@testset "Small-network filtering qualification and physical edge cases" begin
    for kind in (:benign, :thermal, :voltage, :reactive, :transformer)
        case = scopf_parallel_case(kind)
        base = scopf_validation_base(case)
        @test equilibrium_report(case, base).valid
        qualification = validate_contingency_filter(case, base.state;
            optimizer_attributes=Dict("max_iter"=>300))
        @test qualification.no_observed_misses
        @test [r.total for r in qualification.families] == [1,1,2]
        @test all(r.screened_unresolved == 0 for r in qualification.families)
        @test all(last(r.ranking_budgets).found == r.unresolved for r in qualification.families)
        entries = qualification.exact.assessments
        if kind in (:benign, :transformer)
            @test qualification.exact.checks.all_outcomes_accepted
            @test sum(r.screened for r in qualification.families) == 2
        elseif kind in (:thermal, :voltage)
            branches = filter(a -> a.entry.device_kind != :generator, entries)
            @test all(a.rank.classification != :accepted for a in branches)
            @test all(d.action == :exact for d in qualification.decisions if d.device_kind != :generator)
        else
            generators = filter(a -> a.entry.device_kind == :generator, entries)
            @test all(a.rank.classification != :accepted for a in generators)
            @test all(!a.exact_assessment.report.physical_valid for a in generators)
        end
    end
    # Deliberately disable the voltage guard: the benchmark must detect the
    # resulting false screens, not silently report zero misses by construction.
    unsafe_case = scopf_parallel_case(:voltage)
    unsafe_base = scopf_validation_base(unsafe_case).state
    unsafe = validate_contingency_filter(unsafe_case,unsafe_base;
        voltage_guard=0.0,reactive_guard=0.0,ac_risk_guard=false,
        optimizer_attributes=Dict("max_iter"=>300))
    @test !unsafe.no_observed_misses
    @test sum(r.screened_unresolved for r in unsafe.families) == 2
    @test sum(r.screened_physical_failures for r in unsafe.families) == 2
    case = scopf_loaded_island_case()
    base = solve_opf(case)
    @test equilibrium_report(case,base).valid
    pipeline = assess_contingency_pipeline(case,base.state)
    selected = Dict(a.entry.device_id=>a for a in pipeline.assessments
        if a.entry.device_kind != :generator)
    @test selected[10].island_assessment.selection.selected_reference_bus_id == 3
    @test selected[10].rank.discarded_load_p ≈ 0.03
    @test selected[40].island_assessment.selection.selected_reference_bus_id == 1
    @test selected[40].rank.discarded_load_p ≈ 0.12
    @test all(a.rank.classification == :island_load_loss for a in values(selected))
    @test !pipeline.checks.all_outcomes_accepted
    @test first(pipeline.combined_ranking).discarded_load_p ≈ 0.12
    mktempdir() do dir
        @test isfile(write_contingency_pipeline(joinpath(dir,"islands.json"),pipeline))
    end
end

@testset "Campaign checkpoints, replay, and input identity" begin
    case = scopf_parallel_case()
    base = solve_opf(case).state
    mktempdir() do dir
        @test_throws InterruptException run_contingency_campaign(dir,case,base;
            on_checkpoint=a -> throw(InterruptException()))
        @test !ispath(joinpath(dir,".campaign-lock"))
        resumed = run_contingency_campaign(dir,case,base)
        @test resumed.resumed_count == 1
        @test resumed.evaluated_count == 3
        replay = run_contingency_campaign(dir,case,base)
        @test replay.resumed_count == 4
        @test replay.evaluated_count == 0
        @test replay.result.checks == resumed.result.checks
        @test DroopOPF._json_data(replay.result.combined_ranking) ==
            DroopOPF._json_data(resumed.result.combined_ranking)
        @test_throws ArgumentError run_contingency_campaign(dir,case,base; loading_threshold=0.7)
        @test_throws ArgumentError run_contingency_campaign(dir,case,base; sparse_balance=true)
        @test_throws ArgumentError run_contingency_campaign(dir,case,base; participation=Dict(1=>2.0,2=>1.0))
        @test_throws ArgumentError run_contingency_campaign(dir,case,base; optimizer_attributes=Dict("max_iter"=>5))
        @test_throws ArgumentError run_contingency_campaign(dir,case,base;
            catalog=contingency_catalog(case;include_generators=false))
        altered_network = ACNetwork(case.network.buses,
            [Branch(b.id,b.from_bus,b.to_bus; resistance=b.resistance,reactance=b.reactance,
                thermal_limit=3.0,kind=b.kind,tap_ratio=b.tap_ratio) for b in case.network.branches])
        altered_case = Case(case.id;base_power=case.base_power,base_frequency=case.base_frequency,
            network=altered_network,loads=case.loads,generators=case.generators,
            controls=case.controls,attachments=case.attachments)
        @test_throws ArgumentError run_contingency_campaign(dir,altered_case,base)
        changed = deepcopy(base)
        changed.va .+= 0.01 # electrically identical, but not the same saved base
        @test_throws ArgumentError run_contingency_campaign(dir,case,changed)
        checkpoint = joinpath(dir,"checkpoints","1.json")
        write(checkpoint, "incomplete JSON")
        repaired = run_contingency_campaign(dir,case,base)
        @test repaired.resumed_count == 3
        @test repaired.evaluated_count == 1
        mkdir(joinpath(dir,".campaign-lock"))
        @test_throws ArgumentError run_contingency_campaign(dir,case,base)
        rm(joinpath(dir,".campaign-lock"))
    end
    case = scopf_loaded_island_case()
    base = solve_opf(case).state
    mktempdir() do dir
        first_run = run_contingency_campaign(dir,case,base)
        replay = run_contingency_campaign(dir,case,base)
        @test replay.resumed_count == length(first_run.result.assessments)
        @test replay.evaluated_count == 0
        @test DroopOPF._json_data(replay.result.combined_ranking) ==
            DroopOPF._json_data(first_run.result.combined_ranking)
    end
    # Screened checkpoints (not just exact results) preserve the same semantics.
    screened_case = scopf_parallel_case()
    screened_base = scopf_validation_base(screened_case).state
    mktempdir() do dir
        first_run = run_contingency_campaign(dir,screened_case,screened_base;
            audit_screened_ids=[:branch_1])
        replay = run_contingency_campaign(dir,screened_case,screened_base;
            audit_screened_ids=[:branch_1])
        @test replay.resumed_count == 4
        @test replay.result.checks.screened_count == 1
        @test replay.result.checks.audited_screened_count == 1
        @test replay.result.checks == first_run.result.checks
    end
end

@testset "Numerical filtering fallback and catalog integrity" begin
    case = scopf_parallel_case()
    network = ACNetwork(case.network.buses,
        [Branch(b.id,b.from_bus,b.to_bus; resistance=b.resistance,reactance=0.0,
            thermal_limit=b.thermal_limit,kind=b.kind) for b in case.network.branches])
    zero_x = Case("zero-reactance";base_power=100.0,base_frequency=50.0,
        network,loads=Load[],generators=case.generators,
        controls=case.controls,attachments=case.attachments)
    flat = ACState(ones(2),zeros(2),zeros(2),zeros(2))
    decisions = filter_contingencies(zero_x,flat)
    @test all(d.reason == :numerical_fallback for d in decisions if d.device_kind != :generator)
    catalog = contingency_catalog(zero_x)
    duplicate = ContingencyCatalog(zero_x.id,[first(catalog.entries),first(catalog.entries)])
    @test_throws ArgumentError filter_contingencies(zero_x,flat;catalog=duplicate)
    forged = ContingencyCatalog(zero_x.id,[ContingencyCatalogEntry(
        Contingency(:branch_1;branch_ids=[2]),:line,1,:eligible,:connected)])
    @test_throws ArgumentError filter_contingencies(zero_x,flat;catalog=forged)
end
