using JuMP
using LogExpFunctions
import Ipopt

struct ACOPFResult{T<:Real}
    state::Union{Nothing,ACState{T}}
    objective::T
    termination_status::Symbol
    primal_status::Symbol
    smooth_epsilon::Union{Nothing,T}
    smooth_reactive_relative_epsilon::Union{Nothing,T}
    smooth_reactive_epsilon::Union{Nothing,T}
end

# Only specialize widths that are constant zero; a variable initialized at zero
# must retain its deadband dependence.
_fixed_zero_deadband(low, high) = low isa Real && high isa Real && iszero(low) && iszero(high)

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
    raw = if control.schedule.v_db_low == control.schedule.v_db_high
        control.q_at_deadband + (control.schedule.v_ref - voltage) / control.slope
    else
        low = _smooth_positive(control.schedule.v_db_low - voltage, voltage_epsilon)
        high = _smooth_positive(voltage - control.schedule.v_db_high, voltage_epsilon)
        control.q_at_deadband + (low - high) / control.slope
    end
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
    raw = if _fixed_zero_deadband(deadband_low, deadband_high)
        control.q_at_deadband + (v_ref - voltage) / slope
    else
        low = _smooth_positive(v_ref - deadband_low - voltage, voltage_epsilon)
        high = _smooth_positive(voltage - v_ref - deadband_high, voltage_epsilon)
        control.q_at_deadband + (low - high) / slope
    end
    q_min, q_max = control.capability.q_min, control.capability.q_max
    return q_min + _smooth_positive(raw - q_min, reactive_epsilon) -
           _smooth_positive(raw - q_max, reactive_epsilon)
end

function _smooth_capability_droop_value(control,v,p,g,veps,qeps)
    isnothing(g.s_rated) && return _smooth_droop_value(control,v,veps,qeps)
    raw=control.schedule.v_db_low==control.schedule.v_db_high ?
        control.q_at_deadband+(control.schedule.v_ref-v)/control.slope :
        control.q_at_deadband+(_smooth_positive(control.schedule.v_db_low-v,veps)-
            _smooth_positive(v-control.schedule.v_db_high,veps))/control.slope
    lo,hi=reactive_limits(g,p);lo=max(lo,control.capability.q_min);hi=min(hi,control.capability.q_max)
    lo+_smooth_positive(raw-lo,qeps)-_smooth_positive(raw-hi,qeps)
end

# Keep scalar softplus operators separate so legacy JuMP can retain exact
# Hessians when droop settings are variables. This is the same smooth curve as
# _smooth_droop_value, with unchanged voltage and reactive smoothing widths.
function _smooth_droop_expression!(model, name, control, voltage, parameters,
    voltage_epsilon, reactive_epsilon; q_bounds=nothing)
    vsoft = Symbol(name, "_voltage_positive")
    qsoft = Symbol(name, "_reactive_positive")
    JuMP.register(model, vsoft, 1, z -> _smooth_positive(z, voltage_epsilon); autodiff=true)
    JuMP.register(model, qsoft, 1, z -> _smooth_positive(z, reactive_epsilon); autodiff=true)
    low = Expr(:call, vsoft, Expr(:call, :-,
        Expr(:call, :-, parameters.v_ref, parameters.deadband_low), voltage))
    high = Expr(:call, vsoft, Expr(:call, :-,
        Expr(:call, :-, voltage, parameters.v_ref), parameters.deadband_high))
    raw = JuMP.add_nonlinear_expression(model, Expr(:call, :+, control.q_at_deadband,
        Expr(:call, :/, _fixed_zero_deadband(parameters.deadband_low, parameters.deadband_high) ?
            Expr(:call, :-, parameters.v_ref, voltage) : Expr(:call, :-, low, high), parameters.slope)))
    qmin, qmax = isnothing(q_bounds) ? (control.capability.q_min, control.capability.q_max) : q_bounds
    return Expr(:call, :+, qmin, Expr(:call, :-,
        Expr(:call, qsoft, Expr(:call, :-, raw, qmin)),
        Expr(:call, qsoft, Expr(:call, :-, raw, qmax))))
end

function _reactive_bound_expressions!(model, case, pg)
    lo=Any[];hi=Any[]
    for (i,g) in enumerate(case.generators)
        if !g.available || isnothing(g.s_rated)
            push!(lo,g.q_min);push!(hi,g.q_max)
        else
            S=g.s_rated
            set_lower_bound(pg[i],max(g.p_min,-S))
            set_upper_bound(pg[i],min(g.p_max,S))
            # max guards infeasible intermediate iterates; feasible headroom is exact.
            h=@NLexpression(model,sqrt(max(S^2-pg[i]^2,1e-24)))
            push!(lo,@NLexpression(model,max(g.q_min,-h)))
            push!(hi,@NLexpression(model,min(g.q_max,h)))
        end
    end
    lo,hi
end
function _add_generator_circles!(model,case,pg,qg;reactive_assignments=nothing)
    implied=Set{Int}(e.generator_id for e in _reactive_droop_entries(case,reactive_assignments)
        if e.control.capability.q_min<=0<=e.control.capability.q_max)
    for group in _active_avr_groups(case,reactive_assignments)
        length(group)==1 && push!(implied,only(group).generator_id)
    end
    # Clipped Q plus |P|<=S algebraically enforces the circle. Repeating the
    # active circle as another row makes the saturation Jacobian rank deficient.
    get!(model.ext,:implied_apparent_power_generator_ids,Int[])
    for (i,g) in enumerate(case.generators)
        g.available && !isnothing(g.s_rated) || continue
        S=g.s_rated
        if g.id in implied && g.q_min<=0<=g.q_max
            push!(model.ext[:implied_apparent_power_generator_ids],g.id)
        else
            @NLconstraint(model,pg[i]^2+qg[i]^2<=S^2)
        end
    end
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
    reactive_assignments = nothing,
    power_balance_slacks::Bool = false,
    sparse_balance::Bool = false,
    load_relief = nothing,
    avr_target_variables = Dict(),
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

    if !isnothing(reactive_assignments)
        validate_reactive_assignments(case, reactive_assignments)
        droop_q_formulation == :explicit || throw(ArgumentError(
            "reactive_assignments currently require droop_q_formulation=:explicit"))
    end
    model = isnothing(shared_model) ? Model(optimizer_factory) : shared_model
    haskey(model.ext,:power_balance_slacks) ||
        (model.ext[:power_balance_slacks]=VariableRef[])
    silent && set_silent(model)
    bus_indices = _bus_indices(network)
    droop_entries = _reactive_droop_entries(case,reactive_assignments)
    attachment_by_generator = Dict(a.generator_id => a for a in droop_entries)
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

    qlo,qhi=_reactive_bound_expressions!(model,case,pg)
    if !isnothing(reactive_assignments)
        generator_by_id = Dict(generator.id => i for (i, generator) in enumerate(case.generators))
        for assignment in reactive_assignments
            i = generator_by_id[assignment.generator_id]
            generator = case.generators[i]
            generator.available || continue
            if assignment.mode isa FixedQ
                @constraint(model, qg[i] == assignment.mode.q_schedule)
            end
        end
        for (k, group) in enumerate(_active_avr_groups(case, reactive_assignments))
            indices = [generator_by_id[a.generator_id] for a in group]
            generators = case.generators[indices]
            j = bus_indices[first(group).location.bus_id]
            target = get(avr_target_variables,first(group).generator_id,first(group).mode.voltage_setpoint)
            q_min = @NLexpression(model,sum(qlo[i] for i in indices))
            q_max = @NLexpression(model,sum(qhi[i] for i in indices))
            group_q = sum(qg[i] for i in indices)
            # Projection onto effective Q capability is equivalent to ideal AVR:
            # interior Q implies V=target; saturation permits correctly signed release.
            # Scaling conditions the numerical equation, not a physical AVR droop.
            gain=max(sum(g.q_max-g.q_min for g in generators),1e-6)/.02
            width=max(voltage_epsilon^2*gain,1e-12)
            op=Symbol(scenario_prefix,"avr_projection_",k)
            JuMP.register(model,op,1,z->_smooth_positive(z,width);autodiff=true)
            request=@NLexpression(model,group_q-gain*(vm[j]-target))
            clip=Expr(:call,:+,q_min,Expr(:call,:-,
                Expr(:call,op,Expr(:call,:-,request,q_min)),
                Expr(:call,op,Expr(:call,:-,request,q_max))))
            JuMP.add_nonlinear_constraint(model,Expr(:call,Symbol("=="),group_q,clip))
            anchor_i=first(indices)
            for i in indices[2:end]
                @NLconstraint(model,(qg[i]-qlo[i])*(qhi[anchor_i]-qlo[anchor_i]) ==
                    (qg[anchor_i]-qlo[anchor_i])*(qhi[i]-qlo[i]))
            end
        end
    end

    deferred_droop_constraints = Expr[]
    for attachment in droop_entries
        generator_index = findfirst(g -> g.id == attachment.generator_id, case.generators)
        generator_index === nothing && error("validated attachment lookup failed")
        generator = case.generators[generator_index]
        generator.available || continue
        location_index = get(bus_indices, attachment.location.bus_id, 0)
        location_index > 0 || error("validated control-location lookup failed")
        control = attachment.control
        _set_bound!(
            pg[generator_index],
            max(generator.p_min, control.capability.p_min,isnothing(generator.s_rated) ? -Inf : -generator.s_rated),
            min(generator.p_max, control.capability.p_max,isnothing(generator.s_rated) ? Inf : generator.s_rated),
        )
        function_name = Symbol(scenario_prefix, "droop_response_", attachment.control_id)
        control_reactive_epsilon = reactive_smoothing_epsilon(
            control,
            reactive_relative_epsilon;
            absolute_epsilon = reactive_epsilon,
        )
        parameters = get(droop_parameter_variables, attachment.control_id, nothing)
        if isnothing(parameters) && isnothing(generator.s_rated)
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
        droop_expression = if isnothing(parameters) && isnothing(generator.s_rated)
            Expr(:call, function_name, vm[location_index])
        else
            pars=isnothing(parameters) ? (;slope=control.slope,v_ref=control.schedule.v_ref,
                deadband_low=control.schedule.v_ref-control.schedule.v_db_low,
                deadband_high=control.schedule.v_db_high-control.schedule.v_ref) : parameters
            bounds=if isnothing(generator.s_rated)
                nothing
            else
                h=@NLexpression(model,sqrt(max(generator.s_rated^2-pg[generator_index]^2,1e-24)))
                (@NLexpression(model,max(control.capability.q_min,-h)),
                 @NLexpression(model,min(control.capability.q_max,h)))
            end
            _smooth_droop_expression!(model, function_name, control,
                vm[location_index], pars, voltage_epsilon, control_reactive_epsilon;q_bounds=bounds)
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

    _add_generator_circles!(model,case,pg,qg;reactive_assignments)
    generator_indices = [bus_indices[g.bus_id] for g in case.generators]
    generators_at_bus = [Int[] for _ in 1:nbus]
    for (i, bus_index) in enumerate(generator_indices)
        push!(generators_at_bus[bus_index], i)
    end
    load_p = Any[0.0 for _ in 1:nbus]
    load_q = Any[0.0 for _ in 1:nbus]
    for (load_index,load) in enumerate(case.loads)
        bus_index = get(bus_indices, load.bus_id, 0)
        bus_index > 0 || throw(ArgumentError("load references an unknown bus"))
        load_p[bus_index] += load.p
        load_q[bus_index] += load.q
        if !isnothing(load_relief)
            load_p[bus_index] -= load_relief.p[load_index]
            load_q[bus_index] -= load_relief.q[load_index]
        end
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
            # Omit exact-zero admittances before constructing the expression tree.
            # JuMP's legacy nonlinear graph otherwise retains dense dependencies.
            # Preserve legacy droop warm-start trajectories used by CCOpt.
            neighbors = sparse_balance || (isempty(case.controls) && isnothing(reactive_assignments)) ?
                [j for j in 1:nbus if !iszero(Y[i, j])] : collect(1:nbus)
            p_generation = sum(pg[k] for k in generators_at_bus[i]; init = 0.0)
            q_generation = sum(qg[k] for k in generators_at_bus[i]; init = 0.0)
            selected = [b for b in network.banks if haskey(shunts,b.id) && bus_indices[b.bus_id]==i]
            variable_g = sum((only(b.step_conductances)/only(b.step_susceptances))*shunts[b.id] for b in selected; init=0.)
            variable_b = sum(shunts[b.id] for b in selected; init=0.)
            ppos = power_balance_slacks ? @variable(model,lower_bound=0,
                base_name=scenario_prefix*"p_balance_pos[$i]") : 0.0
            pneg = power_balance_slacks ? @variable(model,lower_bound=0,
                base_name=scenario_prefix*"p_balance_neg[$i]") : 0.0
            qpos = power_balance_slacks ? @variable(model,lower_bound=0,
                base_name=scenario_prefix*"q_balance_pos[$i]") : 0.0
            qneg = power_balance_slacks ? @variable(model,lower_bound=0,
                base_name=scenario_prefix*"q_balance_neg[$i]") : 0.0
            power_balance_slacks && append!(model.ext[:power_balance_slacks],
                (ppos,pneg,qpos,qneg))
            @NLconstraint(
                model,
                p_generation - load_p[i] - variable_g*vm[i]^2 + ppos-pneg ==
                vm[i] * sum(
                    vm[j] * (conductance_matrix[i, j] * cos(va[i] - va[j]) +
                             susceptance_matrix[i, j] * sin(va[i] - va[j])) for j in neighbors
                ),
            )
            @NLconstraint(
                model,
                q_generation - load_q[i] + variable_b*vm[i]^2 + qpos-qneg ==
                vm[i] * sum(
                    vm[j] * (conductance_matrix[i, j] * sin(va[i] - va[j]) -
                             susceptance_matrix[i, j] * cos(va[i] - va[j])) for j in neighbors
                ),
            )
        end

        _add_branch_thermal_limits!(model, network, vm, va)
    else
        taps,shunts = _add_tap_network!(model,case,vm,va,pg,qg,generators_at_bus,
            load_p,load_q,tap_controls,shunt_controls;normalize_controls,
            power_balance_slacks,scenario_prefix)
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
    reactive_assignments = nothing,
    sparse_balance::Bool = false,
)
    validate_case(case)
    isnothing(reactive_assignments) || validate_reactive_assignments(case, reactive_assignments)
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
        reactive_assignments = reactive_assignments,
        sparse_balance = sparse_balance,
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
