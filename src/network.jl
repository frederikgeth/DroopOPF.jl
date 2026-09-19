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

"""Two-terminal branch with a from-side complex tap `tap_ratio * cis(phase_shift)`.
The ratio is positive and dimensionless; phase shift is in radians. Defaults
preserve line behavior. Ratio and phase are fixed equipment inputs in M5.
"""
struct Branch{T<:Real}
    id::Int
    from_bus::Int
    to_bus::Int
    resistance::T
    reactance::T
    charging::T
    thermal_limit::T
    available::Bool
    tap_ratio::T
    phase_shift::T

    function Branch{T}(
        id::Integer,
        from_bus::Integer,
        to_bus::Integer,
        resistance::T,
        reactance::T,
        charging::T,
        thermal_limit::T,
        available::Bool,
        tap_ratio::T = one(T),
        phase_shift::T = zero(T),
    ) where {T<:Real}
        id > 0 || throw(ArgumentError("branch id must be positive"))
        from_bus > 0 || throw(ArgumentError("branch from_bus must be positive"))
        to_bus > 0 || throw(ArgumentError("branch to_bus must be positive"))
        from_bus != to_bus || throw(ArgumentError("a branch cannot connect a bus to itself"))
        all(isfinite, (resistance, reactance, charging, thermal_limit, tap_ratio, phase_shift)) ||
            throw(ArgumentError("branch parameters must be finite"))
        resistance >= zero(T) || throw(ArgumentError("branch resistance must be nonnegative"))
        !iszero(resistance) || !iszero(reactance) ||
            throw(ArgumentError("branch impedance cannot be zero"))
        thermal_limit > zero(T) || throw(ArgumentError("branch thermal_limit must be positive"))
        tap_ratio > zero(T) || throw(ArgumentError("branch tap_ratio must be positive"))
        new{T}(Int(id), Int(from_bus), Int(to_bus), resistance, reactance, charging, thermal_limit, available, tap_ratio, phase_shift)
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
    tap_ratio = 1,
    phase_shift = 0,
)
    T = promote_type(typeof(resistance), typeof(reactance), typeof(charging), typeof(thermal_limit), typeof(tap_ratio), typeof(phase_shift))
    return Branch{T}(
        id, from_bus, to_bus, T(resistance), T(reactance), T(charging), T(thermal_limit), available, T(tap_ratio), T(phase_shift),
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

"""Fixed bus admittance in per unit: G >= 0 consumes P; B > 0 injects Q.
Terminal consumption is `(conductance - im*susceptance)*abs2(V)`. Availability
disables the equipment without losing its supplied parameters. This is not a
switched-bank model; no legal positions or controls are inferred.
"""
struct FixedShunt{T<:Real}
    id::Int
    bus_id::Int
    conductance::T
    susceptance::T
    available::Bool
    function FixedShunt{T}(id::Integer, bus_id::Integer, conductance::T,
                           susceptance::T, available::Bool) where {T<:Real}
        id > 0 && bus_id > 0 || throw(ArgumentError("shunt and bus IDs must be positive"))
        all(isfinite, (conductance, susceptance)) ||
            throw(ArgumentError("shunt admittance must be finite"))
        conductance >= zero(T) || throw(ArgumentError("shunt conductance must be nonnegative"))
        new{T}(Int(id), Int(bus_id), conductance, susceptance, available)
    end
end

function FixedShunt(id::Integer, bus_id::Integer; conductance=0.0, susceptance,
                    available::Bool=true)
    T = promote_type(typeof(conductance), typeof(susceptance))
    return FixedShunt{T}(id, bus_id, T(conductance), T(susceptance), available)
end

"""Shunt bank with explicitly supplied legal step-count combinations.
Step admittances use the fixed-shunt G/B convention. State and nominal_state are
integer count tuples, not optimization variables. Metadata is copied to immutable
tuples; unavailable banks retain their legal state but contribute zero admittance.
"""
struct ShuntBank{T<:Real}
    id::Int
    bus_id::Int
    step_conductances::Tuple{Vararg{T}}
    step_susceptances::Tuple{Vararg{T}}
    legal_states::Tuple{Vararg{Tuple{Vararg{Int}}}}
    state::Tuple{Vararg{Int}}
    nominal_state::Tuple{Vararg{Int}}
    available::Bool
    function ShuntBank{T}(id::Integer,bus_id::Integer,gs,bs,legal,state,nominal,
                          available::Bool) where {T<:Real}
        id > 0 && bus_id > 0 || throw(ArgumentError("bank and bus IDs must be positive"))
        length(gs) == length(bs) > 0 || throw(ArgumentError("bank steps must have matching nonempty G/B arrays"))
        g,b = Tuple(T.(gs)),Tuple(T.(bs))
        all(isfinite,g) && all(isfinite,b) && all(>=(zero(T)),g) ||
            throw(ArgumentError("bank admittances must be finite with nonnegative conductances"))
        function counts(xs)
            length(xs) == length(g) && all(x -> x isa Integer && x >= 0,xs) ||
                throw(ArgumentError("bank states require one nonnegative integer count per step"))
            return Tuple(Int.(xs))
        end
        ls = Tuple(counts(x) for x in legal)
        !isempty(ls) && length(unique(ls)) == length(ls) ||
            throw(ArgumentError("bank legal states must be nonempty and unique"))
        st,nom = counts(state),counts(nominal)
        st in ls && nom in ls || throw(ArgumentError("current and nominal bank states must be legal"))
        new{T}(Int(id),Int(bus_id),g,b,ls,st,nom,available)
    end
end

function ShuntBank(id::Integer,bus_id::Integer; step_susceptances,
    step_conductances=zeros(length(step_susceptances)),legal_states,state,
    nominal_state=state,available::Bool=true)
    T = promote_type(Float64, map(typeof,step_conductances)..., map(typeof,step_susceptances)...)
    return ShuntBank{T}(id,bus_id,step_conductances,step_susceptances,legal_states,
        state,nominal_state,available)
end

"""Copy a bank with a supplied legal state/availability, leaving its design intact."""
function with_bank_state(bank::ShuntBank{T},state;available::Bool=bank.available) where {T}
    ShuntBank{T}(bank.id,bank.bus_id,bank.step_conductances,bank.step_susceptances,
        bank.legal_states,state,bank.nominal_state,available)
end

"""Aggregate admittance at the supplied bank state; zero when unavailable."""
function bank_admittance(bank::ShuntBank{T}) where {T}
    bank.available || return zero(Complex{T})
    return sum(bank.state[k]*complex(bank.step_conductances[k],bank.step_susceptances[k])
        for k in eachindex(bank.state))
end

struct ACNetwork{T<:Real}
    buses::Vector{Bus{T}}
    branches::Vector{Branch{T}}
    shunts::Vector{FixedShunt{T}}
    banks::Vector{ShuntBank{T}}

    function ACNetwork{T}(buses::Vector{Bus{T}}, branches::Vector{Branch{T}},
                          shunts::Vector{FixedShunt{T}}=FixedShunt{T}[],
                          banks::Vector{ShuntBank{T}}=ShuntBank{T}[]) where {T<:Real}
        length(unique(b.id for b in buses)) == length(buses) ||
            throw(ArgumentError("bus ids must be unique"))
        length(unique(br.id for br in branches)) == length(branches) ||
            throw(ArgumentError("branch ids must be unique"))
        bus_ids = Set(b.id for b in buses)
        all(br.from_bus in bus_ids && br.to_bus in bus_ids for br in branches) ||
            throw(ArgumentError("branch references an unknown bus"))
        count(b -> b.reference, buses) <= 1 ||
            throw(ArgumentError("an AC network can have at most one reference bus in M1"))
        length(unique(s.id for s in shunts)) == length(shunts) ||
            throw(ArgumentError("shunt IDs must be unique"))
        all(s.bus_id in bus_ids for s in shunts) ||
            throw(ArgumentError("shunt references an unknown bus"))
        ids = [s.id for s in shunts] # fixed and bank IDs share a shunt namespace
        append!(ids, (b.id for b in banks))
        length(unique(ids)) == length(ids) || throw(ArgumentError("fixed-shunt and bank IDs must be unique"))
        all(b.bus_id in bus_ids for b in banks) || throw(ArgumentError("bank references an unknown bus"))
        new{T}(copy(buses), copy(branches), copy(shunts), copy(banks))
    end
end

function ACNetwork(
    buses::AbstractVector{<:Bus},
    branches::AbstractVector{<:Branch};
    shunts::AbstractVector{<:FixedShunt}=FixedShunt[],
    banks::AbstractVector{<:ShuntBank}=ShuntBank[],
)
    numbers = Any[]
    append!(numbers, (typeof(b.v_min) for b in buses))
    append!(numbers, (typeof(br.resistance) for br in branches))
    append!(numbers, (typeof(s.conductance) for s in shunts))
    append!(numbers, (typeof(first(b.step_conductances)) for b in banks))
    T = isempty(numbers) ? Float64 : promote_type(numbers...)
    bs = Bus{T}[Bus{T}(b.id, T(b.v_min), T(b.v_max), b.reference) for b in buses]
    brs = Branch{T}[
        Branch{T}(br.id, br.from_bus, br.to_bus, T(br.resistance), T(br.reactance),
                  T(br.charging), T(br.thermal_limit), br.available, T(br.tap_ratio), T(br.phase_shift)) for br in branches
    ]
    ss = FixedShunt{T}[FixedShunt{T}(s.id, s.bus_id, T(s.conductance),
        T(s.susceptance), s.available) for s in shunts]
    bank_data = ShuntBank{T}[ShuntBank{T}(b.id,b.bus_id,b.step_conductances,
        b.step_susceptances,b.legal_states,b.state,b.nominal_state,b.available) for b in banks]
    return ACNetwork{T}(bs, brs, ss, bank_data)
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
