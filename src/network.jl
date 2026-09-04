using LinearAlgebra

struct Bus{T<:Real}
    id::Int
    v_min::T
    v_max::T
    reference::Bool

    function Bus{T}(id::Integer, v_min::T, v_max::T, reference::Bool) where {T<:Real}
        id > 0 || throw(ArgumentError("bus id must be positive"))
        all(isfinite, (v_min, v_max)) || throw(ArgumentError("bus voltage limits must be finite"))
        zero(T) < v_min <= v_max || throw(ArgumentError("invalid bus voltage limits"))
        new{T}(Int(id), v_min, v_max, reference)
    end
end

function Bus(id::Integer; v_min = 0.9, v_max = 1.1, reference::Bool = false)
    T = promote_type(typeof(v_min), typeof(v_max))
    return Bus{T}(id, T(v_min), T(v_max), reference)
end

struct Branch{T<:Real}
    id::Int
    from_bus::Int
    to_bus::Int
    resistance::T
    reactance::T
    charging::T
    thermal_limit::T
    available::Bool

    function Branch{T}(
        id::Integer,
        from_bus::Integer,
        to_bus::Integer,
        resistance::T,
        reactance::T,
        charging::T,
        thermal_limit::T,
        available::Bool,
    ) where {T<:Real}
        id > 0 || throw(ArgumentError("branch id must be positive"))
        from_bus > 0 || throw(ArgumentError("branch from_bus must be positive"))
        to_bus > 0 || throw(ArgumentError("branch to_bus must be positive"))
        from_bus != to_bus || throw(ArgumentError("a branch cannot connect a bus to itself"))
        all(isfinite, (resistance, reactance, charging, thermal_limit)) ||
            throw(ArgumentError("branch parameters must be finite"))
        resistance >= zero(T) || throw(ArgumentError("branch resistance must be nonnegative"))
        !iszero(resistance) || !iszero(reactance) ||
            throw(ArgumentError("branch impedance cannot be zero"))
        thermal_limit > zero(T) || throw(ArgumentError("branch thermal_limit must be positive"))
        new{T}(Int(id), Int(from_bus), Int(to_bus), resistance, reactance, charging, thermal_limit, available)
    end
end

function Branch(
    id::Integer,
    from_bus::Integer,
    to_bus::Integer;
    resistance,
    reactance,
    charging = 0.0,
    thermal_limit,
    available::Bool = true,
)
    T = promote_type(typeof(resistance), typeof(reactance), typeof(charging), typeof(thermal_limit))
    return Branch{T}(
        id, from_bus, to_bus, T(resistance), T(reactance), T(charging), T(thermal_limit), available,
    )
end

struct Load{T<:Real}
    id::Int
    bus_id::Int
    p::T
    q::T

    function Load{T}(id::Integer, bus_id::Integer, p::T, q::T) where {T<:Real}
        id > 0 || throw(ArgumentError("load id must be positive"))
        bus_id > 0 || throw(ArgumentError("load bus_id must be positive"))
        all(isfinite, (p, q)) || throw(ArgumentError("load values must be finite"))
        new{T}(Int(id), Int(bus_id), p, q)
    end
end

function Load(id::Integer, bus_id::Integer; p, q)
    T = promote_type(typeof(p), typeof(q))
    return Load{T}(id, bus_id, T(p), T(q))
end

struct ACNetwork{T<:Real}
    buses::Vector{Bus{T}}
    branches::Vector{Branch{T}}

    function ACNetwork{T}(buses::Vector{Bus{T}}, branches::Vector{Branch{T}}) where {T<:Real}
        length(unique(b.id for b in buses)) == length(buses) ||
            throw(ArgumentError("bus ids must be unique"))
        length(unique(br.id for br in branches)) == length(branches) ||
            throw(ArgumentError("branch ids must be unique"))
        bus_ids = Set(b.id for b in buses)
        all(br.from_bus in bus_ids && br.to_bus in bus_ids for br in branches) ||
            throw(ArgumentError("branch references an unknown bus"))
        count(b -> b.reference, buses) <= 1 ||
            throw(ArgumentError("an AC network can have at most one reference bus in M1"))
        new{T}(copy(buses), copy(branches))
    end
end

function ACNetwork(
    buses::AbstractVector{<:Bus},
    branches::AbstractVector{<:Branch},
)
    numbers = Any[]
    append!(numbers, (typeof(b.v_min) for b in buses))
    append!(numbers, (typeof(br.resistance) for br in branches))
    T = isempty(numbers) ? Float64 : promote_type(numbers...)
    bs = Bus{T}[Bus{T}(b.id, T(b.v_min), T(b.v_max), b.reference) for b in buses]
    brs = Branch{T}[
        Branch{T}(br.id, br.from_bus, br.to_bus, T(br.resistance), T(br.reactance),
                  T(br.charging), T(br.thermal_limit), br.available) for br in branches
    ]
    return ACNetwork{T}(bs, brs)
end

struct ACState{T<:Real}
    vm::Vector{T}
    va::Vector{T}
    pg::Vector{T}
    qg::Vector{T}

    function ACState{T}(
        vm::Vector{T}, va::Vector{T}, pg::Vector{T}, qg::Vector{T},
    ) where {T<:Real}
        length(vm) == length(va) || throw(ArgumentError("vm and va must have the same length"))
        length(pg) == length(qg) || throw(ArgumentError("pg and qg must have the same length"))
        all(isfinite, vm) && all(isfinite, va) && all(isfinite, pg) && all(isfinite, qg) ||
            throw(ArgumentError("AC state values must be finite"))
        all(vm .> zero(T)) || throw(ArgumentError("voltage magnitudes must be positive"))
        new{T}(copy(vm), copy(va), copy(pg), copy(qg))
    end
end

function ACState(vm::AbstractVector{T}, va::AbstractVector{T}, pg::AbstractVector, qg::AbstractVector) where {T<:Real}
    S = promote_type(T, eltype(pg), eltype(qg))
    return ACState{S}(S.(vm), S.(va), S.(pg), S.(qg))
end
