"""Selection and accounting for the component retained after an islanding outage."""
struct IslandSelection
    contingency_id::Symbol
    retained_bus_ids::Vector{Int}
    discarded_bus_ids::Vector{Int}
    original_reference_bus_id::Int
    selected_reference_bus_id::Int
    reference_reassigned::Bool
    retained_load_p::Float64
    discarded_load_p::Float64
    retained_generation_p_max::Float64
    discarded_generation_p_max::Float64
end

Base.:(==)(left::IslandSelection, right::IslandSelection) =
    all(getfield(left, name) == getfield(right, name) for name in fieldnames(IslandSelection))

"""Reduced-network OPF and independent validation for one islanding outage."""
struct IslandedContingencyAssessment
    selection::IslandSelection
    case::Case
    result::ACOPFResult
    report::EquilibriumReport
end

function _network_components(network::ACNetwork, outaged::Set{Int})
    unseen = Set(bus.id for bus in network.buses)
    components = Set{Int}[]
    while !isempty(unseen)
        component = Set([minimum(unseen)])
        while true
            before = length(component)
            for branch in network.branches
                branch.available && !(branch.id in outaged) || continue
                if branch.from_bus in component || branch.to_bus in component
                    push!(component, branch.from_bus, branch.to_bus)
                end
            end
            length(component) == before && break
        end
        setdiff!(unseen, component)
        push!(components, component)
    end
    return components
end

function _component_priority(case::Case, component::Set{Int})
    load = sum(item.p for item in case.loads if item.bus_id in component; init=0.0)
    capacity = sum(item.p_max for item in case.generators
        if item.available && item.bus_id in component; init=0.0)
    return (length(component), load, capacity, -minimum(component))
end

"""
    islanded_scenario_case(case, contingency, base_state)

Build the connected component to balance after a branch outage. The original
reference-bus component is retained unless another component has strictly more
buses. In that case the largest component is retained and the bus of its
largest available generator becomes the new reference. Ties retain the
original reference component. Discarded load and generation are reported.
"""
function islanded_scenario_case(case::Case, contingency::Contingency,
    base_state::ACState)
    isempty(contingency.generator_ids) ||
        throw(ArgumentError("island-aware reduction currently supports branch outages only"))
    !isempty(contingency.branch_ids) || throw(ArgumentError("branch outage is required"))
    network = case.network
    isnothing(network) && throw(ArgumentError("island-aware reduction requires an AC network"))
    length(base_state.vm) == length(network.buses) &&
        length(base_state.pg) == length(case.generators) ||
        throw(ArgumentError("base state dimensions do not match case"))
    available_ids = Set(branch.id for branch in network.branches if branch.available)
    all(id -> id in available_ids, contingency.branch_ids) ||
        throw(ArgumentError("unknown or unavailable branch outage"))
    components = _network_components(network, Set(contingency.branch_ids))
    original_reference = only(bus.id for bus in network.buses if bus.reference)
    reference_component = only(component for component in components
        if original_reference in component)
    largest = last(sort(components; by=component -> _component_priority(case, component)))
    selected = length(largest) > length(reference_component) ? largest : reference_component
    generators = [(index=i, generator=g) for (i, g) in enumerate(case.generators)
        if g.available && g.bus_id in selected]
    isempty(generators) && throw(ArgumentError("selected island has no available generator"))
    selected_reference = original_reference in selected ? original_reference :
        last(sort(generators; by=item ->
            (item.generator.p_max, -item.generator.id))).generator.bus_id
    retained = Set(selected)
    discarded = setdiff(Set(bus.id for bus in network.buses), retained)
    buses = [Bus(bus.id; v_min=bus.v_min, v_max=bus.v_max,
        reference=bus.id == selected_reference) for bus in network.buses if bus.id in retained]
    branches = [Branch(branch.id, branch.from_bus, branch.to_bus;
        resistance=branch.resistance, reactance=branch.reactance,
        charging=branch.charging, thermal_limit=branch.thermal_limit,
        available=branch.available && !(branch.id in contingency.branch_ids),
        tap_ratio=branch.tap_ratio, phase_shift=branch.phase_shift, kind=branch.kind)
        for branch in network.branches
        if branch.from_bus in retained && branch.to_bus in retained]
    shunts = [shunt for shunt in network.shunts if shunt.bus_id in retained]
    banks = [bank for bank in network.banks if bank.bus_id in retained]
    loads = [load for load in case.loads if load.bus_id in retained]
    # A validated numerical base can overshoot a bound within replay tolerance.
    # Reconstructed Generator data have strict domains: project only these tiny
    # start/reference overshoots, without modifying the saved physical base.
    function initial_value(value, lower, upper)
        lower-1e-6 <= value <= upper+1e-6 ||
            throw(ArgumentError("island base dispatch exceeds generator bounds beyond tolerance"))
        clamp(value,lower,upper)
    end
    reduced_generators = [Generator(item.generator.id, item.generator.bus_id;
        available=true, s_rated=item.generator.s_rated, p_min=item.generator.p_min, p_max=item.generator.p_max,
        q_min=item.generator.q_min, q_max=item.generator.q_max,
        initial_p=initial_value(base_state.pg[item.index],item.generator.p_min,item.generator.p_max),
        initial_q=initial_value(base_state.qg[item.index],item.generator.q_min,item.generator.q_max))
        for item in generators]
    generator_ids = Set(generator.id for generator in reduced_generators)
    attachments = [attachment for attachment in case.attachments
        if attachment.generator_id in generator_ids && attachment.location.bus_id in retained]
    reduced = Case(case.id * "/" * string(contingency.id) * "/retained";
        base_power=case.base_power, base_frequency=case.base_frequency,
        network=ACNetwork(buses, branches; shunts, banks), loads,
        generators=reduced_generators, controls=case.controls, attachments)
    retained_load = sum(load.p for load in case.loads if load.bus_id in retained; init=0.0)
    discarded_load = sum(load.p for load in case.loads if load.bus_id in discarded; init=0.0)
    retained_capacity = sum(generator.p_max for generator in case.generators
        if generator.available && generator.bus_id in retained; init=0.0)
    discarded_capacity = sum(generator.p_max for generator in case.generators
        if generator.available && generator.bus_id in discarded; init=0.0)
    selection = IslandSelection(contingency.id, sort!(collect(retained)),
        sort!(collect(discarded)), original_reference, selected_reference,
        selected_reference != original_reference, Float64(retained_load),
        Float64(discarded_load), Float64(retained_capacity), Float64(discarded_capacity))
    return (; case=reduced, selection)
end

"""Solve and independently validate the retained component of an islanding outage."""
function evaluate_islanding_contingency(case::Case, contingency::Contingency,
    base_state::ACState; kwargs...)
    validate_equilibrium(case, base_state).valid ||
        throw(ArgumentError("base state must independently validate"))
    scenario = islanded_scenario_case(case, contingency, base_state)
    result = solve_opf(scenario.case; kwargs...)
    report = equilibrium_report(scenario.case, result)
    return IslandedContingencyAssessment(scenario.selection, scenario.case, result, report)
end
