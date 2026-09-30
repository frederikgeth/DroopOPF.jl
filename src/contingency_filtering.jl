"""One conservative pre-solve routing decision."""
struct ContingencyFilterDecision
    contingency_id::Symbol
    device_kind::Symbol
    device_id::Int
    action::Symbol
    reason::Symbol
    predicted_loading::Union{Nothing,Float64}
end

"""
    filter_contingencies(case, base_state; loading_threshold=0.8, voltage_guard=0.02)

Route N-1 candidates before exact AC evaluation. Generator outages always go
to exact evaluation. Islanding branches go to the island-aware path. Connected
line and transformer outages use a lossless DC LODF prediction; numerical
uncertainty and a tight base-voltage margin fall back to exact evaluation. Only
low-loading, well-conditioned network outages are screened.
"""
function filter_contingencies(case::Case, base_state::ACState;
    catalog::ContingencyCatalog=contingency_catalog(case),
    loading_threshold::Real=0.8, voltage_guard::Real=0.02,
    lodf_tolerance::Real=1e-8)
    0 < loading_threshold <= 1 || throw(ArgumentError("loading_threshold must lie in (0, 1]"))
    voltage_guard >= 0 && isfinite(voltage_guard) ||
        throw(ArgumentError("voltage_guard must be finite and nonnegative"))
    lodf_tolerance > 0 && isfinite(lodf_tolerance) ||
        throw(ArgumentError("lodf_tolerance must be positive and finite"))
    catalog.case_id == case.id || throw(ArgumentError("catalog case ID does not match case"))
    validate_equilibrium(case, base_state).valid ||
        throw(ArgumentError("base state must independently validate"))
    network = case.network
    bus_index = Dict(bus.id => i for (i, bus) in enumerate(network.buses))
    available = [branch for branch in network.branches if branch.available]
    nbus = length(network.buses)
    incidence = zeros(Float64, length(available), nbus)
    susceptance = zeros(Float64, length(available))
    for (k, branch) in enumerate(available)
        incidence[k, bus_index[branch.from_bus]] = 1.0
        incidence[k, bus_index[branch.to_bus]] = -1.0
        susceptance[k] = 1 / (branch.reactance * branch.tap_ratio)
    end
    bbus = transpose(incidence) * Diagonal(susceptance) * incidence
    reference = findfirst(bus -> bus.reference, network.buses)
    retained = [i for i in 1:nbus if i != reference]
    reduced = bbus[retained, retained]
    branch_index = Dict(branch.id => i for (i, branch) in enumerate(available))
    physical_index = Dict(branch.id => i for (i, branch) in enumerate(network.branches))
    flows = branch_flows(network, base_state)
    active_flow = [0.5 * (real(flows.from[physical_index[branch.id]]) -
        real(flows.to[physical_index[branch.id]])) for branch in available]
    minimum_voltage_margin = minimum(vcat(
        [base_state.vm[i] - bus.v_min for (i, bus) in enumerate(network.buses)],
        [bus.v_max - base_state.vm[i] for (i, bus) in enumerate(network.buses)]))
    decisions = ContingencyFilterDecision[]
    for entry in catalog.entries
        if entry.disposition == :excluded
            push!(decisions, ContingencyFilterDecision(entry.contingency.id,
                entry.device_kind, entry.device_id, :island_aware,
                entry.reason, nothing))
            continue
        elseif entry.device_kind == :generator
            push!(decisions, ContingencyFilterDecision(entry.contingency.id,
                :generator, entry.device_id, :exact, :generator_outage, nothing))
            continue
        elseif entry.device_kind in (:line, :transformer) &&
            minimum_voltage_margin <= voltage_guard
            push!(decisions, ContingencyFilterDecision(entry.contingency.id,
                entry.device_kind, entry.device_id, :exact, :voltage_guard, nothing))
            continue
        end
        k = branch_index[entry.device_id]
        transaction = incidence[k, :]
        prediction = try
            theta = reduced \ transaction[retained]
            full_theta = zeros(Float64, nbus)
            full_theta[retained] = theta
            ptdf = susceptance .* (incidence * full_theta)
            denominator = 1 - ptdf[k]
            abs(denominator) > lodf_tolerance || error("singular LODF")
            lodf = ptdf ./ denominator
            maximum(abs(active_flow[l] + lodf[l] * active_flow[k]) /
                available[l].thermal_limit for l in eachindex(available) if l != k; init=0.0)
        catch
            nothing
        end
        if isnothing(prediction)
            push!(decisions, ContingencyFilterDecision(entry.contingency.id,
                entry.device_kind, entry.device_id, :exact, :numerical_fallback, nothing))
        elseif prediction >= loading_threshold
            push!(decisions, ContingencyFilterDecision(entry.contingency.id,
                entry.device_kind, entry.device_id, :exact, :predicted_thermal_risk, prediction))
        else
            push!(decisions, ContingencyFilterDecision(entry.contingency.id,
                entry.device_kind, entry.device_id, :screened, :below_loading_threshold, prediction))
        end
    end
    return decisions
end
