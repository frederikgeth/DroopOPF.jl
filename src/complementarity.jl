using JuMP
using MathOptComplements
using NLPModelsJuMP
import CCOpt

const _COMPLEMENTARITY_MOI = JuMP.MOI

"""Result returned by [`solve_opf_complementarity`](@ref)."""
struct ComplementarityOPFResult{T<:Real}
    state::Union{Nothing,ACState{T}}
    objective::T
    termination_status::Symbol
    primal_status::Symbol
    complementarity_residual_max::T
end

function _add_complementarity_ac_physics!(
    model,
    case::Case,
    vm,
    va,
    pg,
    qg,
)
    network = case.network
    bus_indices = _bus_indices(network)
    nbus = length(network.buses)

    generators_at_bus = [Int[] for _ in 1:nbus]
    for (i, generator) in enumerate(case.generators)
        push!(generators_at_bus[bus_indices[generator.bus_id]], i)
    end
    load_p = zeros(Float64, nbus)
    load_q = zeros(Float64, nbus)
    for load in case.loads
        load_index = bus_indices[load.bus_id]
        load_p[load_index] += load.p
        load_q[load_index] += load.q
    end
    Y = _admittance_matrix(network)
    conductance_matrix = real.(Y)
    susceptance_matrix = imag.(Y)

    for i in 1:nbus
        p_generation = sum(pg[k] for k in generators_at_bus[i]; init = 0.0)
        q_generation = sum(qg[k] for k in generators_at_bus[i]; init = 0.0)
        @NLconstraint(
            model,
            p_generation - load_p[i] ==
            vm[i] * sum(
                vm[j] * (conductance_matrix[i, j] * cos(va[i] - va[j]) +
                         susceptance_matrix[i, j] * sin(va[i] - va[j])) for j in 1:nbus
            ),
        )
        @NLconstraint(
            model,
            q_generation - load_q[i] ==
            vm[i] * sum(
                vm[j] * (conductance_matrix[i, j] * sin(va[i] - va[j]) -
                         susceptance_matrix[i, j] * cos(va[i] - va[j])) for j in 1:nbus
            ),
        )
    end

    for branch in network.branches
        branch.available || continue
        from = bus_indices[branch.from_bus]
        to = bus_indices[branch.to_bus]
        y = inv(complex(branch.resistance, branch.reactance))
        conductance, susceptance = real(y), imag(y)
        shunt = branch.charging / 2
        δ_from = va[from] - va[to]
        δ_to = va[to] - va[from]
        @NLconstraint(
            model,
            (vm[from]^2 * conductance -
             vm[from] * vm[to] * (conductance * cos(δ_from) + susceptance * sin(δ_from)))^2 +
            (-vm[from]^2 * (susceptance + shunt) -
             vm[from] * vm[to] * (conductance * sin(δ_from) - susceptance * cos(δ_from)))^2 <=
            branch.thermal_limit^2,
        )
        @NLconstraint(
            model,
            (vm[to]^2 * conductance -
             vm[to] * vm[from] * (conductance * cos(δ_to) + susceptance * sin(δ_to)))^2 +
            (-vm[to]^2 * (susceptance + shunt) -
             vm[to] * vm[from] * (conductance * sin(δ_to) - susceptance * cos(δ_to)))^2 <=
            branch.thermal_limit^2,
        )
    end
    return
end

"""Build an exact PWL-droop AC OPF model for CCOpt.

Each voltage hinge is represented as ``z >= 0 ⟂ z - a >= 0``. Reactive
clipping is the KKT system of projection of the raw droop value onto the
reactive capability interval. The four complementarity pairs per attachment
therefore encode deadband, proportional, and saturated operation without a
smooth approximation.
"""
function _build_complementarity_opf_model(
    case::Case;
    silent::Bool,
    initial_state::Union{Nothing,ACState} = nothing,
)
    validate_case(case)
    isnothing(case.network) && throw(ArgumentError("AC OPF requires case.network"))
    network = case.network
    nbus = length(network.buses)
    ngen = length(case.generators)
    count(bus -> bus.reference, network.buses) == 1 ||
        throw(ArgumentError("AC OPF requires exactly one reference bus"))
    if !isnothing(initial_state)
        length(initial_state.vm) == nbus && length(initial_state.va) == nbus ||
            throw(ArgumentError("initial_state voltage vectors do not match the network"))
        length(initial_state.pg) == ngen && length(initial_state.qg) == ngen ||
            throw(ArgumentError("initial_state generator vectors do not match the case"))
    end

    model = Model(CCOpt.Optimizer)
    # This must be called before adding complementarity constraints so JuMP can
    # route them to CCOpt's MOI wrapper.
    MathOptComplements.Bridges.add_all_bridges(model)
    silent && set_silent(model)
    @variable(model, vm[1:nbus])
    @variable(model, va[1:nbus])
    @variable(model, pg[1:ngen])
    @variable(model, qg[1:ngen])

    for (i, bus) in enumerate(network.buses)
        _set_bound!(vm[i], bus.v_min, bus.v_max)
        _set_bound!(va[i], -pi, pi)
        bus.reference && fix(va[i], 0.0; force = true)
        set_start_value(vm[i], isnothing(initial_state) ? 1.0 : initial_state.vm[i])
        set_start_value(va[i], isnothing(initial_state) ? 0.0 : initial_state.va[i])
    end
    for (i, generator) in enumerate(case.generators)
        _set_bound!(pg[i], generator.p_min, generator.p_max)
        _set_bound!(qg[i], generator.q_min, generator.q_max)
        set_start_value(pg[i], isnothing(initial_state) ? generator.initial_p : initial_state.pg[i])
        set_start_value(qg[i], isnothing(initial_state) ? generator.initial_q : initial_state.qg[i])
        if !generator.available
            fix(pg[i], 0.0; force = true)
            fix(qg[i], 0.0; force = true)
        end
    end

    _add_complementarity_ac_physics!(model, case, vm, va, pg, qg)

    generator_indices = Dict(generator.id => i for (i, generator) in enumerate(case.generators))
    bus_indices = _bus_indices(network)
    active_attachments = Tuple{GeneratorControlAttachment,Int,Int}[]
    for attachment in case.attachments
        generator_index = generator_indices[attachment.generator_id]
        generator = case.generators[generator_index]
        generator.available || continue
        control = case.controls[attachment.control_id]
        location_index = bus_indices[attachment.location.bus_id]
        _set_bound!(
            pg[generator_index],
            max(generator.p_min, control.capability.p_min),
            min(generator.p_max, control.capability.p_max),
        )
        push!(active_attachments, (attachment, generator_index, location_index))
    end

    ncontrol = length(active_attachments)
    @variable(model, voltage_lower[1:ncontrol] >= 0)
    @variable(model, voltage_lower_complement[1:ncontrol] >= 0)
    @variable(model, voltage_upper[1:ncontrol] >= 0)
    @variable(model, voltage_upper_complement[1:ncontrol] >= 0)
    @variable(model, raw_q[1:ncontrol])
    @variable(model, q_lower_slack[1:ncontrol] >= 0)
    @variable(model, q_lower_multiplier[1:ncontrol] >= 0)
    @variable(model, q_upper_slack[1:ncontrol] >= 0)
    @variable(model, q_upper_multiplier[1:ncontrol] >= 0)

    for (k, (_, generator_index, location_index)) in enumerate(active_attachments)
        attachment = active_attachments[k][1]
        control = case.controls[attachment.control_id]
        schedule = control.schedule
        q_min, q_max = control.capability.q_min, control.capability.q_max

        # max(v_db_low - V, 0)
        @constraint(
            model,
            voltage_lower_complement[k] - voltage_lower[k] +
            schedule.v_db_low - vm[location_index] == 0,
        )
        @constraint(
            model,
            [voltage_lower[k], voltage_lower_complement[k]] in
            _COMPLEMENTARITY_MOI.Complements(2),
        )
        # max(V - v_db_high, 0)
        @constraint(
            model,
            voltage_upper_complement[k] - voltage_upper[k] +
            vm[location_index] - schedule.v_db_high == 0,
        )
        @constraint(
            model,
            [voltage_upper[k], voltage_upper_complement[k]] in
            _COMPLEMENTARITY_MOI.Complements(2),
        )

        @constraint(
            model,
            raw_q[k] == control.q_at_deadband +
                        (voltage_lower[k] - voltage_upper[k]) / control.slope,
        )
        # Projection of raw_q onto [q_min, q_max].
        @constraint(model, q_lower_slack[k] == qg[generator_index] - q_min)
        @constraint(model, q_upper_slack[k] == q_max - qg[generator_index])
        @constraint(
            model,
            qg[generator_index] - raw_q[k] -
            q_lower_multiplier[k] + q_upper_multiplier[k] == 0,
        )
        @constraint(
            model,
            [q_lower_slack[k], q_lower_multiplier[k]] in
            _COMPLEMENTARITY_MOI.Complements(2),
        )
        @constraint(
            model,
            [q_upper_slack[k], q_upper_multiplier[k]] in
            _COMPLEMENTARITY_MOI.Complements(2),
        )
    end

    @objective(
        model,
        Min,
        sum((pg[i] - case.generators[i].initial_p)^2 +
            1.0e-3 * (qg[i] - case.generators[i].initial_q)^2 for i in 1:ngen),
    )
    return model, (vm = vm, va = va, pg = pg, qg = qg,
                   voltage_lower = voltage_lower,
                   voltage_lower_complement = voltage_lower_complement,
                   voltage_upper = voltage_upper,
                   voltage_upper_complement = voltage_upper_complement,
                   q_lower_slack = q_lower_slack,
                   q_lower_multiplier = q_lower_multiplier,
                   q_upper_slack = q_upper_slack,
                   q_upper_multiplier = q_upper_multiplier)
end

"""Solve an AC OPF with exact complementarity-encoded volt-var controls."""
function solve_opf_complementarity(
    case::Case;
    silent::Bool = true,
    initial_state::Union{Nothing,ACState} = nothing,
    optimizer_attributes::AbstractDict = Dict{String,Any}(),
)
    model, variables = _build_complementarity_opf_model(
        case;
        silent = silent,
        initial_state = initial_state,
    )
    for (key, value) in optimizer_attributes
        set_optimizer_attribute(model, key, value)
    end
    optimize!(model)
    termination = Symbol(string(termination_status(model)))
    primal = Symbol(string(primal_status(model)))
    if !has_values(model)
        return ComplementarityOPFResult{Float64}(nothing, NaN, termination, primal, NaN)
    end
    state = ACState(
        value.(variables.vm),
        value.(variables.va),
        value.(variables.pg),
        value.(variables.qg),
    )
    complementarity_residual = maximum(
        abs,
        vcat(
            value.(variables.voltage_lower) .* value.(variables.voltage_lower_complement),
            value.(variables.voltage_upper) .* value.(variables.voltage_upper_complement),
            value.(variables.q_lower_slack) .* value.(variables.q_lower_multiplier),
            value.(variables.q_upper_slack) .* value.(variables.q_upper_multiplier),
        );
        init = 0.0,
    )
    return ComplementarityOPFResult{Float64}(
        state,
        objective_value(model),
        termination,
        primal,
        complementarity_residual,
    )
end
