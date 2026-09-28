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
        append!(numeric_types, (typeof(s.conductance) for s in network.shunts))
        append!(numeric_types, (typeof(first(b.step_conductances)) for b in network.banks))
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
                    T(br.reactance), T(br.charging), T(br.thermal_limit), br.available,
                    T(br.tap_ratio), T(br.phase_shift))
                    for br in network.branches],
                FixedShunt{T}[FixedShunt{T}(s.id, s.bus_id, T(s.conductance),
                    T(s.susceptance), s.available) for s in network.shunts],
                ShuntBank{T}[ShuntBank{T}(b.id,b.bus_id,b.step_conductances,
                    b.step_susceptances,b.legal_states,b.state,b.nominal_state,b.available) for b in network.banks],
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

"""Validate explicit reactive-control assignments against one case."""
function validate_reactive_assignments(
    case::Case,
    assignments::AbstractVector{<:ReactiveControlAssignment},
)
    length(unique(a.generator_id for a in assignments)) == length(assignments) ||
        throw(ArgumentError("each generator may have at most one reactive-control mode"))
    generators = Dict(generator.id => generator for generator in case.generators)
    bus_ids = isnothing(case.network) ? Set{Int}() : Set(bus.id for bus in case.network.buses)
    buses = isnothing(case.network) ? Dict{Int,Any}() :
        Dict(bus.id => bus for bus in case.network.buses)
    for assignment in assignments
        haskey(generators, assignment.generator_id) ||
            throw(ArgumentError("reactive-control assignment references an unknown generator"))
        generator = generators[assignment.generator_id]
        mode = assignment.mode
        if mode isa FixedQ
            generator.q_min <= mode.q_schedule <= generator.q_max || throw(ArgumentError(
                "fixed-Q schedule must lie within generator $(generator.id) limits"))
        elseif mode isa AVR
            isnothing(case.network) && throw(ArgumentError("AVR requires an AC network"))
            location = assignment.location
            location.bus_id in bus_ids ||
                throw(ArgumentError("AVR location references an unknown bus"))
            bus = buses[location.bus_id]
            bus.v_min <= mode.voltage_setpoint <= bus.v_max || throw(ArgumentError(
                "AVR setpoint must lie within regulated-bus voltage limits"))
            location.kind == :generator_terminal && location.bus_id != generator.bus_id &&
                throw(ArgumentError("generator-terminal AVR must regulate its generator bus"))
            if location.kind == :branch_terminal
                branch = findfirst(b -> b.id == location.branch_id, case.network.branches)
                !isnothing(branch) || throw(ArgumentError("AVR branch-terminal references an unknown branch"))
                selected = case.network.branches[branch]
                selected.available || throw(ArgumentError("AVR branch-terminal references an unavailable branch"))
                endpoint = location.side == :from ? selected.from_bus : selected.to_bus
                endpoint == location.bus_id || throw(ArgumentError(
                    "AVR branch-terminal bus_id must match the declared branch side"))
            end
        elseif mode isa VoltVarDroop
            location = assignment.location
            !isnothing(case.network) && location.bus_id in bus_ids || throw(ArgumentError(
                "VoltVarDroop location references an unknown bus"))
            mode.capability.p_min <= mode.capability.p_max || error("invalid capability")
            max(generator.p_min, mode.capability.p_min) <=
                min(generator.p_max, mode.capability.p_max) || throw(ArgumentError(
                    "VoltVarDroop has no active-power overlap with generator $(generator.id)"))
            mode.capability.q_min >= generator.q_min &&
                mode.capability.q_max <= generator.q_max || throw(ArgumentError(
                    "VoltVarDroop reactive capability must be inside generator $(generator.id) limits"))
        end
    end
    avr_targets = Dict{Tuple{Symbol,Int,Union{Nothing,Symbol}},Float64}()
    for assignment in assignments
        assignment.mode isa AVR || continue
        key = (assignment.location.kind, assignment.location.bus_id,
            assignment.location.side)
        target = Float64(assignment.mode.voltage_setpoint)
        haskey(avr_targets, key) && avr_targets[key] != target && throw(ArgumentError(
            "AVR assignments at one regulated location must use the same setpoint"))
        avr_targets[key] = target
    end
    true
end

function _active_avr_groups(case::Case, assignments)
    isnothing(assignments) && return Vector{Vector{ReactiveControlAssignment}}()
    available = Set(g.id for g in case.generators if g.available)
    groups = Vector{Vector{ReactiveControlAssignment}}()
    for assignment in assignments
        assignment.mode isa AVR && assignment.generator_id in available || continue
        location = assignment.location
        if location.kind == :branch_terminal
            branch = only(filter(b -> b.id == location.branch_id, case.network.branches))
            branch.available || continue
        end
        index = findfirst(group -> first(group).location == assignment.location, groups)
        if isnothing(index)
            push!(groups, ReactiveControlAssignment[assignment])
        else
            push!(groups[index], assignment)
        end
    end
    groups
end

"""Project a legacy droop-only case into one explicit mode per generator.

Generators without a legacy attachment become `FreeQ`; existing attachments
become `VoltVarDroop` assignments. The case itself is not modified.
"""
function reactive_control_assignments(case::Case)
    by_generator = Dict(attachment.generator_id => attachment for attachment in case.attachments)
    assignments = ReactiveControlAssignment[]
    for generator in case.generators
        if haskey(by_generator, generator.id)
            attachment = by_generator[generator.id]
            push!(assignments, ReactiveControlAssignment(generator.id,
                case.controls[attachment.control_id], attachment.location))
        else
            push!(assignments, ReactiveControlAssignment(generator.id, FreeQ()))
        end
    end
    validate_reactive_assignments(case, assignments)
    assignments
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
