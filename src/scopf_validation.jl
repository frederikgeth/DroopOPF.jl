"""Independent per-scenario physical and inter-scenario response checks."""
struct SCOPFReport
    case_id::String
    valid::Bool
    physical_valid::Bool
    encoded_physical_valid::Bool
    termination_status::Symbol
    primal_status::Symbol
    objective::Float64
    mode::Symbol
    encoding::Symbol
    solver::String
    scenario_ids::Vector{Symbol}
    scenarios::Dict{Symbol,EquilibriumValidationReport{Float64}}
    coupling_violation::Dict{Symbol,Float64}
    equipment_coupling_violation::Dict{Symbol,Float64}
    encoded_droop_residual::Dict{Symbol,Float64}
    violations::Dict{Symbol,Vector{Symbol}}
    tolerances::NamedTuple
end

"""
    validate_equilibrium(study, result; coupling_tolerance=1e-6, ...)

Rebuild each outage independently and check AC physics, exact droop replay,
availability, and coupling to the base dispatch. Missing scenarios and states
produce invalid reports. `physical_valid` is separate from solver success.
"""
function validate_equilibrium(study::Study, result::SCOPFResult;
    coupling_tolerance::Real = 1e-6, power_tolerance::Real = 1e-6,
    droop_tolerance::Real = 1e-5, limit_tolerance::Real = 1e-6,
    unavailable_tolerance::Real = 1e-8,
)
    study = _validated_study(study)
    all(x -> isfinite(x) && x >= 0,
        (coupling_tolerance, power_tolerance, droop_tolerance, limit_tolerance, unavailable_tolerance)) ||
        throw(ArgumentError("validation tolerances must be finite and nonnegative"))
    ids = [:base; [c.id for c in study.contingencies]]
    cases = [study.case; [scenario_case(study.case, c) for c in study.contingencies]]
    reports = Dict{Symbol,EquilibriumValidationReport{Float64}}()
    coupling = Dict{Symbol,Float64}()
    equipment_coupling = Dict{Symbol,Float64}()
    encoded_droop = Dict{Symbol,Float64}()
    violations = Dict(id => Symbol[] for id in ids)
    result.encoding in (:smooth,:complementarity) || push!(violations[:base], :unknown_encoding)
    result.mode == study.mode || push!(violations[:base], :response_mode_mismatch)
    _json_data(result.reactive_assignments) == _json_data(study.reactive_assignments) ||
        push!(violations[:base], :reactive_assignments_mismatch)
    _json_data(result.tap_controls) == _json_data(study.tap_controls) ||
        push!(violations[:base], :tap_controls_mismatch)
    _json_data(result.shunt_controls) == _json_data(study.shunt_controls) ||
        push!(violations[:base], :shunt_controls_mismatch)
    result.control_policy == study.control_policy ||
        push!(violations[:base], :control_policy_mismatch)
    Set(keys(result.states)) == Set(ids) || push!(violations[:base], :scenario_set_mismatch)
    base = get(result.states, :base, nothing)
    base_taps = get(result.tap_settings, :base, Dict{Int,Float64}())
    base_shunts = get(result.shunt_settings, :base, Dict{Int,Float64}())
    for (id, case) in zip(ids, cases)
        state = get(result.states, id, nothing)
        if isnothing(state)
            push!(violations[id], :missing_state)
            continue
        end
        if length(state.vm) != length(case.network.buses) || length(state.va) != length(case.network.buses) ||
           length(state.pg) != length(case.generators) || length(state.qg) != length(case.generators)
            push!(violations[id], :state_dimension)
            continue
        end
        # State vectors are mutable even though ACState itself is immutable.
        if !all(isfinite, vcat(state.vm, state.va, state.pg, state.qg)) || !all(>(0), state.vm)
            push!(violations[id], :nonfinite_or_invalid_state)
            continue
        end
        taps = get(result.tap_settings, id, Dict{Int,Float64}())
        shunts = get(result.shunt_settings, id, Dict{Int,Float64}())
        expected_taps = Set(c.branch_id for c in _scenario_tap_controls(study, case))
        expected_shunts = Set(c.bank_id for c in study.shunt_controls)
        if Set(keys(taps)) != expected_taps
            push!(violations[id], :tap_settings)
        end
        if Set(keys(shunts)) != expected_shunts
            push!(violations[id], :shunt_settings)
        end
        for control in study.tap_controls
            control.branch_id in expected_taps || continue
            setting = get(taps, control.branch_id, NaN)
            isfinite(setting) &&
                control.lower-limit_tolerance <= setting <= control.upper+limit_tolerance ||
                push!(violations[id], :tap_settings)
        end
        for control in study.shunt_controls
            setting = get(shunts, control.bank_id, NaN)
            policy = _shunt_policy(case, control)
            isfinite(setting) &&
                policy.lower-limit_tolerance <= setting <= policy.upper+limit_tolerance ||
                push!(violations[id], :shunt_settings)
        end
        physical_case = case
        if Set(keys(taps)) == expected_taps &&
           all(isfinite, values(taps)) && Set(keys(shunts)) == expected_shunts &&
           all(isfinite, values(shunts))
            physical_case = with_shunt_settings(with_tap_settings(case, taps), shunts)
        end
        report = validate_equilibrium(physical_case, state;
            power_tolerance=power_tolerance, droop_tolerance=droop_tolerance,
            limit_tolerance=limit_tolerance, unavailable_tolerance=unavailable_tolerance,
            smooth_epsilon=result.encoding == :smooth ? result.smooth_epsilon : nothing,
            smooth_reactive_relative_epsilon=result.encoding == :smooth ? result.smooth_reactive_relative_epsilon : nothing,
            smooth_reactive_epsilon=result.encoding == :smooth ? result.smooth_reactive_epsilon : nothing,
            reactive_assignments=study.reactive_assignments)
        encoded_droop[id] = report.droop_residual_max
        if result.encoding == :smooth
            encoded_droop[id] = 0.0
            bus_indices = _bus_indices(case.network)
            generator_indices = Dict(g.id=>i for (i,g) in enumerate(case.generators))
            droop_entries = isnothing(study.reactive_assignments) ?
                [(generator_id=a.generator_id, location=a.location,
                    control=case.controls[a.control_id]) for a in case.attachments] :
                [(generator_id=a.generator_id, location=a.location, control=a.mode)
                    for a in study.reactive_assignments if a.mode isa VoltVarDroop]
            for attachment in droop_entries
                i = generator_indices[attachment.generator_id]
                case.generators[i].available || continue
                control = attachment.control
                epsilon_q = reactive_smoothing_epsilon(control,result.smooth_reactive_relative_epsilon;
                    absolute_epsilon=result.smooth_reactive_epsilon)
                expected = _smooth_capability_droop_value(control,state.vm[bus_indices[attachment.location.bus_id]],
                    state.pg[i],case.generators[i],result.smooth_epsilon,epsilon_q)
                encoded_droop[id] = max(encoded_droop[id],abs(state.qg[i]-expected))
            end
        end
        reports[id] = report
        append!(violations[id], report.violations)
        reference = findfirst(b -> b.reference, case.network.buses)
        abs(state.va[reference]) <= coupling_tolerance || push!(violations[id], :reference_angle)
        id == :base && continue
        if isnothing(base) || length(base.pg) != length(case.generators)
            push!(violations[id], :missing_base_state)
            continue
        end
        violation = 0.0
        alpha = study.mode == :preventive ? _participation(study, case) : Float64[]
        delta = get(result.balancing_power, id, NaN)
        if study.mode == :preventive && !isfinite(delta)
            push!(violations[id], :missing_balancing_power)
            violation = Inf
        end
        for (i, generator) in enumerate(case.generators)
            generator.available || continue
            change = state.pg[i] - base.pg[i]
            if study.mode == :preventive && isfinite(delta)
                # Replay the exact bounded law, independently of the NLP graph.
                lo, hi = _active_response_bounds(case, i, study.reactive_assignments)
                if haskey(study.redispatch_limits, generator.id)
                    r = study.redispatch_limits[generator.id]
                    lo, hi = max(lo, base.pg[i]-r), min(hi, base.pg[i]+r)
                end
                expected = alpha[i] == 0 ? base.pg[i] :
                    clamp(base.pg[i] + alpha[i]*delta, lo, hi)
                violation = max(violation, abs(state.pg[i] - expected))
            end
            if study.mode == :corrective || haskey(study.redispatch_limits, generator.id)
                violation = max(violation, abs(change) - get(study.redispatch_limits, generator.id, 0.0))
            end
        end
        coupling[id] = violation
        violation <= coupling_tolerance || push!(violations[id], :active_power_response)
        equipment_violation = 0.0
        for (timing, limits, base_settings, settings, expected) in (
            (study.control_policy.taps, study.control_policy.tap_movement_limits,
                base_taps, taps, expected_taps),
            (study.control_policy.shunts, study.control_policy.shunt_movement_limits,
                base_shunts, shunts, expected_shunts))
            for device_id in intersect(Set(keys(base_settings)), expected)
                movement = abs(get(settings, device_id, NaN) - base_settings[device_id])
                allowed = timing == :preventive ? 0.0 :
                    isnothing(limits) ? Inf : get(limits, device_id, 0.0)
                equipment_violation = max(equipment_violation, movement - allowed)
            end
        end
        equipment_coupling[id] = equipment_violation
        equipment_violation <= coupling_tolerance ||
            push!(violations[id], :equipment_response)
    end
    physical_valid = all(isempty, values(violations))
    encoded_valid = all(id -> all(v -> v == :droop, violations[id]) &&
        get(encoded_droop,id,Inf) <= droop_tolerance, ids)
    solver_success = result.termination_status in
        (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED, :OPTIMAL, :ALMOST_OPTIMAL) ||
        (result.termination_status == :NOT_RUN && isempty(study.contingencies))
    tolerances = (; power_tolerance, droop_tolerance, limit_tolerance, unavailable_tolerance, coupling_tolerance)
    return SCOPFReport(study.case.id, physical_valid && solver_success, physical_valid, encoded_valid,
        result.termination_status, result.primal_status, result.objective, study.mode,
        result.encoding, result.solver, ids, reports, coupling, equipment_coupling,
        encoded_droop, violations, tolerances)
end

equilibrium_report(study::Study, result::SCOPFResult; kwargs...) =
    validate_equilibrium(study, result; kwargs...)

"""Render SCOPF status, tolerances, exact-curve checks, and scenario failures."""
function markdown_report(report::SCOPFReport)
    lines = ["# SCOPF report: $(report.case_id)", "",
        "- Valid: `$(report.valid)`; exact-curve feasible: `$(report.physical_valid)`; encoded-model feasible: `$(report.encoded_physical_valid)`",
        "- Solver: $(report.solver); termination: `$(report.termination_status)`; primal: `$(report.primal_status)`",
        "- Mode: `$(report.mode)`; encoding: `$(report.encoding)`",
        "- Base dispatch objective: $(report.objective)",
        "- Tolerances (p.u., reference angle in radians): `$(report.tolerances)`", "",
        "| Scenario | AC residual | Exact droop residual | Encoded droop residual | Smooth/exact gap | Branch margin | P-response violation | Equipment violation | Failures |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---|"]
    for id in report.scenario_ids
        failures = isempty(report.violations[id]) ? "none" : join(string.(report.violations[id]), ", ")
        if haskey(report.scenarios, id)
            r = report.scenarios[id]
            push!(lines, "| $id | $(r.power_balance_max) | $(r.droop_residual_max) | $(report.encoded_droop_residual[id]) | $(r.smooth_exact_droop_gap) | $(r.branch_thermal_min_margin) | $(get(report.coupling_violation, id, 0.0)) | $(get(report.equipment_coupling_violation, id, 0.0)) | $failures |")
        else
            push!(lines, "| $id | — | — | — | — | — | — | — | $failures |")
        end
    end
    push!(lines, "", "Controls and network limits are checked independently in each scenario. " *
        "Active-power response follows the declared policy; this report makes no dynamic or frequency-stability claim.")
    return join(lines, "\n")
end
