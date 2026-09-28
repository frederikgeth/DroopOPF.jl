struct RegulatedLocation
    kind::Symbol
    bus_id::Int
    side::Union{Nothing,Symbol}
    branch_id::Union{Nothing,Int}

    function RegulatedLocation(
        kind::Symbol,
        bus_id::Integer;
        side::Union{Nothing,Symbol} = nothing,
        branch_id::Union{Nothing,Integer} = nothing,
    )
        kind in (:generator_terminal, :bus, :branch_terminal, :remote_bus) ||
            throw(ArgumentError("unsupported regulated-location kind: $kind"))
        bus_id > 0 || throw(ArgumentError("regulated-location bus_id must be positive"))
        if kind == :branch_terminal
            side in (:from, :to) ||
                throw(ArgumentError("branch-terminal locations require side=:from or :to"))
            !isnothing(branch_id) && branch_id > 0 ||
                throw(ArgumentError("branch-terminal locations require a positive branch_id"))
        elseif !isnothing(side) || !isnothing(branch_id)
            throw(ArgumentError("side and branch_id are only valid for branch-terminal locations"))
        end
        new(kind, Int(bus_id), side, isnothing(branch_id) ? nothing : Int(branch_id))
    end
end

"""Declared reactive-control semantics for one generator.

These modes are deliberately independent of their numerical encoding. `AVR`
may later be represented by a smooth transition or exact complementarity
without changing the physical assignment.
"""
abstract type ReactiveControlMode end

"""Generator Q is bounded only by its declared capability."""
struct FreeQ <: ReactiveControlMode end

"""Generator Q is fixed to an explicit schedule."""
struct FixedQ{T<:Real} <: ReactiveControlMode
    q_schedule::T
    function FixedQ{T}(q_schedule::T) where {T<:Real}
        isfinite(q_schedule) || throw(ArgumentError("fixed-Q schedule must be finite"))
        new{T}(q_schedule)
    end
end

FixedQ(q_schedule::T) where {T<:Real} = FixedQ{T}(q_schedule)

"""Automatic voltage regulation with generator Q limits supplied by the case."""
struct AVR{T<:Real} <: ReactiveControlMode
    voltage_setpoint::T
    function AVR{T}(voltage_setpoint::T) where {T<:Real}
        isfinite(voltage_setpoint) && voltage_setpoint > zero(T) ||
            throw(ArgumentError("AVR voltage setpoint must be finite and positive"))
        new{T}(voltage_setpoint)
    end
end


AVR(voltage_setpoint::T) where {T<:Real} = AVR{T}(voltage_setpoint)

struct VoltageSchedule{T<:Real}
    v_ref::T
    v_db_low::T
    v_db_high::T
    unit::Symbol

    function VoltageSchedule{T}(
        v_ref::T,
        v_db_low::T,
        v_db_high::T,
        unit::Symbol,
    ) where {T<:Real}
        unit == :pu || throw(ArgumentError("M1 voltage schedules must use unit=:pu"))
        all(isfinite, (v_ref, v_db_low, v_db_high)) ||
            throw(ArgumentError("voltage schedule values must be finite"))
        v_ref > zero(T) || throw(ArgumentError("v_ref must be positive"))
        v_db_low <= v_ref <= v_db_high ||
            throw(ArgumentError("deadband must contain v_ref"))
        new{T}(v_ref, v_db_low, v_db_high, unit)
    end
end

function VoltageSchedule(
    v_ref::T;
    v_db_low::T = v_ref,
    v_db_high::T = v_ref,
    unit::Symbol = :pu,
) where {T<:Real}
    return VoltageSchedule{T}(v_ref, v_db_low, v_db_high, unit)
end

struct ReactiveCapability{T<:Real}
    p_min::T
    p_max::T
    q_min::T
    q_max::T

    function ReactiveCapability{T}(
        p_min::T,
        p_max::T,
        q_min::T,
        q_max::T,
    ) where {T<:Real}
        all(isfinite, (p_min, p_max, q_min, q_max)) ||
            throw(ArgumentError("capability limits must be finite"))
        p_min <= p_max || throw(ArgumentError("p_min must not exceed p_max"))
        q_min < q_max || throw(ArgumentError("q_min must be less than q_max"))
        new{T}(p_min, p_max, q_min, q_max)
    end
end

function ReactiveCapability(; p_min, p_max, q_min, q_max)
    T = promote_type(typeof(p_min), typeof(p_max), typeof(q_min), typeof(q_max))
    return ReactiveCapability{T}(T(p_min), T(p_max), T(q_min), T(q_max))
end

function q_limits(capability::ReactiveCapability, p::Real)
    capability.p_min <= p <= capability.p_max ||
        throw(DomainError(p, "active power is outside generator capability"))
    return capability.q_min, capability.q_max
end

"""A static volt-var droop with exact PWL semantics and constant Q capability."""
struct VoltVarDroop{T<:Real} <: ReactiveControlMode
    schedule::VoltageSchedule{T}
    slope::T
    q_at_deadband::T
    capability::ReactiveCapability{T}
    curve::PiecewiseLinearCurve{T}

    function VoltVarDroop{T}(
        schedule::VoltageSchedule{T},
        slope::T,
        q_at_deadband::T,
        capability::ReactiveCapability{T},
    ) where {T<:Real}
        isfinite(slope) && slope > zero(T) ||
            throw(ArgumentError("volt-var slope must be finite and positive"))
        isfinite(q_at_deadband) ||
            throw(ArgumentError("q_at_deadband must be finite"))
        q_min, q_max = capability.q_min, capability.q_max
        q_min <= q_at_deadband <= q_max ||
            throw(ArgumentError("q_at_deadband must lie within reactive capability"))

        # slope is ΔV / ΔQ in pu voltage per unit reactive output.
        v_at_qmax = schedule.v_db_low - slope * (q_max - q_at_deadband)
        v_at_qmin = schedule.v_db_high + slope * (q_at_deadband - q_min)
        v_at_qmax < schedule.v_db_low < schedule.v_db_high < v_at_qmin ||
            throw(ArgumentError("droop and deadband must produce ordered curve breakpoints"))

        curve = PiecewiseLinearCurve(
            [v_at_qmax, schedule.v_db_low, schedule.v_db_high, v_at_qmin],
            [q_max, q_at_deadband, q_at_deadband, q_min];
            extrapolation = :clamp,
        )
        new{T}(schedule, slope, q_at_deadband, capability, curve)
    end
end

"""Preferred name for the reactive-power reference inside the voltage deadband."""
q_ref(control::VoltVarDroop) = control.q_at_deadband

function VoltVarDroop(
    schedule::VoltageSchedule{T},
    slope::T,
    capability::ReactiveCapability{T};
    q_ref::T,
) where {T<:Real}
    VoltVarDroop(schedule, slope, q_ref, capability)
end

"""Attach one explicit reactive-control mode to a generator.

`FreeQ` and `FixedQ` act at the generator and therefore take no regulated
location. `AVR` and `VoltVarDroop` require a declared voltage location.
"""
struct ReactiveControlAssignment{M<:ReactiveControlMode}
    generator_id::Int
    mode::M
    location::Union{Nothing,RegulatedLocation}
    function ReactiveControlAssignment(
        generator_id::Integer,
        mode::M,
        location::Union{Nothing,RegulatedLocation}=nothing,
    ) where {M<:ReactiveControlMode}
        generator_id > 0 || throw(ArgumentError("generator_id must be positive"))
        needs_location = mode isa AVR || mode isa VoltVarDroop
        needs_location == !isnothing(location) || throw(ArgumentError(
            needs_location ? "$(nameof(typeof(mode))) requires a regulated location" :
                "$(nameof(typeof(mode))) must not declare a regulated location"))
        new{M}(Int(generator_id), mode, location)
    end
end

function VoltVarDroop(
    schedule::VoltageSchedule{T},
    slope::T,
    q_at_deadband::T,
    capability::ReactiveCapability{T},
) where {T<:Real}
    return VoltVarDroop{T}(schedule, slope, q_at_deadband, capability)
end

droop_curve(control::VoltVarDroop) = control.curve

function droop_response(control::VoltVarDroop, voltage::Real; p::Real)
    q_min, q_max = q_limits(control.capability, p)
    q = evaluate(control.curve, voltage)
    return clamp(q, q_min, q_max)
end
