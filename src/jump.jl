using JuMP
using LogExpFunctions
import Ipopt

struct ACOPFResult{T<:Real}
    state::Union{Nothing,ACState{T}}
    objective::T
    termination_status::Symbol
    primal_status::Symbol
    smooth_epsilon::T
    smooth_reactive_relative_epsilon::T
    smooth_reactive_epsilon::Union{Nothing,T}
end

function _smooth_positive(x, epsilon)
    return epsilon * log1pexp(x / epsilon)
end

"""Return the reactive-power smoothing width for one droop control.

The relative default is expressed as a fraction of the smaller distance from
the deadband reactive reference to either capability limit. This makes the
regularization comparable for generators with different ratings and power
bases.
"""
function reactive_smoothing_epsilon(
    control::VoltVarDroop,
    relative_epsilon::Real;
    absolute_epsilon::Union{Nothing,Real} = nothing,
)
    relative_epsilon > 0 && isfinite(relative_epsilon) ||
        throw(ArgumentError("relative_epsilon must be positive and finite"))
    if !isnothing(absolute_epsilon)
        absolute_epsilon > 0 && isfinite(absolute_epsilon) ||
            throw(ArgumentError("absolute_epsilon must be positive and finite"))
        return absolute_epsilon
    end
    q_scale = min(
        control.q_at_deadband - control.capability.q_min,
        control.capability.q_max - control.q_at_deadband,
    )
    return relative_epsilon * q_scale
end

function _smooth_droop_value(
    control::VoltVarDroop,
    voltage::Real,
    voltage_epsilon::Real,
    reactive_epsilon::Real,
)
    low = _smooth_positive(control.schedule.v_db_low - voltage, voltage_epsilon)
    high = _smooth_positive(voltage - control.schedule.v_db_high, voltage_epsilon)
    raw = control.q_at_deadband + (low - high) / control.slope
    q_min, q_max = control.capability.q_min, control.capability.q_max
    return q_min + _smooth_positive(raw - q_min, reactive_epsilon) -
           _smooth_positive(raw - q_max, reactive_epsilon)
end

function _set_bound!(variable, lower, upper)
    set_lower_bound(variable, lower)
    set_upper_bound(variable, upper)
end

function _build_acopf_model(
    case::Case;
    voltage_epsilon::Real,
    reactive_relative_epsilon::Real,
    reactive_epsilon::Union{Nothing,Real},
    silent::Bool,
    initial_state::Union{Nothing,ACState} = nothing,
)
    isnothing(case.network) && throw(ArgumentError("AC OPF requires case.network"))
    network = case.network
    nbus = length(network.buses)
    ngen = length(case.generators)
    nbranch = length(network.branches)
    nbus > 0 || throw(ArgumentError("AC OPF requires at least one bus"))
    count(bus -> bus.reference, network.buses) == 1 ||
        throw(ArgumentError("AC OPF requires exactly one reference bus"))
    voltage_epsilon > 0 || throw(ArgumentError("smooth_voltage_epsilon must be positive"))
    reactive_relative_epsilon > 0 ||
        throw(ArgumentError("smooth_reactive_relative_epsilon must be positive"))
    if !isnothing(reactive_epsilon)
        reactive_epsilon > 0 || throw(ArgumentError("smooth_reactive_epsilon must be positive"))
    end
    if !isnothing(initial_state)
        length(initial_state.vm) == nbus && length(initial_state.va) == nbus ||
            throw(ArgumentError("initial_state voltage vectors do not match the network"))
        length(initial_state.pg) == ngen && length(initial_state.qg) == ngen ||
            throw(ArgumentError("initial_state generator vectors do not match the case"))
    end

    model = Model(Ipopt.Optimizer)
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

    bus_indices = _bus_indices(network)
    generator_indices = [bus_indices[g.bus_id] for g in case.generators]
    generators_at_bus = [Int[] for _ in 1:nbus]
    for (i, bus_index) in enumerate(generator_indices)
        push!(generators_at_bus[bus_index], i)
    end
    load_p = zeros(Float64, nbus)
    load_q = zeros(Float64, nbus)
    for load in case.loads
        bus_index = get(bus_indices, load.bus_id, 0)
        bus_index > 0 || throw(ArgumentError("load references an unknown bus"))
        load_p[bus_index] += load.p
        load_q[bus_index] += load.q
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

    for (i, branch) in enumerate(network.branches)
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

    for attachment in case.attachments
        generator_index = findfirst(g -> g.id == attachment.generator_id, case.generators)
        generator_index === nothing && error("validated attachment lookup failed")
        generator = case.generators[generator_index]
        generator.available || continue
        location_index = get(bus_indices, attachment.location.bus_id, 0)
        location_index > 0 || error("validated control-location lookup failed")
        control = case.controls[attachment.control_id]
        function_name = Symbol("droop_response_", attachment.control_id)
        control_reactive_epsilon = reactive_smoothing_epsilon(
            control,
            reactive_relative_epsilon;
            absolute_epsilon = reactive_epsilon,
        )
        JuMP.register(
            model,
            function_name,
            1,
            voltage -> _smooth_droop_value(
                control,
                voltage,
                voltage_epsilon,
                control_reactive_epsilon,
            ),
            autodiff = true,
        )
        # `@NLconstraint` requires function names to be literal symbols. Build
        # the expression programmatically because control IDs are data.
        droop_expression = Expr(:call, function_name, vm[location_index])
        droop_constraint = Expr(
            :call,
            Symbol("=="),
            qg[generator_index],
            droop_expression,
        )
        JuMP.add_nonlinear_constraint(model, droop_constraint)
    end

    @objective(
        model,
        Min,
        sum((pg[i] - case.generators[i].initial_p)^2 +
            1.0e-3 * (qg[i] - case.generators[i].initial_q)^2 for i in 1:ngen),
    )
    return model, (vm = vm, va = va, pg = pg, qg = qg)
end

function solve_opf(
    case::Case;
    smooth_epsilon::Union{Nothing,Real} = 1.0e-4,
    smooth_voltage_epsilon::Union{Nothing,Real} = nothing,
    smooth_reactive_relative_epsilon::Union{Nothing,Real} = nothing,
    smooth_reactive_epsilon::Union{Nothing,Real} = nothing,
    silent::Bool = true,
    initial_state::Union{Nothing,ACState} = nothing,
    optimizer_attributes::AbstractDict = Dict{String,Any}(),
)
    validate_case(case)
    base_epsilon = isnothing(smooth_epsilon) ? 1.0e-4 : smooth_epsilon
    voltage_epsilon = isnothing(smooth_voltage_epsilon) ? base_epsilon : smooth_voltage_epsilon
    reactive_relative_epsilon = isnothing(smooth_reactive_relative_epsilon) ?
        base_epsilon : smooth_reactive_relative_epsilon
    model, variables = _build_acopf_model(
        case;
        voltage_epsilon = voltage_epsilon,
        reactive_relative_epsilon = reactive_relative_epsilon,
        reactive_epsilon = smooth_reactive_epsilon,
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
        return ACOPFResult{Float64}(
            nothing,
            NaN,
            termination,
            primal,
            Float64(voltage_epsilon),
            Float64(reactive_relative_epsilon),
            isnothing(smooth_reactive_epsilon) ? nothing : Float64(smooth_reactive_epsilon),
        )
    end
    state = ACState(
        value.(variables.vm),
        value.(variables.va),
        value.(variables.pg),
        value.(variables.qg),
    )
    return ACOPFResult{Float64}(
        state,
        objective_value(model),
        termination,
        primal,
        Float64(voltage_epsilon),
        Float64(reactive_relative_epsilon),
        isnothing(smooth_reactive_epsilon) ? nothing : Float64(smooth_reactive_epsilon),
    )
end

solve(case::Case; kwargs...) = solve_opf(case; kwargs...)

struct ACOPFContinuationResult{T<:Real}
    results::Vector{ACOPFResult{T}}
end

"""
    solve_opf_continuation(case; smooth_epsilons, initial_state, kwargs...)

Solve a sequence of smoothed OPF problems, passing each available state as the
warm start for the next epsilon. The supplied epsilon sequence should usually
decrease from a robust, relatively smooth value to the desired final value.
"""
function solve_opf_continuation(
    case::Case;
    smooth_epsilons::AbstractVector{<:Real} = [1.0e-2, 1.0e-3, 1.0e-4],
    initial_state::Union{Nothing,ACState} = nothing,
    silent::Bool = true,
    optimizer_attributes::AbstractDict = Dict{String,Any}(),
)
    isempty(smooth_epsilons) &&
        throw(ArgumentError("smooth_epsilons must contain at least one value"))
    all(isfinite, smooth_epsilons) && all(>(0), smooth_epsilons) ||
        throw(ArgumentError("smooth_epsilons must be positive and finite"))

    results = ACOPFResult{Float64}[]
    warm_start = initial_state
    for epsilon in smooth_epsilons
        result = solve_opf(
            case;
            smooth_epsilon = epsilon,
            initial_state = warm_start,
            silent = silent,
            optimizer_attributes = optimizer_attributes,
        )
        push!(results, result)
        if isnothing(result.state)
            break
        end
        warm_start = result.state
    end
    return ACOPFContinuationResult(results)
end
