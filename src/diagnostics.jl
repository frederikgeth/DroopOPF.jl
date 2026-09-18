"""Distance from one active controller operating point to its nearest PWL breakpoint."""
struct DroopBreakpointDiagnostic
    scenario::Symbol
    generator_id::Int
    control_id::Int
    voltage::Float64
    nearest_breakpoint::Float64
    breakpoint_index::Int
    distance::Float64
    regime::Symbol
    near_breakpoint::Bool
end

"""A machine-readable M4 finding tied to a scenario and optional network object."""
struct SCOPFFinding
    severity::Symbol
    code::Symbol
    scenario::Symbol
    subject::Symbol
    subject_id::Union{Nothing,Int}
    value::Union{Nothing,Float64}
    threshold::Union{Nothing,Float64}
    message::String
end

"""Structured SCOPF diagnostics kept separate from the stable validation report."""
struct SCOPFDiagnostics
    case_id::String
    critical_scenario::Union{Nothing,Symbol}
    breakpoint_tolerance::Float64
    binding_tolerance::Float64
    breakpoints::Vector{DroopBreakpointDiagnostic}
    findings::Vector{SCOPFFinding}
end

function _diagnostic_regime(control::VoltVarDroop, voltage::Real)
    b = control.curve.breakpoints
    voltage <= b[1] && return :saturation_qmax
    voltage < b[2] && return :proportional_qmax
    voltage <= b[3] && return :deadband
    voltage < b[4] && return :proportional_qmin
    return :saturation_qmin
end

function _scopf_cases(study::Study)
    ids = [:base; [contingency.id for contingency in study.contingencies]]
    cases = [study.case; [scenario_case(study.case, contingency) for contingency in study.contingencies]]
    return ids, cases
end

function _finding(severity, code, scenario, subject, subject_id, value, threshold, message)
    return SCOPFFinding(severity, code, scenario, subject, subject_id,
        isnothing(value) ? nothing : Float64(value),
        isnothing(threshold) ? nothing : Float64(threshold), message)
end

function _binding_findings!(findings, id, case, state, tolerance)
    for (i, bus) in enumerate(case.network.buses)
        for (code, margin) in ((:binding_voltage_min, state.vm[i] - bus.v_min),
                               (:binding_voltage_max, bus.v_max - state.vm[i]))
            margin <= tolerance || continue
            severity = margin < 0 ? :error : :warning
            side = code == :binding_voltage_min ? "lower" : "upper"
            push!(findings, _finding(severity, code, id, :bus, bus.id, margin, tolerance,
                "Bus $(bus.id) has $(side) voltage margin $(margin) p.u."))
        end
    end
    branch_margins = operating_margins(case.network, state)
    for (branch, margin) in zip(case.network.branches, branch_margins)
        branch.available && margin <= tolerance || continue
        push!(findings, _finding(margin < 0 ? :error : :warning, :binding_branch_thermal,
            id, :branch, branch.id, margin, tolerance,
            "Branch $(branch.id) has thermal margin $(margin) p.u."))
    end
    for (i, generator) in enumerate(case.generators)
        generator.available || continue
        margins = ((:binding_generator_p_min, state.pg[i] - generator.p_min),
                   (:binding_generator_p_max, generator.p_max - state.pg[i]),
                   (:binding_generator_q_min, state.qg[i] - generator.q_min),
                   (:binding_generator_q_max, generator.q_max - state.qg[i]))
        for (code, margin) in margins
            margin <= tolerance || continue
            push!(findings, _finding(margin < 0 ? :error : :warning, code, id,
                :generator, generator.id, margin, tolerance,
                "Generator $(generator.id) has $(code) margin $(margin) p.u."))
        end
    end
    return findings
end

function _critical_margin(report::EquilibriumValidationReport)
    margins = (report.voltage_min_margin, report.voltage_max_margin,
        report.generator_p_min_margin, report.generator_p_max_margin,
        report.generator_q_min_margin, report.generator_q_max_margin,
        report.branch_thermal_min_margin)
    finite_margins = filter(isfinite, collect(margins))
    return isempty(finite_margins) ? Inf : minimum(finite_margins)
end

"""
    scopf_diagnostics(study, result; breakpoint_tolerance=1e-3, binding_tolerance=1e-4, ...)

Independently validate a result, measure every active control's nearest-breakpoint
distance, identify device-level binding limits, and select the contingency with
the smallest independently recomputed physical margin. The critical-scenario
score is a screening heuristic, not a dynamic stability ranking.
"""
function scopf_diagnostics(
    study::Study,
    result::SCOPFResult;
    breakpoint_tolerance::Real = 1.0e-3,
    binding_tolerance::Real = 1.0e-4,
    validation_kwargs...,
)
    all(x -> isfinite(x) && x >= 0, (breakpoint_tolerance, binding_tolerance)) ||
        throw(ArgumentError("diagnostic tolerances must be finite and nonnegative"))
    report = equilibrium_report(study, result; validation_kwargs...)
    ids, cases = _scopf_cases(study)
    breakpoints = DroopBreakpointDiagnostic[]
    findings = SCOPFFinding[]

    successful = result.termination_status in
        (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED, :OPTIMAL, :ALMOST_OPTIMAL) ||
        (result.termination_status == :NOT_RUN && isempty(study.contingencies))
    successful || push!(findings, _finding(:error, :solver_failure, :base, :study,
        nothing, nothing, nothing, "Solver terminated with $(result.termination_status)."))

    for (id, case) in zip(ids, cases)
        for violation in get(report.violations, id, Symbol[])
            push!(findings, _finding(:error, :validation_failure, id, :scenario,
                nothing, nothing, nothing, "Independent validation failed: $(violation)."))
        end
        state = get(result.states, id, nothing)
        isnothing(state) && continue
        # Validation omits malformed states; retain its finding without indexing them.
        haskey(report.scenarios, id) || continue
        _binding_findings!(findings, id, case, state, binding_tolerance)
        bus_indices = _bus_indices(case.network)
        generator_indices = Dict(generator.id => i for (i, generator) in enumerate(case.generators))
        for attachment in case.attachments
            generator_index = generator_indices[attachment.generator_id]
            case.generators[generator_index].available || continue
            control = case.controls[attachment.control_id]
            voltage = state.vm[bus_indices[attachment.location.bus_id]]
            distances = abs.(control.curve.breakpoints .- voltage)
            breakpoint_index = argmin(distances)
            distance = distances[breakpoint_index]
            diagnostic = DroopBreakpointDiagnostic(id, attachment.generator_id,
                attachment.control_id, Float64(voltage),
                Float64(control.curve.breakpoints[breakpoint_index]), breakpoint_index,
                Float64(distance), _diagnostic_regime(control, voltage),
                distance <= breakpoint_tolerance)
            push!(breakpoints, diagnostic)
            if diagnostic.near_breakpoint
                push!(findings, _finding(:warning, :near_droop_breakpoint, id,
                    :generator, attachment.generator_id, distance, breakpoint_tolerance,
                    "Generator $(attachment.generator_id) control $(attachment.control_id) is $(distance) p.u. from breakpoint $(breakpoint_index)."))
            end
        end
    end

    candidates = isempty(study.contingencies) ? ids : [c.id for c in study.contingencies]
    scored = [(id, _critical_margin(report.scenarios[id])) for id in candidates if haskey(report.scenarios, id)]
    critical_index = isempty(scored) ? nothing : argmin(last.(scored))
    critical_scenario = isnothing(critical_index) ? nothing : first(scored[critical_index])
    if !isnothing(critical_scenario)
        margin = last(scored[critical_index])
        push!(findings, _finding(:info, :critical_contingency, critical_scenario,
            :scenario, nothing, margin, nothing,
            "Scenario $(critical_scenario) has the smallest aggregate physical margin ($(margin) p.u.)."))
    end
    return SCOPFDiagnostics(study.case.id, critical_scenario,
        Float64(breakpoint_tolerance), Float64(binding_tolerance), breakpoints, findings)
end

"""Render structured findings and breakpoint distances as Markdown."""
function markdown_report(diagnostics::SCOPFDiagnostics)
    lines = [
        "# SCOPF diagnostics: $(diagnostics.case_id)", "",
        "- Critical scenario: `$(diagnostics.critical_scenario)`",
        "- Breakpoint tolerance: $(diagnostics.breakpoint_tolerance) p.u.",
        "- Binding tolerance: $(diagnostics.binding_tolerance) p.u.", "",
        "## Droop breakpoint distances", "",
        "| Scenario | Generator | Control | Voltage | Nearest breakpoint | Distance | Regime | Near |",
        "|---|---:|---:|---:|---:|---:|---|---:|",
    ]
    for item in diagnostics.breakpoints
        push!(lines, "| $(item.scenario) | $(item.generator_id) | $(item.control_id) | $(item.voltage) | $(item.nearest_breakpoint) | $(item.distance) | $(item.regime) | $(item.near_breakpoint) |")
    end
    append!(lines, ["", "## Findings", "",
        "| Severity | Code | Scenario | Subject | Value | Threshold | Message |",
        "|---|---|---|---|---:|---:|---|"])
    for finding in diagnostics.findings
        subject = isnothing(finding.subject_id) ? string(finding.subject) : "$(finding.subject) $(finding.subject_id)"
        push!(lines, "| $(finding.severity) | $(finding.code) | $(finding.scenario) | $subject | $(finding.value) | $(finding.threshold) | $(finding.message) |")
    end
    return join(lines, "\n")
end
