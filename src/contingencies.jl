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
        b.charging, b.thermal_limit, b.available && !(b.id in contingency.branch_ids))
        for b in case.network.branches]
    overlay = Case{T}(case.id * "/" * string(contingency.id), case.base_power,
        case.base_frequency, ACNetwork(case.network.buses, branches), case.loads,
        generators, case.controls, case.attachments)
    _check_connected(overlay)
    return overlay
end

"""
    Study(case; contingencies=[], mode=:preventive, participation=Dict(), redispatch_limits=Dict())

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
    contingencies::Vector{Contingency}
    mode::Symbol
    participation::Dict{Int,Float64}
    redispatch_limits::Dict{Int,Float64}
    function Study(case::Case{T}; contingencies = Contingency[], mode::Symbol = :preventive,
                   participation::AbstractDict = Dict{Int,Float64}(),
                   redispatch_limits::AbstractDict = Dict{Int,Float64}()) where {T}
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
        _check_connected(case)
        for c in cs
            overlay = scenario_case(case, c)
            if mode == :preventive
                total = sum(get(weights, g.id, 0.0) for g in overlay.generators if g.available; init=0.0)
                isfinite(total) && total > 0 ||
                    throw(ArgumentError("scenario $(c.id) needs a surviving active-power participant"))
            end
        end
        new{T}(case, copy(cs), mode, weights, limits)
    end
end

function _participation(study::Study, case::Case)
    weights = [g.available ? get(study.participation, g.id, 0.0) : 0.0 for g in case.generators]
    return weights ./ sum(weights)
end

# Recheck mutable vectors/dictionaries when a study is used.
function _validated_study(study::Study)
    return Study(study.case; contingencies=study.contingencies, mode=study.mode,
        participation=study.participation, redispatch_limits=study.redispatch_limits)
end
