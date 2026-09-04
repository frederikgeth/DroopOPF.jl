struct Generator{T<:Real}
    id::Int
    bus_id::Int
    available::Bool
    p_min::T
    p_max::T
    q_min::T
    q_max::T
    initial_p::T
    initial_q::T

    function Generator{T}(
        id::Integer,
        bus_id::Integer,
        available::Bool,
        p_min::T,
        p_max::T,
        q_min::T,
        q_max::T,
        initial_p::T,
        initial_q::T,
    ) where {T<:Real}
        id > 0 || throw(ArgumentError("generator id must be positive"))
        bus_id > 0 || throw(ArgumentError("generator bus_id must be positive"))
        all(isfinite, (p_min, p_max, q_min, q_max, initial_p, initial_q)) ||
            throw(ArgumentError("generator values must be finite"))
        p_min <= initial_p <= p_max ||
            throw(ArgumentError("initial_p must lie within active-power limits"))
        q_min <= initial_q <= q_max ||
            throw(ArgumentError("initial_q must lie within reactive-power limits"))
        p_min <= p_max || throw(ArgumentError("p_min must not exceed p_max"))
        q_min < q_max || throw(ArgumentError("q_min must be less than q_max"))
        new{T}(Int(id), Int(bus_id), available, p_min, p_max, q_min, q_max, initial_p, initial_q)
    end
end

function Generator(
    id::Integer,
    bus_id::Integer;
    available::Bool = true,
    p_min,
    p_max,
    q_min,
    q_max,
    initial_p = p_min,
    initial_q = zero(promote_type(typeof(q_min), typeof(q_max))),
)
    T = promote_type(
        typeof(p_min), typeof(p_max), typeof(q_min), typeof(q_max),
        typeof(initial_p), typeof(initial_q),
    )
    return Generator{T}(
        id,
        bus_id,
        available,
        T(p_min),
        T(p_max),
        T(q_min),
        T(q_max),
        T(initial_p),
        T(initial_q),
    )
end

struct GeneratorControlAttachment
    generator_id::Int
    control_id::Int
    location::RegulatedLocation
    priority::Symbol

    function GeneratorControlAttachment(
        generator_id::Integer,
        control_id::Integer,
        location::RegulatedLocation;
        priority::Symbol = :unit,
    )
        generator_id > 0 || throw(ArgumentError("generator_id must be positive"))
        control_id > 0 || throw(ArgumentError("control_id must be positive"))
        priority in (:unit, :plant, :system) ||
            throw(ArgumentError("priority must be :unit, :plant, or :system"))
        new(Int(generator_id), Int(control_id), location, priority)
    end
end

struct Case{T<:Real}
    id::String
    base_power::T
    base_frequency::T
    generators::Vector{Generator{T}}
    controls::Vector{VoltVarDroop{T}}
    attachments::Vector{GeneratorControlAttachment}

    function Case{T}(
        id::AbstractString,
        base_power::T,
        base_frequency::T,
        generators::Vector{Generator{T}},
        controls::Vector{VoltVarDroop{T}},
        attachments::Vector{GeneratorControlAttachment},
    ) where {T<:Real}
        isempty(strip(id)) && throw(ArgumentError("case id must not be empty"))
        base_power > zero(T) || throw(ArgumentError("base_power must be positive"))
        base_frequency > zero(T) || throw(ArgumentError("base_frequency must be positive"))
        length(unique(g.id for g in generators)) == length(generators) ||
            throw(ArgumentError("generator ids must be unique"))
        length(unique(a.control_id for a in attachments)) == length(attachments) ||
            throw(ArgumentError("each control may have at most one attachment in M1"))
        generator_ids = Set(g.id for g in generators)
        control_ids = Set(eachindex(controls))
        all(a.generator_id in generator_ids for a in attachments) ||
            throw(ArgumentError("control attachment references an unknown generator"))
        all(a.control_id in control_ids for a in attachments) ||
            throw(ArgumentError("control attachment references an unknown control"))
        new{T}(String(id), base_power, base_frequency, copy(generators), copy(controls), copy(attachments))
    end
end

function Case(
    id::AbstractString;
    base_power,
    base_frequency,
    generators::AbstractVector{<:Generator},
    controls::AbstractVector{<:VoltVarDroop},
    attachments::AbstractVector{<:GeneratorControlAttachment},
)
    T = promote_type(
        typeof(base_power), typeof(base_frequency),
        (typeof(g.p_min) for g in generators)...,
    )
    # The explicit conversion keeps the public case homogeneous and avoids
    # type instability when a case is assembled from integer literals.
    gs = Generator{T}[
        Generator{T}(
            g.id, g.bus_id, g.available, T(g.p_min), T(g.p_max), T(g.q_min),
            T(g.q_max), T(g.initial_p), T(g.initial_q),
        ) for g in generators
    ]
    cs = VoltVarDroop{T}[
        VoltVarDroop{T}(
            VoltageSchedule{T}(T(c.schedule.v_ref), T(c.schedule.v_db_low),
                               T(c.schedule.v_db_high), c.schedule.unit),
            T(c.slope), T(c.q_at_deadband),
            ReactiveCapability{T}(T(c.capability.p_min), T(c.capability.p_max),
                                  T(c.capability.q_min), T(c.capability.q_max)),
        ) for c in controls
    ]
    return Case{T}(String(id), T(base_power), T(base_frequency), gs, cs, collect(attachments))
end

validate_case(case::Case) = true

function droop_response(case::Case, generator_id::Integer, voltage::Real; p::Real)
    gen = findfirst(g -> g.id == generator_id, case.generators)
    gen === nothing && throw(KeyError(generator_id))
    attachment_index = findfirst(a -> a.generator_id == generator_id, case.attachments)
    attachment_index === nothing &&
        throw(ArgumentError("generator has no volt-var control attachment"))
    attachment = case.attachments[attachment_index]
    return droop_response(case.controls[attachment.control_id], voltage; p = p)
end
