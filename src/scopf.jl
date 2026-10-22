"""Scenario-indexed SCOPF output; `:base` is always present. States may be missing
on failure. `balancing_power` stores the common active-response request signal;
after saturation it differs from total delivered adjustment and can be nonunique.
"""
struct SCOPFResult
    states::Dict{Symbol,Union{Nothing,ACState{Float64}}}
    balancing_power::Dict{Symbol,Float64}
    objective::Float64
    termination_status::Symbol
    primal_status::Symbol
    mode::Symbol
    encoding::Symbol
    smooth_epsilon::Float64
    smooth_reactive_relative_epsilon::Float64
    smooth_reactive_epsilon::Union{Nothing,Float64}
    solver::String
    reactive_assignments::Union{Nothing,Vector{ReactiveControlAssignment}}
    tap_settings::Dict{Symbol,Dict{Int,Float64}}
    shunt_settings::Dict{Symbol,Dict{Int,Float64}}
    tap_controls::Vector{TapControl}
    shunt_controls::Vector{ShuntControl}
    control_policy::SCOPFControlPolicy
end

# Compatibility for pre-M9 internal callers and schema readers.
SCOPFResult(states, balancing_power, objective, termination_status, primal_status,
    mode, encoding, smooth_epsilon, smooth_reactive_relative_epsilon,
    smooth_reactive_epsilon, solver, reactive_assignments) =
    SCOPFResult(states, balancing_power, objective, termination_status, primal_status,
        mode, encoding, smooth_epsilon, smooth_reactive_relative_epsilon,
        smooth_reactive_epsilon, solver, reactive_assignments,
        Dict{Symbol,Dict{Int,Float64}}(), Dict{Symbol,Dict{Int,Float64}}(),
        TapControl[], ShuntControl[],
        SCOPFControlPolicy(taps=:preventive, shunts=:preventive))

function _scenario_tap_controls(study::Study, case::Case)
    available = Set(b.id for b in case.network.branches if b.available)
    TapControl[c for c in study.tap_controls if c.branch_id in available]
end

function _couple_equipment_family!(model, timing, limits, base, scenario)
    for id in intersect(Set(keys(base)), Set(keys(scenario)))
        if timing == :preventive || (!isnothing(limits) && !haskey(limits, id))
            @constraint(model, scenario[id] == base[id])
        elseif !isnothing(limits)
            limit = limits[id]
            @constraint(model, -limit <= scenario[id] - base[id] <= limit)
        end
    end
end

function _couple_equipment!(model, policy, base_taps, base_shunts, scenario)
    _couple_equipment_family!(model, policy.taps, policy.tap_movement_limits,
        base_taps, scenario.taps)
    _couple_equipment_family!(model, policy.shunts, policy.shunt_movement_limits,
        base_shunts, scenario.shunts)
    nothing
end

function _add_response_constraints!(model, study, scenario, base, variables, prefix,
    encoding::Symbol=occursin("CCOpt", solver_name(model)) ? :complementarity : :smooth)
    delta = nothing
    if study.mode == :preventive
        if encoding == :complementarity && !get(model.ext,:limit_aware_response,false)
            # CCOpt has two independent relaxation floors. Keep both below
            # native convergence accuracy for the additional projection pairs.
            # Public optimizer_attributes are applied later and can override.
            set_optimizer_attribute(model,"sigma_min",1e-14)
            set_optimizer_attribute(model,"relaxation_update",
                CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14))
            model.ext[:limit_aware_response] = true
        end
        alpha = _participation(study, scenario)
        responding = count(i -> alpha[i] > 0 &&
            get(study.redispatch_limits,scenario.generators[i].id,Inf) > 0, eachindex(alpha))
        initial_delta = sum(start_value(variables.pg[i]) -
            (base isa ACState ? base.pg[i] : start_value(base.pg[i]))
            for (i,g) in enumerate(scenario.generators) if g.available; init=0.0)
        base_pg = base isa ACState ? base.pg : start_value.(base.pg)
        signal_start = _response_signal_start(study, scenario, base_pg, initial_delta)
        delta = @variable(model, base_name = prefix * "response_signal", start = signal_start)
        for (i, g) in enumerate(scenario.generators)
            g.available || continue
            if alpha[i] == 0 || get(study.redispatch_limits, g.id, Inf) == 0
                @constraint(model, variables.pg[i] == base.pg[i])
                continue
            end
            # With a single movable participant, select the canonical signal
            # whose request equals delivery. Bounds still enforce all limits;
            # this removes redundant saturated-signal representations only.
            if responding == 1
                @constraint(model, variables.pg[i] == base.pg[i]+alpha[i]*delta)
                continue
            end
            lo, hi = _active_response_bounds(scenario, i, study.reactive_assignments)
            if encoding == :complementarity
                pg_i, base_p = variables.pg[i], base.pg[i]
                # The nonnegative projection slacks enforce these same bounds.
                # Avoid duplicate variable-bound rows in the MPCC formulation.
                has_lower_bound(pg_i) && delete_lower_bound(pg_i)
                has_upper_bound(pg_i) && delete_upper_bound(pg_i)
                raw_start = base_pg[i] + alpha[i]*signal_start
                projected = clamp(raw_start, _response_bounds(study,scenario,i,base_pg[i])...)
                set_start_value(pg_i, projected)
                stationarity = @expression(model, pg_i-base_p-alpha[i]*delta)
                pairs = Tuple{Any,Float64}[(lo, -1.0), (hi, 1.0)]
                if haskey(study.redispatch_limits,g.id)
                    r = study.redispatch_limits[g.id]
                    append!(pairs, [(base_p-r,-1.0),(base_p+r,1.0)])
                end
                # Projection KKT: affine slacks and nonnegative multipliers.
                for (k,(bound,sign)) in enumerate(pairs)
                    bound_start = bound isa Real ? bound : start_value(base_p)+sign*study.redispatch_limits[g.id]
                    slack = @variable(model, lower_bound=0,
                        base_name=prefix*"p_slack_$(i)_$(k)",
                        start=max(0.0,sign*(bound_start-projected)))
                    multiplier = @variable(model, lower_bound=0,
                        base_name=prefix*"p_multiplier_$(i)_$(k)", start=0.0)
                    @constraint(model, slack == sign*(bound-pg_i))
                    @constraint(model, [slack,multiplier] in _COMPLEMENTARITY_MOI.Complements(2))
                    add_to_expression!(stationarity, sign, multiplier)
                end
                @constraint(model, stationarity == 0)
                continue
            end
            if haskey(study.redispatch_limits, g.id)
                r = study.redispatch_limits[g.id]
                base_p = base.pg[i]
                lower = @NLexpression(model, max(lo, base_p-r))
                upper = @NLexpression(model, min(hi, base_p+r))
            else
                lower, upper = lo, hi
            end
            # Exact piecewise projection: saturated participants stop moving,
            # while the common signal can continue driving the others.
            pg_i, base_p, weight = variables.pg[i], base.pg[i], alpha[i]
            @NLconstraint(model, pg_i == min(upper, max(lower, base_p + weight * delta)))
        end
    end
    for (i, g) in enumerate(scenario.generators)
        g.available || continue
        if study.mode == :preventive && encoding == :complementarity &&
            responding > 1 && alpha[i] > 0 && get(study.redispatch_limits,g.id,Inf) > 0
            continue # Any movement bounds are already projection KKT slacks.
        end
        if study.mode == :corrective || haskey(study.redispatch_limits, g.id)
            limit = get(study.redispatch_limits, g.id, 0.0)
            @constraint(model, -limit <= variables.pg[i] - base.pg[i] <= limit)
        end
    end
    return delta
end

"""
    solve_scopf(study; smooth_epsilon=1e-4, optimizer_factory=Ipopt.Optimizer, ...)

Solve the base and all listed contingencies jointly, minimizing the M1 base
schedule-deviation objective. Contingencies impose feasibility constraints and
have no additional cost. The fixed droop graph applies in every available unit.
`fixed_base_state` evaluates security of an existing equilibrium without changing it.
"""
function solve_scopf(study::Study;
    smooth_epsilon::Real = 1.0e-4,
    smooth_reactive_relative_epsilon::Real = smooth_epsilon,
    smooth_reactive_epsilon::Union{Nothing,Real} = nothing,
    encoding::Symbol = :smooth,
    optimizer_factory = Ipopt.Optimizer,
    optimizer_attributes::AbstractDict = Dict{String,Any}(),
    silent::Bool = true,
    initial_states::AbstractDict = Dict(),
    fixed_base_state::Union{Nothing,ACState} = nothing,
    fixed_base_tap_settings::AbstractDict = Dict{Int,Float64}(),
    fixed_base_shunt_settings::AbstractDict = Dict{Int,Float64}(),
    _model_hook::Union{Nothing,Function} = nothing,
    _optimizer_lock::Union{Nothing,ReentrantLock} = nothing,
    _phase1_power_balance::Bool = false,
    _droop_parameter_builder::Union{Nothing,Function} = nothing,
    sparse_balance::Bool = false,
)
    study = _validated_study(study)
    encoding in (:smooth, :complementarity) || throw(ArgumentError("unknown control encoding"))
    sparse_balance && encoding != :smooth &&
        throw(ArgumentError("sparse_balance is currently a smooth-builder option"))
    all(x -> isfinite(x) && x > 0, (smooth_epsilon, smooth_reactive_relative_epsilon)) ||
        throw(ArgumentError("smoothing widths must be positive and finite"))
    isnothing(smooth_reactive_epsilon) ||
        (isfinite(smooth_reactive_epsilon) && smooth_reactive_epsilon > 0) ||
        throw(ArgumentError("reactive smoothing width must be positive and finite"))
    ids = [:base; [c.id for c in study.contingencies]]
    all(id in ids for id in keys(initial_states)) || throw(ArgumentError("unknown initial scenario"))
    cases = [study.case; [scenario_case(study.case, c) for c in study.contingencies]]
    if encoding == :complementarity
        optimizer_factory === Ipopt.Optimizer ||
            throw(ArgumentError("complementarity uses CCOpt; omit optimizer_factory"))
        model = Model(CCOpt.Optimizer)
        MathOptComplements.Bridges.add_all_bridges(model)
    else
        model = Model(optimizer_factory)
    end
    silent && set_silent(model)
    if !isnothing(_droop_parameter_builder)
        encoding == :smooth && isnothing(fixed_base_state) && !_phase1_power_balance ||
            throw(ArgumentError("shared droop design requires a smooth, unfixed SCOPF"))
    end
    droop_parameters = isnothing(_droop_parameter_builder) ? Dict() :
        _droop_parameter_builder(model)
    fixed_taps = Dict{Int,Float64}(fixed_base_tap_settings)
    fixed_shunts = Dict{Int,Float64}(fixed_base_shunt_settings)
    if isnothing(fixed_base_state)
        isempty(fixed_taps) && isempty(fixed_shunts) ||
            throw(ArgumentError("fixed equipment settings require fixed_base_state"))
    else
        length(fixed_base_state.vm) == length(study.case.network.buses) &&
            length(fixed_base_state.va) == length(study.case.network.buses) &&
            length(fixed_base_state.pg) == length(study.case.generators) &&
            length(fixed_base_state.qg) == length(study.case.generators) ||
            throw(ArgumentError("fixed base state dimensions do not match the case"))
        Set(keys(fixed_taps)) == Set(c.branch_id for c in study.tap_controls) ||
            throw(ArgumentError("fixed base tap settings must match selected controls"))
        Set(keys(fixed_shunts)) == Set(c.bank_id for c in study.shunt_controls) ||
            throw(ArgumentError("fixed base shunt settings must match selected controls"))
        for control in study.tap_controls
            value = fixed_taps[control.branch_id]
            isfinite(value) && control.lower <= value <= control.upper ||
                throw(ArgumentError("fixed base tap setting lies outside its policy"))
        end
        for control in study.shunt_controls
            value = fixed_shunts[control.bank_id]
            policy = _shunt_policy(study.case, control)
            isfinite(value) && policy.lower <= value <= policy.upper ||
                throw(ArgumentError("fixed base shunt setting lies outside its policy"))
        end
    end
    base_cost = 0.0
    variables = []
    deltas = Dict{Symbol,VariableRef}()
    for (k, (id, case)) in enumerate(zip(ids, cases))
        initial = id == :base && !isnothing(fixed_base_state) ? fixed_base_state :
            get(initial_states, id, nothing)
        if k > 1 && isnothing(initial) && !isnothing(fixed_base_state)
            pg, qg = copy(fixed_base_state.pg), copy(fixed_base_state.qg)
            lost_p = sum(pg[i] for (i,g) in enumerate(case.generators) if !g.available; init=0.0)
            alpha = study.mode == :preventive ? _participation(study, case) :
                [g.available ? 1.0 / count(g -> g.available, case.generators) : 0.0 for g in case.generators]
            signal = study.mode == :preventive ? _response_signal_start(study, case, pg, lost_p) : lost_p
            for (i,g) in enumerate(case.generators)
                lo, hi = _response_bounds(study, case, i, pg[i])
                pg[i] = g.available ? (alpha[i] > 0 ? clamp(pg[i] + alpha[i] * signal, lo, hi) : pg[i]) : 0.0
                g.available || (qg[i] = 0.0)
            end
            initial = ACState(fixed_base_state.vm,fixed_base_state.va,pg,qg)
        end
        prefix = "scenario_$(k)_"
        if k == 1 && !isnothing(fixed_base_state)
            # The base is data during evaluation: do not add redundant fixed-base
            # physics equations to the NLP. The independent report checks it.
            push!(variables, fixed_base_state)
            base_cost = sum((fixed_base_state.pg[i] - g.initial_p)^2 +
                1e-3 * (fixed_base_state.qg[i] - g.initial_q)^2
                for (i,g) in enumerate(case.generators))
            @objective(model, Min, base_cost)
            continue
        end
        scenario_taps = _scenario_tap_controls(study, case)
        tap_arg = isempty(scenario_taps) ? nothing : scenario_taps
        shunt_arg = isempty(study.shunt_controls) ? nothing : study.shunt_controls
        _, vars = if encoding == :smooth
            _build_acopf_model(case; voltage_epsilon=smooth_epsilon,
                reactive_relative_epsilon=smooth_reactive_relative_epsilon,
                reactive_epsilon=smooth_reactive_epsilon, silent=silent,
                shared_model=model, scenario_prefix=prefix, set_objective=(k == 1),
                initial_state=initial, reactive_assignments=study.reactive_assignments,
                tap_controls=tap_arg, shunt_controls=shunt_arg,
                droop_parameter_variables=droop_parameters, sparse_balance,
                power_balance_slacks=_phase1_power_balance)
        else
            _build_complementarity_opf_model(case; silent=silent,
                shared_model=model, scenario_prefix=prefix, set_objective=(k == 1),
                initial_state=initial, reactive_assignments=study.reactive_assignments,
                tap_controls=tap_arg, shunt_controls=shunt_arg,
                power_balance_slacks=_phase1_power_balance)
        end
        push!(variables, vars)
        if k > 1
            delta = _add_response_constraints!(model, study, case, variables[1], vars, prefix, encoding)
            isnothing(delta) || (deltas[id] = delta)
            base_taps = isnothing(fixed_base_state) ? variables[1].taps : fixed_taps
            base_shunts = isnothing(fixed_base_state) ? variables[1].shunts : fixed_shunts
            _couple_equipment!(model, study.control_policy,
                base_taps, base_shunts, vars)
        end
    end
    if _phase1_power_balance
        slacks=model.ext[:power_balance_slacks]
        isempty(slacks) && throw(ArgumentError("Phase-I requires optimized scenarios"))
        @objective(model,Min,sum(slacks))
    end
    for (key, value) in optimizer_attributes
        set_optimizer_attribute(model, key, value)
    end
    isnothing(_model_hook) || _model_hook(model)
    if length(ids) == 1 && !isnothing(fixed_base_state)
        tap_settings = Dict{Symbol,Dict{Int,Float64}}(:base => copy(fixed_taps))
        shunt_settings = Dict{Symbol,Dict{Int,Float64}}(:base => copy(fixed_shunts))
        return SCOPFResult(Dict{Symbol,Union{Nothing,ACState{Float64}}}(:base =>
            ACState(Float64.(fixed_base_state.vm),Float64.(fixed_base_state.va),
                    Float64.(fixed_base_state.pg),Float64.(fixed_base_state.qg))),
            Dict{Symbol,Float64}(), base_cost, :NOT_RUN, :NO_SOLUTION, study.mode,
            encoding, Float64(smooth_epsilon),Float64(smooth_reactive_relative_epsilon),
            isnothing(smooth_reactive_epsilon) ? nothing : Float64(smooth_reactive_epsilon),
            "Fixed base evaluation (no optimization)", study.reactive_assignments,
            tap_settings, shunt_settings, copy(study.tap_controls),
            copy(study.shunt_controls), study.control_policy)
    end
    if isnothing(_optimizer_lock)
        optimize!(model)
    else
        lock(_optimizer_lock) do
            optimize!(model)
        end
    end
    states = Dict{Symbol,Union{Nothing,ACState{Float64}}}(id => nothing for id in ids)
    if !isnothing(fixed_base_state)
        states[:base] = ACState(Float64.(fixed_base_state.vm),Float64.(fixed_base_state.va),
            Float64.(fixed_base_state.pg),Float64.(fixed_base_state.qg))
    end
    balancing = Dict{Symbol,Float64}()
    tap_settings = Dict{Symbol,Dict{Int,Float64}}(id => Dict{Int,Float64}() for id in ids)
    shunt_settings = Dict{Symbol,Dict{Int,Float64}}(id => Dict{Int,Float64}() for id in ids)
    if !isnothing(fixed_base_state)
        tap_settings[:base] = copy(fixed_taps)
        shunt_settings[:base] = copy(fixed_shunts)
    end
    if has_values(model)
        for (id, vars) in zip(ids, variables)
            if id == :base && !isnothing(fixed_base_state)
                states[id] = ACState(Float64.(vars.vm),Float64.(vars.va),Float64.(vars.pg),Float64.(vars.qg))
                continue
            end
            values = [value.(getproperty(vars, field)) for field in (:vm, :va, :pg, :qg)]
            if all(v -> all(isfinite, v), values) && all(>(0), values[1])
                states[id] = ACState(values...)
            end
            tap_settings[id] = Dict(device_id => Float64(value(x)) for
                (device_id, x) in vars.taps)
            shunt_settings[id] = Dict(device_id => Float64(value(x)) for
                (device_id, x) in vars.shunts)
        end
        for (id, delta) in deltas
            balancing[id] = value(delta)
        end
    end
    return SCOPFResult(states, balancing, has_values(model) ? objective_value(model) : NaN,
        Symbol(string(termination_status(model))), Symbol(string(primal_status(model))),
        study.mode, encoding, Float64(smooth_epsilon), Float64(smooth_reactive_relative_epsilon),
        isnothing(smooth_reactive_epsilon) ? nothing : Float64(smooth_reactive_epsilon),
        solver_name(model), study.reactive_assignments, tap_settings, shunt_settings,
        copy(study.tap_controls), copy(study.shunt_controls), study.control_policy)
end

solve(study::Study; kwargs...) = solve_scopf(study; kwargs...)

"""Evaluate all contingencies while holding the supplied base equilibrium fixed."""
evaluate_contingencies(study::Study, state::ACState; kwargs...) =
    solve_scopf(study; fixed_base_state=state, kwargs...)

"""Solve successive smoothing widths, warm-starting all scenarios; stop on solver failure."""
function solve_scopf_continuation(study::Study;
    smooth_epsilons::AbstractVector{<:Real} = [1e-2, 1e-3, 1e-4], kwargs...)
    !isempty(smooth_epsilons) && all(x -> isfinite(x) && x > 0, smooth_epsilons) ||
        throw(ArgumentError("smooth_epsilons must be nonempty, positive, and finite"))
    results = SCOPFResult[]
    initial = Dict{Symbol,ACState{Float64}}()
    for epsilon in smooth_epsilons
        result = solve_scopf(study; smooth_epsilon=epsilon, initial_states=initial, kwargs...)
        push!(results, result)
        result.termination_status in (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED, :OPTIMAL, :ALMOST_OPTIMAL) || break
        any(isnothing, values(result.states)) && break
        initial = Dict(id => state for (id, state) in result.states)
    end
    return results
end
