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

function _complementarity_residual(variables)
    maximum(abs, vcat(
        value.(variables.voltage_lower) .* value.(variables.voltage_lower_complement),
        value.(variables.voltage_upper) .* value.(variables.voltage_upper_complement),
        value.(variables.q_lower_slack) .* value.(variables.q_lower_multiplier),
        value.(variables.q_upper_slack) .* value.(variables.q_upper_multiplier)); init=0.0)
end

"""Read final CCOpt/MadNLP relaxation diagnostics from a solved JuMP model.

The iteration count is the cumulative inner MadNLP count exposed by CCOpt. The
package does not currently expose a separate outer-homotopy iteration count.
These are final relaxed-NLP metrics, not an original-MPCC stationarity proof.
"""
function ccopt_diagnostics(model::Model)
    backend = unsafe_backend(model)
    string(_COMPLEMENTARITY_MOI.get(backend,_COMPLEMENTARITY_MOI.SolverName())) == "CCOpt" ||
        throw(ArgumentError("model is not backed by CCOpt"))
    isnothing(backend.stats) && throw(ArgumentError("CCOpt model has not been solved"))
    stats,solver=backend.stats,backend.solver
    sigma=solver.rnlp.σ
    Dict{String,Any}(
        "backend"=>"CCOpt",
        "status"=>string(stats.status),
        "inner_iterations"=>stats.iter,
        "outer_iterations"=>nothing,
        "outer_iterations_available"=>false,
        "primal_feasibility"=>stats.primal_feas,
        "dual_feasibility"=>stats.dual_feas,
        "complementarity_feasibility"=>stats.inf_pr_cc,
        "relaxation_min"=>isempty(sigma) ? nothing : minimum(sigma),
        "relaxation_max"=>isempty(sigma) ? nothing : maximum(sigma),
        "complementarity_pairs"=>length(sigma),
        "solve_time_seconds"=>stats.counters.solve_time,
        "solver_time_seconds"=>stats.counters.solver_time,
        "total_time_seconds"=>stats.counters.total_time,
        "variables"=>num_variables(model),
        "constraints"=>num_constraints(model;count_variable_in_set_constraints=true),
        "stationarity_scope"=>"final relaxed NLP; not an original-MPCC stationarity certificate",
    )
end

_ccopt_audit_value(x::Number)=Float64(x)
_ccopt_audit_value(x)=Float64(value(x))

"""Compare CCOpt's solved auxiliary MPCC variables with direct exact-droop evaluation.

This is a read-only diagnostic for distinguishing a relaxed-complementarity
iterate from an extraction/model-bridge discrepancy. It does not change the
model, stopping rules, or physical acceptance criteria.
"""
function ccopt_encoding_audit(model::Model)
    variables=get(model.ext,:ccopt_complementarity_variables,nothing)
    metadata=get(model.ext,:ccopt_complementarity_droop_metadata,nothing)
    isnothing(variables) && throw(ArgumentError("model has no retained CCOpt complementarity variables"))
    isnothing(metadata) && throw(ArgumentError("model has no retained CCOpt droop metadata"))
    has_values(model) || throw(ArgumentError("CCOpt model has no solution values"))
    rows=Dict{String,Any}[]
    for (k,entry) in enumerate(metadata)
        v=value(variables.vm[entry.bus_index]);q=value(variables.qg[entry.generator_index])
        slope=_ccopt_audit_value(entry.slope);vref=_ccopt_audit_value(entry.v_ref)
        low=_ccopt_audit_value(entry.deadband_low);high=_ccopt_audit_value(entry.deadband_high)
        lower_direct=max(vref-low-v,0.);upper_direct=max(v-vref-high,0.)
        raw_direct=entry.q_at_deadband+(lower_direct-upper_direct)/slope
        physical=clamp(raw_direct,entry.q_min,entry.q_max)
        lower_aux=value(variables.voltage_lower[k]);upper_aux=value(variables.voltage_upper[k])
        raw_aux=value(variables.raw_q[k])
        projection_aux=clamp(raw_aux,entry.q_min,entry.q_max)
        push!(rows,Dict{String,Any}(
            "generator_id"=>entry.generator_id,"control_id"=>entry.control_id,
            "regulated_bus_id"=>entry.bus_id,"voltage_pu"=>v,
            "lower_hinge_error_pu"=>abs(lower_aux-lower_direct),
            "upper_hinge_error_pu"=>abs(upper_aux-upper_direct),
            "raw_droop_error_pu"=>abs(raw_aux-raw_direct),
            "projection_error_pu"=>abs(q-projection_aux),
            "exact_droop_error_pu"=>abs(q-physical),
            "raw_q_aux_pu"=>raw_aux,"raw_q_direct_pu"=>raw_direct,
            "qg_pu"=>q,"exact_qg_pu"=>physical))
    end
    sort!(rows;by=row->-row["exact_droop_error_pu"])
    maximum_field(field)=isempty(rows) ? 0. : maximum(row[field] for row in rows)
    Dict{String,Any}("controllers"=>rows,
        "max_lower_hinge_error_pu"=>maximum_field("lower_hinge_error_pu"),
        "max_upper_hinge_error_pu"=>maximum_field("upper_hinge_error_pu"),
        "max_raw_droop_error_pu"=>maximum_field("raw_droop_error_pu"),
        "max_projection_error_pu"=>maximum_field("projection_error_pu"),
        "max_exact_droop_error_pu"=>maximum_field("exact_droop_error_pu"),
        "worst"=>isempty(rows) ? nothing : first(rows))
end

function _add_complementarity_ac_physics!(
    model,
    case::Case,
    vm,
    va,
    pg,
    qg,
    tap_controls = nothing,
    shunt_controls = nothing;
    normalize_controls::Bool = false,
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
    if !isnothing(tap_controls)
        return _add_tap_network!(model, case, vm, va, pg, qg,
            generators_at_bus, load_p, load_q, tap_controls, shunt_controls;
            normalize_controls)
    end

    Y = _admittance_matrix(network)
    shunts = isnothing(shunt_controls) ? Dict{Int,VariableRef}() :
        _shunt_variables!(model, case, shunt_controls, Y; normalize_controls)
    conductance_matrix = real.(Y)
    susceptance_matrix = imag.(Y)

    for i in 1:nbus
        p_generation = sum(pg[k] for k in generators_at_bus[i]; init = 0.0)
        q_generation = sum(qg[k] for k in generators_at_bus[i]; init = 0.0)
        selected = [b for b in network.banks if haskey(shunts, b.id) &&
            bus_indices[b.bus_id] == i]
        variable_g = sum((only(b.step_conductances) / only(b.step_susceptances)) *
            shunts[b.id] for b in selected; init = 0.0)
        variable_b = sum(shunts[b.id] for b in selected; init = 0.0)
        @NLconstraint(
            model,
            p_generation - load_p[i] - variable_g * vm[i]^2 ==
            vm[i] * sum(
                vm[j] * (conductance_matrix[i, j] * cos(va[i] - va[j]) +
                         susceptance_matrix[i, j] * sin(va[i] - va[j])) for j in 1:nbus
            ),
        )
        @NLconstraint(
            model,
            q_generation - load_q[i] + variable_b * vm[i]^2 ==
            vm[i] * sum(
                vm[j] * (conductance_matrix[i, j] * sin(va[i] - va[j]) -
                         susceptance_matrix[i, j] * cos(va[i] - va[j])) for j in 1:nbus
            ),
        )
    end

    _add_branch_thermal_limits!(model, network, vm, va)

    return Dict{Int,VariableRef}(), shunts
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
    shared_model::Union{Nothing,Model} = nothing,
    scenario_prefix::String = "",
    set_objective::Bool = true,
    tap_controls = nothing,
    shunt_controls = nothing,
    normalize_controls::Bool = false,
    droop_parameter_variables::AbstractDict = Dict(),
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

    model = isnothing(shared_model) ? Model(CCOpt.Optimizer) : shared_model
    # This must be called before adding complementarity constraints so JuMP can
    # route them to CCOpt's MOI wrapper.
    isnothing(shared_model) && MathOptComplements.Bridges.add_all_bridges(model)
    silent && set_silent(model)
    vm = @variable(model, [1:nbus], base_name = scenario_prefix * "vm")
    va = @variable(model, [1:nbus], base_name = scenario_prefix * "va")
    pg = @variable(model, [1:ngen], base_name = scenario_prefix * "pg")
    qg = @variable(model, [1:ngen], base_name = scenario_prefix * "qg")

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

    taps, shunts = _add_complementarity_ac_physics!(model, case, vm, va, pg, qg,
        tap_controls, shunt_controls; normalize_controls)

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
    audit_metadata=Any[]
    voltage_lower = @variable(model, [1:ncontrol], lower_bound = 0, base_name = scenario_prefix * "voltage_lower")
    voltage_lower_complement = @variable(model, [1:ncontrol], lower_bound = 0, base_name = scenario_prefix * "voltage_lower_complement")
    voltage_upper = @variable(model, [1:ncontrol], lower_bound = 0, base_name = scenario_prefix * "voltage_upper")
    voltage_upper_complement = @variable(model, [1:ncontrol], lower_bound = 0, base_name = scenario_prefix * "voltage_upper_complement")
    raw_q = @variable(model, [1:ncontrol], base_name = scenario_prefix * "raw_q")
    q_lower_slack = @variable(model, [1:ncontrol], lower_bound = 0, base_name = scenario_prefix * "q_lower_slack")
    q_lower_multiplier = @variable(model, [1:ncontrol], lower_bound = 0, base_name = scenario_prefix * "q_lower_multiplier")
    q_upper_slack = @variable(model, [1:ncontrol], lower_bound = 0, base_name = scenario_prefix * "q_upper_slack")
    q_upper_multiplier = @variable(model, [1:ncontrol], lower_bound = 0, base_name = scenario_prefix * "q_upper_multiplier")

    for (k, (_, generator_index, location_index)) in enumerate(active_attachments)
        attachment = active_attachments[k][1]
        generator = case.generators[generator_index]
        control = case.controls[attachment.control_id]
        schedule = control.schedule
        q_min, q_max = control.capability.q_min, control.capability.q_max
        parameters = get(droop_parameter_variables, attachment.control_id, nothing)
        slope = isnothing(parameters) ? control.slope : parameters.slope
        v_ref = isnothing(parameters) ? schedule.v_ref : parameters.v_ref
        deadband_low = isnothing(parameters) ? schedule.v_ref - schedule.v_db_low :
            parameters.deadband_low
        deadband_high = isnothing(parameters) ? schedule.v_db_high - schedule.v_ref :
            parameters.deadband_high
        initial = if isnothing(parameters)
            DroopSettings(control)
        else
            DroopSettings(
                _droop_parameter_start(parameters.slope, control.slope),
                _droop_parameter_start(parameters.v_ref, schedule.v_ref),
                _droop_parameter_start(parameters.deadband_low,
                    schedule.v_ref - schedule.v_db_low),
                _droop_parameter_start(parameters.deadband_high,
                    schedule.v_db_high - schedule.v_ref),
            )
        end
        v_db_low = v_ref - deadband_low
        v_db_high = v_ref + deadband_high
        push!(audit_metadata,(generator_id=generator.id,control_id=attachment.control_id,
            bus_id=attachment.location.bus_id,generator_index=generator_index,
            bus_index=location_index,q_min=q_min,q_max=q_max,
            q_at_deadband=control.q_at_deadband,slope=slope,v_ref=v_ref,
            deadband_low=deadband_low,deadband_high=deadband_high))

        voltage_start = isnothing(initial_state) ? 1.0 : initial_state.vm[location_index]
        voltage_lower_start = max(initial.v_ref - initial.deadband_low - voltage_start, 0.0)
        voltage_upper_start = max(voltage_start - initial.v_ref - initial.deadband_high, 0.0)
        raw_q_start = control.q_at_deadband +
            (voltage_lower_start - voltage_upper_start) / initial.slope
        q_start = clamp(raw_q_start, q_min, q_max)
        set_start_value(vm[location_index], voltage_start)
        set_start_value(qg[generator_index], q_start)
        set_start_value(voltage_lower[k], voltage_lower_start)
        set_start_value(voltage_lower_complement[k],
            max(voltage_start - initial.v_ref + initial.deadband_low, 0.0))
        set_start_value(voltage_upper[k], voltage_upper_start)
        set_start_value(voltage_upper_complement[k],
            max(initial.v_ref + initial.deadband_high - voltage_start, 0.0))
        set_start_value(raw_q[k], raw_q_start)
        set_start_value(q_lower_slack[k], q_start - q_min)
        set_start_value(q_upper_slack[k], q_max - q_start)
        set_start_value(q_lower_multiplier[k], max(q_start - raw_q_start, 0.0))
        set_start_value(q_upper_multiplier[k], max(raw_q_start - q_start, 0.0))

        # max(v_db_low - V, 0)
        @constraint(
            model,
            voltage_lower_complement[k] - voltage_lower[k] +
            v_db_low - vm[location_index] == 0,
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
            vm[location_index] - v_db_high == 0,
        )
        @constraint(
            model,
            [voltage_upper[k], voltage_upper_complement[k]] in
            _COMPLEMENTARITY_MOI.Complements(2),
        )

        @NLconstraint(
            model,
            raw_q[k] == control.q_at_deadband +
                        (voltage_lower[k] - voltage_upper[k]) / slope,
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

    if set_objective
        @objective(
            model,
            Min,
            sum((pg[i] - case.generators[i].initial_p)^2 +
                1.0e-3 * (qg[i] - case.generators[i].initial_q)^2 for i in 1:ngen),
        )
    end
    variables=(vm = vm, va = va, pg = pg, qg = qg, taps = taps, shunts = shunts,
                   voltage_lower = voltage_lower,
                   voltage_lower_complement = voltage_lower_complement,
                   voltage_upper = voltage_upper,
                   voltage_upper_complement = voltage_upper_complement,
                   raw_q = raw_q,
                   q_lower_slack = q_lower_slack,
                   q_lower_multiplier = q_lower_multiplier,
                   q_upper_slack = q_upper_slack,
                   q_upper_multiplier = q_upper_multiplier)
    model.ext[:ccopt_complementarity_variables]=variables
    model.ext[:ccopt_complementarity_droop_metadata]=audit_metadata
    return model,variables
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
    complementarity_residual = _complementarity_residual(variables)
    return ComplementarityOPFResult{Float64}(
        state,
        objective_value(model),
        termination,
        primal,
        complementarity_residual,
    )
end
