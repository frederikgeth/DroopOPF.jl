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
    network::Union{Nothing,ACNetwork{T}}
    loads::Vector{Load{T}}
    generators::Vector{Generator{T}}
    controls::Vector{VoltVarDroop{T}}
    attachments::Vector{GeneratorControlAttachment}

    function Case{T}(
        id::AbstractString,
        base_power::T,
        base_frequency::T,
        network::Union{Nothing,ACNetwork{T}},
        loads::Vector{Load{T}},
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
        length(unique(a.generator_id for a in attachments)) == length(attachments) ||
            throw(ArgumentError("each generator may have at most one control attachment in M1"))
        generator_ids = Set(g.id for g in generators)
        control_ids = Set(eachindex(controls))
        all(a.generator_id in generator_ids for a in attachments) ||
            throw(ArgumentError("control attachment references an unknown generator"))
        all(a.control_id in control_ids for a in attachments) ||
            throw(ArgumentError("control attachment references an unknown control"))
        if !isnothing(network)
            bus_ids = Set(b.id for b in network.buses)
            all(g.bus_id in bus_ids for g in generators) ||
                throw(ArgumentError("generator references an unknown network bus"))
            all(l.bus_id in bus_ids for l in loads) ||
                throw(ArgumentError("load references an unknown network bus"))
            all(a.location.bus_id in bus_ids for a in attachments) ||
                throw(ArgumentError("control location references an unknown network bus"))
        end
        new{T}(String(id), base_power, base_frequency, network, copy(loads),
               copy(generators), copy(controls), copy(attachments))
    end
end

function Case(
    id::AbstractString;
    base_power,
    base_frequency,
    network = nothing,
    loads::AbstractVector{<:Load} = Load[],
    generators::AbstractVector{<:Generator},
    controls::AbstractVector{<:VoltVarDroop},
    attachments::AbstractVector{<:GeneratorControlAttachment},
)
    numeric_types = Any[typeof(base_power), typeof(base_frequency)]
    append!(numeric_types, (typeof(g.p_min) for g in generators))
    append!(numeric_types, (typeof(l.p) for l in loads))
    if !isnothing(network)
        append!(numeric_types, (typeof(b.v_min) for b in network.buses))
        append!(numeric_types, (typeof(br.resistance) for br in network.branches))
    end
    T = promote_type(numeric_types...)
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
    net = if isnothing(network)
        nothing
    else
        ACNetwork{T}[
            ACNetwork{T}(
                Bus{T}[Bus{T}(b.id, T(b.v_min), T(b.v_max), b.reference) for b in network.buses],
                Branch{T}[Branch{T}(br.id, br.from_bus, br.to_bus, T(br.resistance),
                    T(br.reactance), T(br.charging), T(br.thermal_limit), br.available)
                    for br in network.branches],
            ),
        ][1]
    end
    ls = Load{T}[Load{T}(l.id, l.bus_id, T(l.p), T(l.q)) for l in loads]
    return Case{T}(String(id), T(base_power), T(base_frequency), net, ls, gs, cs, collect(attachments))
end

function validate_case(case::Case)
    generator_indices = Dict(generator.id => i for (i, generator) in enumerate(case.generators))
    for attachment in case.attachments
        generator = case.generators[generator_indices[attachment.generator_id]]
        control = case.controls[attachment.control_id]
        p_overlap = max(generator.p_min, control.capability.p_min) <=
            min(generator.p_max, control.capability.p_max)
        p_overlap || throw(ArgumentError(
            "control $(attachment.control_id) has no active-power overlap with generator $(generator.id)",
        ))
        control.capability.q_min >= generator.q_min &&
            control.capability.q_max <= generator.q_max ||
            throw(ArgumentError(
                "control $(attachment.control_id) reactive capability must be inside generator $(generator.id) limits",
            ))
    end
    return true
end

function droop_response(case::Case, generator_id::Integer, voltage::Real; p::Real)
    gen = findfirst(g -> g.id == generator_id, case.generators)
    gen === nothing && throw(KeyError(generator_id))
    attachment_index = findfirst(a -> a.generator_id == generator_id, case.attachments)
    attachment_index === nothing &&
        throw(ArgumentError("generator has no volt-var control attachment"))
    attachment = case.attachments[attachment_index]
    return droop_response(case.controls[attachment.control_id], voltage; p = p)
end
