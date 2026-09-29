"""A named outage overlay. Device IDs refer to the original case; `:base` is reserved."""
struct Contingency
    id::Symbol
    generator_ids::Vector{Int}
    branch_ids::Vector{Int}
    function Contingency(id::Symbol; generator_ids = Int[], branch_ids = Int[])
        id != :base && !isempty(string(id)) || throw(ArgumentError("invalid contingency id"))
        gs, bs = Int.(generator_ids), Int.(branch_ids)
        !isempty(gs) || !isempty(bs) || throw(ArgumentError("contingency must contain an outage"))
        all(>(0), gs) && all(>(0), bs) || throw(ArgumentError("outage IDs must be positive"))
        length(unique(gs)) == length(gs) && length(unique(bs)) == length(bs) ||
            throw(ArgumentError("duplicate outage IDs"))
        new(id, copy(gs), copy(bs))
    end
end

function _check_connected(case::Case)
    isnothing(case.network) && throw(ArgumentError("SCOPF requires an AC network"))
    net = case.network
    isempty(net.buses) && throw(ArgumentError("SCOPF requires at least one bus"))
    count(b -> b.reference, net.buses) == 1 ||
        throw(ArgumentError("SCOPF requires exactly one reference bus"))
    visited = Set([first(net.buses).id])
    while true
        before = length(visited)
        for br in net.branches
            br.available || continue
            if br.from_bus in visited || br.to_bus in visited
                push!(visited, br.from_bus, br.to_bus)
            end
        end
        before == length(visited) && break
    end
    length(visited) == length(net.buses) ||
        throw(ArgumentError("islanding is unsupported in scenario $(case.id)"))
    return true
end

"""Apply outages without changing the case, device order, or control settings."""
function scenario_case(case::Case{T}, contingency::Contingency) where {T}
    isnothing(case.network) && throw(ArgumentError("SCOPF requires an AC network"))
    for id in contingency.generator_ids
        any(g -> g.id == id && g.available, case.generators) ||
            throw(ArgumentError("unknown or already unavailable generator $id"))
    end
    for id in contingency.branch_ids
        any(b -> b.id == id && b.available, case.network.branches) ||
            throw(ArgumentError("unknown or already unavailable branch $id"))
    end
    generators = [Generator{T}(g.id, g.bus_id,
        g.available && !(g.id in contingency.generator_ids), g.p_min, g.p_max,
        g.q_min, g.q_max, g.initial_p, g.initial_q) for g in case.generators]
    branches = [Branch{T}(b.id, b.from_bus, b.to_bus, b.resistance, b.reactance,
        b.charging, b.thermal_limit, b.available && !(b.id in contingency.branch_ids),
        b.tap_ratio, b.phase_shift)
        for b in case.network.branches]
    overlay = Case{T}(case.id * "/" * string(contingency.id), case.base_power,
        case.base_frequency, ACNetwork(case.network.buses, branches; shunts=case.network.shunts, banks=case.network.banks), case.loads,
        generators, case.controls, case.attachments)
    _check_connected(overlay)
    return overlay
end

"""
    SCOPFControlPolicy(; taps=:preventive, shunts=:preventive, reactive=:automatic,
        tap_movement_limits=nothing, shunt_movement_limits=nothing)

Declare cross-scenario timing. Preventive equipment has one shared setting;
corrective equipment may select a bounded setting per scenario. Reactive
assignments and voltage targets remain shared, while Q and voltage respond
automatically to each scenario's equations and availability.
"""
struct SCOPFControlPolicy
    taps::Symbol
    shunts::Symbol
    reactive::Symbol
    tap_movement_limits::Union{Nothing,Dict{Int,Float64}}
    shunt_movement_limits::Union{Nothing,Dict{Int,Float64}}
    function SCOPFControlPolicy(; taps::Symbol=:preventive,
        shunts::Symbol=:preventive, reactive::Symbol=:automatic,
        tap_movement_limits::Union{Nothing,AbstractDict}=nothing,
        shunt_movement_limits::Union{Nothing,AbstractDict}=nothing)
        taps in (:preventive, :corrective) ||
            throw(ArgumentError("tap timing must be :preventive or :corrective"))
        shunts in (:preventive, :corrective) ||
            throw(ArgumentError("shunt timing must be :preventive or :corrective"))
        reactive == :automatic ||
            throw(ArgumentError("reactive timing currently requires :automatic"))
        tap_limits = isnothing(tap_movement_limits) ? nothing :
            Dict{Int,Float64}(tap_movement_limits)
        shunt_limits = isnothing(shunt_movement_limits) ? nothing :
            Dict{Int,Float64}(shunt_movement_limits)
        for (timing, limits, label) in ((taps, tap_limits, "tap"),
            (shunts, shunt_limits, "shunt"))
            isnothing(limits) && continue
            timing == :corrective ||
                throw(ArgumentError("$label movement limits require corrective timing"))
            all(>(0), keys(limits)) ||
                throw(ArgumentError("$label movement-limit IDs must be positive"))
            all(x -> isfinite(x) && x >= 0, values(limits)) ||
                throw(ArgumentError("$label movement limits must be finite and nonnegative"))
        end
        new(taps, shunts, reactive, tap_limits, shunt_limits)
    end
end

Base.:(==)(a::SCOPFControlPolicy, b::SCOPFControlPolicy) =
    a.taps == b.taps && a.shunts == b.shunts && a.reactive == b.reactive &&
    a.tap_movement_limits == b.tap_movement_limits &&
    a.shunt_movement_limits == b.shunt_movement_limits

"""
    Study(case; contingencies=[], mode=:preventive, participation=Dict(), redispatch_limits=Dict(),
          tap_controls=[], shunt_controls=[], control_policy=SCOPFControlPolicy())

Fixed-curve SCOPF study. Preventive response is `P[c,g] = P[base,g] + α[c,g] Δ[c]`:
nonnegative participation weights are normalized over surviving generators.
`Δ` balances the outage and changed AC losses; it is power in p.u., not frequency.
Corrective response permits `abs(P[c,g] - P[base,g]) <= redispatch_limits[g]`.
Missing limits mean zero redispatch. Limits also optionally cap preventive response.
All powers use the case per-unit base. Generator capability limits apply in every
scenario. Outaged generators have zero P/Q and no active droop equation.
"""
struct Study{T<:Real}
    case::Case{T}
    reactive_assignments::Union{Nothing,Vector{ReactiveControlAssignment}}
    contingencies::Vector{Contingency}
    mode::Symbol
    participation::Dict{Int,Float64}
    redispatch_limits::Dict{Int,Float64}
    tap_controls::Vector{TapControl}
    shunt_controls::Vector{ShuntControl}
    control_policy::SCOPFControlPolicy
    function Study(case::Case{T}; contingencies = Contingency[], mode::Symbol = :preventive,
                   participation::AbstractDict = Dict{Int,Float64}(),
                   redispatch_limits::AbstractDict = Dict{Int,Float64}(),
                   reactive_assignments = nothing,
                   tap_controls::AbstractVector{<:TapControl}=TapControl[],
                   shunt_controls::AbstractVector{<:ShuntControl}=ShuntControl[],
                   control_policy::SCOPFControlPolicy=SCOPFControlPolicy()) where {T}
        mode in (:preventive, :corrective) || throw(ArgumentError("unknown SCOPF mode"))
        cs = Contingency[contingencies...]
        length(unique(c.id for c in cs)) == length(cs) ||
            throw(ArgumentError("contingency IDs must be unique"))
        weights = Dict{Int,Float64}(participation)
        limits = Dict{Int,Float64}(redispatch_limits)
        available = Set(g.id for g in case.generators if g.available)
        for values in (weights, limits)
            all(id in available for id in keys(values)) ||
                throw(ArgumentError("response policy references unknown or unavailable generators"))
            all(x -> isfinite(x) && x >= 0, Base.values(values)) ||
                throw(ArgumentError("response policy values must be finite and nonnegative"))
        end
        mode == :corrective && !isempty(weights) &&
            throw(ArgumentError("participation weights only apply to preventive mode"))
        validate_case(case)
        assignments = isnothing(reactive_assignments) ? nothing :
            ReactiveControlAssignment[reactive_assignments...]
        isnothing(assignments) || validate_reactive_assignments(case, assignments)
        taps = TapControl[tap_controls...]
        shunts = ShuntControl[shunt_controls...]
        _check_tap_controls(case, taps)
        _check_shunt_controls(case, shunts)
        isnothing(control_policy.tap_movement_limits) ||
            all(id in Set(c.branch_id for c in taps) for id in keys(control_policy.tap_movement_limits)) ||
            throw(ArgumentError("tap movement limit references an unselected control"))
        isnothing(control_policy.shunt_movement_limits) ||
            all(id in Set(c.bank_id for c in shunts) for id in keys(control_policy.shunt_movement_limits)) ||
            throw(ArgumentError("shunt movement limit references an unselected control"))
        _check_connected(case)
        for c in cs
            overlay = scenario_case(case, c)
            if mode == :preventive
                total = sum(get(weights, g.id, 0.0) for g in overlay.generators if g.available; init=0.0)
                isfinite(total) && total > 0 ||
                    throw(ArgumentError("scenario $(c.id) needs a surviving active-power participant"))
            end
        end
        new{T}(case, assignments, copy(cs), mode, weights, limits,
            taps, shunts, control_policy)
    end
end

function _participation(study::Study, case::Case)
    weights = [g.available ? get(study.participation, g.id, 0.0) : 0.0 for g in case.generators]
    return weights ./ sum(weights)
end

# Recheck mutable vectors/dictionaries when a study is used.
function _validated_study(study::Study)
    return Study(study.case; contingencies=study.contingencies, mode=study.mode,
        participation=study.participation, redispatch_limits=study.redispatch_limits,
        reactive_assignments=study.reactive_assignments,
        tap_controls=study.tap_controls, shunt_controls=study.shunt_controls,
        control_policy=study.control_policy)
end
