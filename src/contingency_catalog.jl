"""One candidate N-1 outage together with its structural disposition."""
struct ContingencyCatalogEntry
    contingency::Contingency
    device_kind::Symbol
    device_id::Int
    disposition::Symbol
    reason::Symbol
    function ContingencyCatalogEntry(contingency::Contingency, device_kind::Symbol,
        device_id::Integer, disposition::Symbol, reason::Symbol)
        device_kind in (:line, :transformer, :generator) ||
            throw(ArgumentError("unsupported contingency device kind"))
        disposition in (:eligible, :excluded) ||
            throw(ArgumentError("contingency disposition must be :eligible or :excluded"))
        device_id > 0 || throw(ArgumentError("contingency device ID must be positive"))
        new(contingency, device_kind, Int(device_id), disposition, reason)
    end
end

"""A deterministic, provenance-preserving N-1 candidate set for one case."""
struct ContingencyCatalog
    case_id::String
    entries::Vector{ContingencyCatalogEntry}
end

"""One exact-evaluation severity ranking; it never asserts that omitted cases are safe."""
struct ContingencyRank
    contingency_id::Symbol
    device_kind::Symbol
    device_id::Int
    classification::Symbol
    severity::Float64
    minimum_operating_margin::Float64
    termination_status::Symbol
end

"""A cheap pre-solve priority score; it is not a safety classification."""
struct ContingencyScreeningScore
    contingency_id::Symbol
    device_kind::Symbol
    device_id::Int
    raw_score::Float64
    percentile_score::Float64
end

function _connected_after_branch_outage(case::Case, branch_id::Int)
    network = case.network
    isnothing(network) && return false
    reference = only(bus.id for bus in network.buses if bus.reference)
    visited = Set([reference])
    while true
        before = length(visited)
        for branch in network.branches
            branch.available && branch.id != branch_id || continue
            if branch.from_bus in visited || branch.to_bus in visited
                push!(visited, branch.from_bus, branch.to_bus)
            end
        end
        before == length(visited) && return length(visited) == length(network.buses)
    end
end

"""
    contingency_catalog(case; include_branches=true, include_generators=true)

Enumerate every available single branch and generator outage without silently
discarding candidates. Branch outages that island the network are retained as
`:excluded` with reason `:islanding_unsupported`, because the current SCOPF
formulation has one reference angle and does not support island balancing.
Generator outages and connected line/transformer outages are `:eligible`.
"""
function contingency_catalog(case::Case; include_branches::Bool=true,
    include_generators::Bool=true)
    validate_case(case)
    isnothing(case.network) && throw(ArgumentError("contingency catalog requires an AC network"))
    entries = ContingencyCatalogEntry[]
    if include_branches
        for branch in sort([b for b in case.network.branches if b.available]; by=x -> x.id)
            contingency = Contingency(Symbol("branch_", branch.id); branch_ids=[branch.id])
            connected = _connected_after_branch_outage(case, branch.id)
            push!(entries, ContingencyCatalogEntry(contingency, branch.kind, branch.id,
                connected ? :eligible : :excluded,
                connected ? :connected_n1 : :islanding_unsupported))
        end
    end
    if include_generators
        for generator in sort([g for g in case.generators if g.available]; by=x -> x.id)
            contingency = Contingency(Symbol("generator_", generator.id);
                generator_ids=[generator.id])
            push!(entries, ContingencyCatalogEntry(contingency, :generator, generator.id,
                :eligible, :available_generator))
        end
    end
    return ContingencyCatalog(case.id, entries)
end

eligible_contingencies(catalog::ContingencyCatalog) =
    Contingency[entry.contingency for entry in catalog.entries if entry.disposition == :eligible]

excluded_contingencies(catalog::ContingencyCatalog) =
    ContingencyCatalogEntry[entry for entry in catalog.entries if entry.disposition == :excluded]

"""
    contingency_screening_scores(case, state; catalog=contingency_catalog(case))

Prioritize eligible outages using base-state branch loading within the branch
family and active-power share within the generator family. Scores are empirical
within-family percentiles so unlike raw quantities can share one queue. This is
a screening feature only: low score never means safe.
"""
function contingency_screening_scores(case::Case, state::ACState;
    catalog::ContingencyCatalog=contingency_catalog(case))
    catalog.case_id == case.id || throw(ArgumentError("catalog case ID does not match case"))
    length(state.pg) == length(case.generators) ||
        throw(ArgumentError("state generator vector does not match case"))
    flows = branch_flows(case.network, state)
    branch_indices = Dict(branch.id => i for (i, branch) in enumerate(case.network.branches))
    generator_indices = Dict(generator.id => i for (i, generator) in enumerate(case.generators))
    total_generation = sum(abs, state.pg)
    entries = [entry for entry in catalog.entries if entry.disposition == :eligible]
    raw = Dict{Symbol,Float64}()
    for entry in entries
        raw[entry.contingency.id] = if entry.device_kind in (:line, :transformer)
            i = branch_indices[entry.device_id]
            limit = case.network.branches[i].thermal_limit
            isfinite(limit) && limit > 0 ?
                max(abs(flows.from[i]), abs(flows.to[i])) / limit : 0.0
        else
            i = generator_indices[entry.device_id]
            total_generation > 0 ? abs(state.pg[i]) / total_generation : 0.0
        end
    end
    scores = ContingencyScreeningScore[]
    for kind in (:line, :transformer, :generator)
        family = filter(entry -> entry.device_kind == kind, entries)
        values = sort([raw[entry.contingency.id] for entry in family])
        denominator = max(length(values) - 1, 1)
        for entry in family
            value = raw[entry.contingency.id]
            percentile = length(values) == 1 ? 1.0 :
                (searchsortedlast(values, value) - 1) / denominator
            push!(scores, ContingencyScreeningScore(entry.contingency.id, kind,
                entry.device_id, value, percentile))
        end
    end
    sort!(scores; by=score -> (-score.percentile_score, -score.raw_score,
        string(score.contingency_id)))
    return scores
end

function markdown_report(catalog::ContingencyCatalog)
    lines = ["# Contingency catalog: $(catalog.case_id)", "",
        "Candidates are structurally classified before solving. Excluded entries are retained; they are not safe contingencies.", "",
        "| ID | Device | Device ID | Disposition | Reason |",
        "|---|---|---:|---|---|"]
    for entry in catalog.entries
        push!(lines, "| $(entry.contingency.id) | $(entry.device_kind) | $(entry.device_id) | $(entry.disposition) | $(entry.reason) |")
    end
    return join(lines, "\n")
end

function _contingency_rank_margin(report)
    minimum((report.voltage_min_margin, report.voltage_max_margin,
        report.generator_p_min_margin, report.generator_p_max_margin,
        report.generator_q_min_margin, report.generator_q_max_margin,
        report.branch_thermal_min_margin))
end

"""
    rank_contingencies(catalog, report)

Rank the contingencies represented in an independently generated `SCOPFReport`.
The ranking is an *evaluation result*, not a pre-solve filter: invalid and
physical-only results remain visible and sort ahead of accepted results.
Among accepted results, lower voltage, generator, or thermal margin means higher
severity. A catalog entry absent from `report` is omitted rather than presumed
safe.
"""
function rank_contingencies(catalog::ContingencyCatalog, report)
    entries = Dict(entry.contingency.id => entry for entry in catalog.entries
        if entry.disposition == :eligible)
    ranks = ContingencyRank[]
    for id in report.scenario_ids
        id == :base && continue
        haskey(entries, id) || continue
        entry = entries[id]
        scenario = get(report.scenarios, id, nothing)
        if isnothing(scenario)
            push!(ranks, ContingencyRank(id, entry.device_kind, entry.device_id,
                :invalid, Inf, -Inf, report.termination_status))
            continue
        end
        margin = _contingency_rank_margin(scenario)
        solver_accepted = report.termination_status in
            (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED, :OPTIMAL, :ALMOST_OPTIMAL)
        physical = isempty(get(report.violations, id, Symbol[]))
        classification = physical ? (solver_accepted ? :accepted : :physical_only) : :invalid
        severity = classification == :accepted ? -margin : Inf
        push!(ranks, ContingencyRank(id, entry.device_kind, entry.device_id,
            classification, severity, margin, report.termination_status))
    end
    sort!(ranks; by=x -> (-x.severity, string(x.contingency_id)))
    return ranks
end


function markdown_report(ranks::AbstractVector{<:ContingencyRank})
    lines = ["# Evaluated contingency ranking", "",
        "Invalid and physical-only outcomes are retained at the top of the ranking; this table does not certify unlisted contingencies.", "",
        "| Rank | ID | Device | Device ID | Classification | Severity | Minimum operating margin | Solver status |",
        "|---:|---|---|---:|---|---:|---:|---|"]
    for (index, rank) in enumerate(ranks)
        push!(lines, "| $index | $(rank.contingency_id) | $(rank.device_kind) | $(rank.device_id) | $(rank.classification) | $(rank.severity) | $(rank.minimum_operating_margin) | $(rank.termination_status) |")
    end
    return join(lines, "\n")
end
