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
    encoded_droop = Dict{Symbol,Float64}()
    violations = Dict(id => Symbol[] for id in ids)
    result.encoding in (:smooth,:complementarity) || push!(violations[:base], :unknown_encoding)
    result.mode == study.mode || push!(violations[:base], :response_mode_mismatch)
    Set(keys(result.states)) == Set(ids) || push!(violations[:base], :scenario_set_mismatch)
    base = get(result.states, :base, nothing)
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
        report = validate_equilibrium(case, state;
            power_tolerance=power_tolerance, droop_tolerance=droop_tolerance,
            limit_tolerance=limit_tolerance, unavailable_tolerance=unavailable_tolerance,
            smooth_epsilon=result.encoding == :smooth ? result.smooth_epsilon : nothing,
            smooth_reactive_relative_epsilon=result.encoding == :smooth ? result.smooth_reactive_relative_epsilon : nothing,
            smooth_reactive_epsilon=result.encoding == :smooth ? result.smooth_reactive_epsilon : nothing)
        encoded_droop[id] = report.droop_residual_max
        if result.encoding == :smooth
            encoded_droop[id] = 0.0
            bus_indices = _bus_indices(case.network)
            generator_indices = Dict(g.id=>i for (i,g) in enumerate(case.generators))
            for attachment in case.attachments
                i = generator_indices[attachment.generator_id]
                case.generators[i].available || continue
                control = case.controls[attachment.control_id]
                epsilon_q = reactive_smoothing_epsilon(control,result.smooth_reactive_relative_epsilon;
                    absolute_epsilon=result.smooth_reactive_epsilon)
                expected = _smooth_droop_value(control,state.vm[bus_indices[attachment.location.bus_id]],
                    result.smooth_epsilon,epsilon_q)
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
                violation = max(violation, abs(change - alpha[i] * delta))
            end
            if study.mode == :corrective || haskey(study.redispatch_limits, generator.id)
                violation = max(violation, abs(change) - get(study.redispatch_limits, generator.id, 0.0))
            end
        end
        coupling[id] = violation
        violation <= coupling_tolerance || push!(violations[id], :active_power_response)
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
        result.encoding, result.solver, ids, reports, coupling, encoded_droop, violations, tolerances)
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
        "| Scenario | AC residual | Exact droop residual | Encoded droop residual | Smooth/exact gap | Branch margin | Response violation | Failures |",
        "|---|---:|---:|---:|---:|---:|---:|---|"]
    for id in report.scenario_ids
        failures = isempty(report.violations[id]) ? "none" : join(string.(report.violations[id]), ", ")
        if haskey(report.scenarios, id)
            r = report.scenarios[id]
            push!(lines, "| $id | $(r.power_balance_max) | $(r.droop_residual_max) | $(report.encoded_droop_residual[id]) | $(r.smooth_exact_droop_gap) | $(r.branch_thermal_min_margin) | $(get(report.coupling_violation, id, 0.0)) | $failures |")
        else
            push!(lines, "| $id | — | — | — | — | — | — | $failures |")
        end
    end
    push!(lines, "", "Controls and network limits are checked independently in each scenario. " *
        "Active-power response follows the declared policy; this report makes no dynamic or frequency-stability claim.")
    return join(lines, "\n")
end
