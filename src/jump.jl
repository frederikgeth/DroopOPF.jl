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

function _smooth_droop_value(
    control::VoltVarDroop,
    voltage::Real,
    slope::Real,
    v_ref::Real,
    deadband_low::Real,
    deadband_high::Real,
    voltage_epsilon::Real,
    reactive_epsilon::Real,
)
    low = _smooth_positive(v_ref - deadband_low - voltage, voltage_epsilon)
    high = _smooth_positive(voltage - v_ref - deadband_high, voltage_epsilon)
    raw = control.q_at_deadband + (low - high) / slope
    q_min, q_max = control.capability.q_min, control.capability.q_max
    return q_min + _smooth_positive(raw - q_min, reactive_epsilon) -
           _smooth_positive(raw - q_max, reactive_epsilon)
end

# Keep scalar softplus operators separate so legacy JuMP can retain exact
# Hessians when droop settings are variables. This is the same smooth curve as
# _smooth_droop_value, with unchanged voltage and reactive smoothing widths.
function _smooth_droop_expression!(model, name, control, voltage, parameters,
    voltage_epsilon, reactive_epsilon)
    vsoft = Symbol(name, "_voltage_positive")
    qsoft = Symbol(name, "_reactive_positive")
    JuMP.register(model, vsoft, 1, z -> _smooth_positive(z, voltage_epsilon); autodiff=true)
    JuMP.register(model, qsoft, 1, z -> _smooth_positive(z, reactive_epsilon); autodiff=true)
    low = Expr(:call, vsoft, Expr(:call, :-,
        Expr(:call, :-, parameters.v_ref, parameters.deadband_low), voltage))
    high = Expr(:call, vsoft, Expr(:call, :-,
        Expr(:call, :-, voltage, parameters.v_ref), parameters.deadband_high))
    raw = JuMP.add_nonlinear_expression(model, Expr(:call, :+, control.q_at_deadband,
        Expr(:call, :/, Expr(:call, :-, low, high), parameters.slope)))
    qmin, qmax = control.capability.q_min, control.capability.q_max
    return Expr(:call, :+, qmin, Expr(:call, :-,
        Expr(:call, qsoft, Expr(:call, :-, raw, qmin)),
        Expr(:call, qsoft, Expr(:call, :-, raw, qmax))))
end

function _set_bound!(variable, lower, upper)
    set_lower_bound(variable, lower)
    set_upper_bound(variable, upper)
end

# Both formulations use the same terminal-limit convention. Physical validation
# separately evaluates internal-side currents in branch_flows.
function _add_branch_thermal_limits!(model, network::ACNetwork, vm, va)
    indices = _bus_indices(network)
    for branch in network.branches
        branch.available || continue
        f, t = indices[branch.from_bus], indices[branch.to_bus]
        yff, yft, ytf, ytt = _branch_admittances(branch)
        for (i, j, self, mutual) in ((f, t, yff, yft), (t, f, ytt, ytf))
            gs, bs = real(self), imag(self)
            gm, bm = real(mutual), imag(mutual)
            @NLconstraint(model,
                (vm[i]^2 * gs + vm[i] * vm[j] *
                    (gm * cos(va[i] - va[j]) + bm * sin(va[i] - va[j])))^2 +
                (-vm[i]^2 * bs + vm[i] * vm[j] *
                    (gm * sin(va[i] - va[j]) - bm * cos(va[i] - va[j])))^2 <=
                branch.thermal_limit^2)
        end
    end
    return nothing
end

function _build_acopf_model(
    case::Case;
    voltage_epsilon::Real,
    reactive_relative_epsilon::Real,
    reactive_epsilon::Union{Nothing,Real},
    silent::Bool,
    optimizer_factory = Ipopt.Optimizer,
    initial_state::Union{Nothing,ACState} = nothing,
    shared_model::Union{Nothing,Model} = nothing,
    scenario_prefix::String = "",
    set_objective::Bool = true,
    droop_parameter_variables::AbstractDict = Dict(),
    tap_controls = nothing,
    shunt_controls = nothing,
    normalize_controls::Bool = false,
    droop_q_bounds::Symbol = :explicit,
    droop_q_formulation::Symbol = :explicit,
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
    droop_q_bounds in (:explicit, :implied) ||
        throw(ArgumentError("droop_q_bounds must be :explicit or :implied"))
    droop_q_formulation in (:explicit, :reduced) ||
        throw(ArgumentError("droop_q_formulation must be :explicit or :reduced"))
    droop_q_formulation == :reduced && droop_q_bounds != :explicit &&
        throw(ArgumentError("reduced droop Q has no separate Q bound; use droop_q_bounds=:explicit"))
    if !isnothing(initial_state)
        length(initial_state.vm) == nbus && length(initial_state.va) == nbus ||
            throw(ArgumentError("initial_state voltage vectors do not match the network"))
        length(initial_state.pg) == ngen && length(initial_state.qg) == ngen ||
            throw(ArgumentError("initial_state generator vectors do not match the case"))
    end

    model = isnothing(shared_model) ? Model(optimizer_factory) : shared_model
    silent && set_silent(model)
    bus_indices = _bus_indices(network)
    attachment_by_generator = Dict(
        attachment.generator_id => attachment for attachment in case.attachments
    )
    vm = @variable(model, [1:nbus], base_name = scenario_prefix * "vm")
    va = @variable(model, [1:nbus], base_name = scenario_prefix * "va")
    pg = @variable(model, [1:ngen], base_name = scenario_prefix * "pg")
    qg = if droop_q_formulation == :explicit
        collect(@variable(model, [1:ngen], base_name = scenario_prefix * "qg"))
    else
        Any[
            generator.available && haskey(attachment_by_generator, generator.id) ? nothing :
            @variable(model, base_name = scenario_prefix * "qg[$i]")
            for (i, generator) in enumerate(case.generators)
        ]
    end

    for (i, bus) in enumerate(network.buses)
        _set_bound!(vm[i], bus.v_min, bus.v_max)
        _set_bound!(va[i], -pi, pi)
        bus.reference && fix(va[i], 0.0; force = true)
        set_start_value(vm[i], isnothing(initial_state) ? 1.0 : initial_state.vm[i])
        set_start_value(va[i], isnothing(initial_state) ? 0.0 : initial_state.va[i])
    end
    attached_generator_ids = Set(keys(attachment_by_generator))
    implied_q_bound_ids = Int[]
    reduced_q_generator_ids = Int[]
    for (i, generator) in enumerate(case.generators)
        _set_bound!(pg[i], generator.p_min, generator.p_max)
        reduced_q = droop_q_formulation == :reduced &&
            generator.available && generator.id in attached_generator_ids
        if reduced_q
            push!(reduced_q_generator_ids, generator.id)
        elseif droop_q_bounds == :explicit ||
               !(generator.available && generator.id in attached_generator_ids)
            _set_bound!(qg[i], generator.q_min, generator.q_max)
        else
            push!(implied_q_bound_ids, generator.id)
        end
        set_start_value(pg[i], isnothing(initial_state) ? generator.initial_p : initial_state.pg[i])
        reduced_q || set_start_value(
            qg[i],
            isnothing(initial_state) ? generator.initial_q : initial_state.qg[i],
        )
        if !generator.available
            fix(pg[i], 0.0; force = true)
            fix(qg[i], 0.0; force = true)
        end
    end
    model.ext[:droop_q_bounds] = droop_q_bounds
    model.ext[:implied_droop_q_bound_generator_ids] = implied_q_bound_ids
    model.ext[:droop_q_formulation] = droop_q_formulation
    model.ext[:reduced_droop_q_generator_ids] = reduced_q_generator_ids

    deferred_droop_constraints = Expr[]
    for attachment in case.attachments
        generator_index = findfirst(g -> g.id == attachment.generator_id, case.generators)
        generator_index === nothing && error("validated attachment lookup failed")
        generator = case.generators[generator_index]
        generator.available || continue
        location_index = get(bus_indices, attachment.location.bus_id, 0)
        location_index > 0 || error("validated control-location lookup failed")
        control = case.controls[attachment.control_id]
        _set_bound!(
            pg[generator_index],
            max(generator.p_min, control.capability.p_min),
            min(generator.p_max, control.capability.p_max),
        )
        function_name = Symbol(scenario_prefix, "droop_response_", attachment.control_id)
        control_reactive_epsilon = reactive_smoothing_epsilon(
            control,
            reactive_relative_epsilon;
            absolute_epsilon = reactive_epsilon,
        )
        parameters = get(droop_parameter_variables, attachment.control_id, nothing)
        if isnothing(parameters)
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
        end
        droop_expression = if isnothing(parameters)
            Expr(:call, function_name, vm[location_index])
        else
            _smooth_droop_expression!(model, function_name, control,
                vm[location_index], parameters, voltage_epsilon, control_reactive_epsilon)
        end
        if droop_q_formulation == :reduced
            qg[generator_index] = JuMP.add_nonlinear_expression(model, droop_expression)
        else
            push!(deferred_droop_constraints, Expr(
                :call,
                Symbol("=="),
                qg[generator_index],
                droop_expression,
            ))
        end
    end

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
    taps = Dict{Int,VariableRef}()
    shunts = Dict{Int,VariableRef}()
    if isnothing(tap_controls)
        Y = _admittance_matrix(network)
        if !isnothing(shunt_controls)
            shunts = _shunt_variables!(model,case,shunt_controls,Y;normalize_controls)
        end
        conductance_matrix = real.(Y)
        susceptance_matrix = imag.(Y)

        for i in 1:nbus
            p_generation = sum(pg[k] for k in generators_at_bus[i]; init = 0.0)
            q_generation = sum(qg[k] for k in generators_at_bus[i]; init = 0.0)
            selected = [b for b in network.banks if haskey(shunts,b.id) && bus_indices[b.bus_id]==i]
            variable_g = sum((only(b.step_conductances)/only(b.step_susceptances))*shunts[b.id] for b in selected; init=0.)
            variable_b = sum(shunts[b.id] for b in selected; init=0.)
            @NLconstraint(
                model,
                p_generation - load_p[i] - variable_g*vm[i]^2 ==
                vm[i] * sum(
                    vm[j] * (conductance_matrix[i, j] * cos(va[i] - va[j]) +
                             susceptance_matrix[i, j] * sin(va[i] - va[j])) for j in 1:nbus
                ),
            )
            @NLconstraint(
                model,
                q_generation - load_q[i] + variable_b*vm[i]^2 ==
                vm[i] * sum(
                    vm[j] * (conductance_matrix[i, j] * sin(va[i] - va[j]) -
                             susceptance_matrix[i, j] * cos(va[i] - va[j])) for j in 1:nbus
                ),
            )
        end

        _add_branch_thermal_limits!(model, network, vm, va)
    else
        taps,shunts = _add_tap_network!(model,case,vm,va,pg,qg,generators_at_bus,load_p,load_q,tap_controls,shunt_controls;normalize_controls)
    end

    # Keep the legacy explicit formulation's nonlinear constraint ordering.
    # Reduced mode must construct its expressions before reactive balance, but
    # explicit droop equalities historically followed all network constraints.
    for constraint in deferred_droop_constraints
        JuMP.add_nonlinear_constraint(model, constraint)
    end

    if set_objective
        if droop_q_formulation == :reduced
            @NLobjective(
                model,
                Min,
                sum((pg[i] - case.generators[i].initial_p)^2 +
                    1.0e-3 * (qg[i] - case.generators[i].initial_q)^2 for i in 1:ngen),
            )
        else
            @objective(
                model,
                Min,
                sum((pg[i] - case.generators[i].initial_p)^2 +
                    1.0e-3 * (qg[i] - case.generators[i].initial_q)^2 for i in 1:ngen),
            )
        end
    end
    return model, (vm = vm, va = va, pg = pg, qg = qg, taps = taps, shunts = shunts)
end

function solve_opf(
    case::Case;
    smooth_epsilon::Union{Nothing,Real} = 1.0e-4,
    smooth_voltage_epsilon::Union{Nothing,Real} = nothing,
    smooth_reactive_relative_epsilon::Union{Nothing,Real} = nothing,
    smooth_reactive_epsilon::Union{Nothing,Real} = nothing,
    optimizer_factory = Ipopt.Optimizer,
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
        optimizer_factory = optimizer_factory,
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
    optimizer_factory = Ipopt.Optimizer,
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
            optimizer_factory = optimizer_factory,
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
