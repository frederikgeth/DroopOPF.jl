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
    case = Case("m10-filter-mesh"; base_power=100.0, base_frequency=50.0,
        network=ACNetwork(buses, branches), loads=Load[], generators,
        controls=VoltVarDroop[], attachments=GeneratorControlAttachment[])
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
