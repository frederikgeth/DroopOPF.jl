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
uncertainty and a tight base-voltage margin fall back to exact evaluation.
`reactive_guard=0.1` escalates when aggregate bidirectional Q headroom is at
most 10% of available Q range. `ac_risk_guard=true` also checks apparent-flow
redistribution and an impedance-based incremental voltage-drop indicator.
These are escalation heuristics, not AC power-flow solutions or bounds.
Set `reactive_guard=0, ac_risk_guard=false` to replay the legacy policy.
Opt-in `droop_response_guard=true` adds individual Q-reserve and bounded
AC/droop-response risk checks for fixed-equipment legacy droops. Unsupported
or uncertain predictions escalate to exact AC; the default remains unchanged.
`participation` must match the subsequent fixed-base exact evaluation.
"""
function filter_contingencies(case::Case, base_state::ACState;
    catalog::ContingencyCatalog=contingency_catalog(case),
    loading_threshold::Real=0.8, voltage_guard::Real=0.02,
    lodf_tolerance::Real=1e-8, reactive_guard::Real=0.1,
    ac_risk_guard::Bool=true, droop_response_guard::Bool=false,
    participation::AbstractDict=default_participation(case))
    0 <= reactive_guard <= 0.5 || throw(ArgumentError("reactive_guard must lie in [0, 0.5]"))
    0 < loading_threshold <= 1 || throw(ArgumentError("loading_threshold must lie in (0, 1]"))
    voltage_guard >= 0 && isfinite(voltage_guard) ||
        throw(ArgumentError("voltage_guard must be finite and nonnegative"))
    lodf_tolerance > 0 && isfinite(lodf_tolerance) ||
        throw(ArgumentError("lodf_tolerance must be positive and finite"))
    catalog.case_id == case.id || throw(ArgumentError("catalog case ID does not match case"))
    canonical = Dict(e.contingency.id=>e for e in contingency_catalog(case).entries)
    length(unique(e.contingency.id for e in catalog.entries)) == length(catalog.entries) ||
        throw(ArgumentError("catalog contains duplicate contingency IDs"))
    all(e -> haskey(canonical,e.contingency.id) &&
        _json_data(e) == _json_data(canonical[e.contingency.id]), catalog.entries) ||
        throw(ArgumentError("catalog entries do not match the current network"))
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
    factor = try
        all(isfinite, reduced) || error("nonfinite DC matrix")
        factorize(reduced)
    catch error
        error isa InterruptException && rethrow()
        nothing
    end
    branch_index = Dict(branch.id => i for (i, branch) in enumerate(available))
    physical_index = Dict(branch.id => i for (i, branch) in enumerate(network.branches))
    flows = branch_flows(network, base_state)
    active_flow = [0.5 * (real(flows.from[physical_index[branch.id]]) -
        real(flows.to[physical_index[branch.id]])) for branch in available]
    reactive_flow = [0.5 * (imag(flows.from[physical_index[branch.id]]) -
        imag(flows.to[physical_index[branch.id]])) for branch in available]
    generators = [(i,g) for (i,g) in enumerate(case.generators) if g.available]
    qrange = sum(g.q_max-g.q_min for (_,g) in generators;init=0.0)
    qreserve = min(sum(g.q_max-base_state.qg[i] for (i,g) in generators;init=0.0),
        sum(base_state.qg[i]-g.q_min for (i,g) in generators;init=0.0))
    reserve_fraction = qrange > 0 ? qreserve/qrange : 0.0
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
        elseif reactive_guard > 0 && reserve_fraction <= reactive_guard
            push!(decisions, ContingencyFilterDecision(entry.contingency.id,
                entry.device_kind, entry.device_id, :exact, :reactive_reserve_guard, nothing))
            continue
        end
        k = branch_index[entry.device_id]
        transaction = incidence[k, :]
        prediction = try
            isnothing(factor) && error("DC factorization unavailable")
            theta = factor \ transaction[retained]
            full_theta = zeros(Float64, nbus)
            full_theta[retained] = theta
            ptdf = susceptance .* (incidence * full_theta)
            denominator = 1 - ptdf[k]
            abs(denominator) > lodf_tolerance || error("singular LODF")
            lodf = ptdf ./ denominator
            active = maximum(abs(active_flow[l] + lodf[l] * active_flow[k]) /
                available[l].thermal_limit for l in eachindex(available) if l != k; init=0.0)
            apparent = maximum(hypot(active_flow[l]+lodf[l]*active_flow[k],
                reactive_flow[l]+lodf[l]*reactive_flow[k])/available[l].thermal_limit
                for l in eachindex(available) if l != k; init=0.0)
            # AC-informed risk surrogate, NOT an AC power-flow prediction:
            # bound-like voltage-drop indicator from redistributed apparent flow.
            voltage_change = maximum(hypot(available[l].resistance,available[l].reactance)*
                abs(lodf[l])*hypot(active_flow[k],reactive_flow[k])/minimum(base_state.vm)
                for l in eachindex(available) if l != k; init=0.0)
            (;active,apparent,voltage_change)
        catch error
            error isa InterruptException && rethrow()
            nothing
        end
        if isnothing(prediction) || !all(isfinite,values(prediction))
            push!(decisions, ContingencyFilterDecision(entry.contingency.id,
                entry.device_kind, entry.device_id, :exact, :numerical_fallback, nothing))
        elseif prediction.active >= loading_threshold
            push!(decisions, ContingencyFilterDecision(entry.contingency.id,
                entry.device_kind, entry.device_id, :exact, :predicted_thermal_risk, prediction.active))
        elseif ac_risk_guard && prediction.apparent >= loading_threshold
            push!(decisions, ContingencyFilterDecision(entry.contingency.id,
                entry.device_kind, entry.device_id, :exact, :predicted_apparent_risk, prediction.apparent))
        elseif ac_risk_guard && prediction.voltage_change >= max(0.0,minimum_voltage_margin-voltage_guard)
            push!(decisions, ContingencyFilterDecision(entry.contingency.id,
                entry.device_kind, entry.device_id, :exact, :voltage_redistribution_guard, prediction.active))
        else
            response = droop_response_guard && !isempty(case.controls) ?
                _droop_screening_diagnostics(case,base_state,entry.contingency;
                    participation,voltage_guard,loading_threshold,reactive_guard) : nothing
            if !isnothing(response) && !response.safe
                push!(decisions,ContingencyFilterDecision(entry.contingency.id,
                    entry.device_kind,entry.device_id,:exact,response.reason,prediction.active))
            else
                push!(decisions, ContingencyFilterDecision(entry.contingency.id,
                    entry.device_kind, entry.device_id, :screened, :below_loading_threshold, prediction.active))
            end
        end
    end
    return decisions
end
