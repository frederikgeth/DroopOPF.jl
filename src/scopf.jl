"""Scenario-indexed SCOPF output; `:base` is always present. States may be missing after failure."""
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
end

function _add_response_constraints!(model, study, scenario, base, variables, prefix)
    delta = nothing
    if study.mode == :preventive
        alpha = _participation(study, scenario)
        initial_delta = sum(start_value(variables.pg[i]) -
            (base isa ACState ? base.pg[i] : start_value(base.pg[i]))
            for (i,g) in enumerate(scenario.generators) if g.available; init=0.0)
        delta = @variable(model, base_name = prefix * "balancing_power", start = initial_delta)
        for (i, g) in enumerate(scenario.generators)
            g.available || continue
            @constraint(model, variables.pg[i] == base.pg[i] + alpha[i] * delta)
        end
    end
    for (i, g) in enumerate(scenario.generators)
        g.available || continue
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
)
    study = _validated_study(study)
    encoding in (:smooth, :complementarity) || throw(ArgumentError("unknown control encoding"))
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
    if !isnothing(fixed_base_state)
        length(fixed_base_state.vm) == length(study.case.network.buses) &&
            length(fixed_base_state.va) == length(study.case.network.buses) &&
            length(fixed_base_state.pg) == length(study.case.generators) &&
            length(fixed_base_state.qg) == length(study.case.generators) ||
            throw(ArgumentError("fixed base state dimensions do not match the case"))
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
            for (i,g) in enumerate(case.generators)
                pg[i] = g.available ? clamp(pg[i] + alpha[i] * lost_p, g.p_min, g.p_max) : 0.0
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
        _, vars = if encoding == :smooth
            _build_acopf_model(case; voltage_epsilon=smooth_epsilon,
                reactive_relative_epsilon=smooth_reactive_relative_epsilon,
                reactive_epsilon=smooth_reactive_epsilon, silent=silent,
                shared_model=model, scenario_prefix=prefix, set_objective=(k == 1),
                initial_state=initial)
        else
            _build_complementarity_opf_model(case; silent=silent,
                shared_model=model, scenario_prefix=prefix, set_objective=(k == 1),
                initial_state=initial)
        end
        push!(variables, vars)
        if k > 1
            delta = _add_response_constraints!(model, study, case, variables[1], vars, prefix)
            isnothing(delta) || (deltas[id] = delta)
        end
    end
    for (key, value) in optimizer_attributes
        set_optimizer_attribute(model, key, value)
    end
    if length(ids) == 1 && !isnothing(fixed_base_state)
        return SCOPFResult(Dict{Symbol,Union{Nothing,ACState{Float64}}}(:base =>
            ACState(Float64.(fixed_base_state.vm),Float64.(fixed_base_state.va),
                    Float64.(fixed_base_state.pg),Float64.(fixed_base_state.qg))),
            Dict{Symbol,Float64}(), base_cost, :NOT_RUN, :NO_SOLUTION, study.mode,
            encoding, Float64(smooth_epsilon),Float64(smooth_reactive_relative_epsilon),
            isnothing(smooth_reactive_epsilon) ? nothing : Float64(smooth_reactive_epsilon),
            "Fixed base evaluation (no optimization)")
    end
    optimize!(model)
    states = Dict{Symbol,Union{Nothing,ACState{Float64}}}(id => nothing for id in ids)
    if !isnothing(fixed_base_state)
        states[:base] = ACState(Float64.(fixed_base_state.vm),Float64.(fixed_base_state.va),
            Float64.(fixed_base_state.pg),Float64.(fixed_base_state.qg))
    end
    balancing = Dict{Symbol,Float64}()
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
        end
        for (id, delta) in deltas
            balancing[id] = value(delta)
        end
    end
    return SCOPFResult(states, balancing, has_values(model) ? objective_value(model) : NaN,
        Symbol(string(termination_status(model))), Symbol(string(primal_status(model))),
        study.mode, encoding, Float64(smooth_epsilon), Float64(smooth_reactive_relative_epsilon),
        isnothing(smooth_reactive_epsilon) ? nothing : Float64(smooth_reactive_epsilon),
        solver_name(model))
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
