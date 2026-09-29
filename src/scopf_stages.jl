"""Paired immediate and settled steady-state SCOPF assessments sharing one fixed base."""
struct SCOPFStageAssessment
    immediate::SCOPFResult
    settled::SCOPFResult
    immediate_report::SCOPFReport
    settled_report::SCOPFReport
    scenario_metrics::Dict{Symbol,NamedTuple}
end

function _stage_equipment_movement(result::SCOPFResult, id::Symbol)
    tap_base = get(result.tap_settings, :base, Dict{Int,Float64}())
    shunt_base = get(result.shunt_settings, :base, Dict{Int,Float64}())
    taps = get(result.tap_settings, id, Dict{Int,Float64}())
    shunts = get(result.shunt_settings, id, Dict{Int,Float64}())
    tap = maximum((abs(value - tap_base[device]) for (device,value) in taps
        if haskey(tap_base,device)); init=0.0)
    shunt = maximum((abs(value - shunt_base[device]) for (device,value) in shunts
        if haskey(shunt_base,device)); init=0.0)
    (; tap, shunt)
end

"""
    assess_scopf_response_stages(immediate_study, settled_study, base_result; ...)

Hold the validated base state and equipment settings fixed, then solve the same
contingencies twice: first with preventive equipment frozen and then with the
declared settled policy. These are paired equilibria, not a transient simulation.
"""
function assess_scopf_response_stages(immediate_study::Study,
    settled_study::Study, base_result::SCOPFResult;
    immediate_solve_kwargs::NamedTuple=(;),
    settled_solve_kwargs::NamedTuple=immediate_solve_kwargs,
    validation_kwargs::NamedTuple=(;))
    _json_data(immediate_study.case) == _json_data(settled_study.case) ||
        throw(ArgumentError("response stages must use the same case"))
    _json_data(immediate_study.contingencies) == _json_data(settled_study.contingencies) ||
        throw(ArgumentError("response stages must use the same contingencies"))
    immediate_study.control_policy.taps == :preventive &&
        immediate_study.control_policy.shunts == :preventive ||
        throw(ArgumentError("the immediate stage must freeze taps and shunts"))
    base_state = get(base_result.states, :base, nothing)
    isnothing(base_state) && throw(ArgumentError("base result has no base state"))
    base_taps = get(base_result.tap_settings, :base, Dict{Int,Float64}())
    base_shunts = get(base_result.shunt_settings, :base, Dict{Int,Float64}())
    immediate = solve_scopf(immediate_study; fixed_base_state=base_state,
        fixed_base_tap_settings=base_taps,
        fixed_base_shunt_settings=base_shunts, immediate_solve_kwargs...)
    settled = solve_scopf(settled_study; fixed_base_state=base_state,
        fixed_base_tap_settings=base_taps,
        fixed_base_shunt_settings=base_shunts, settled_solve_kwargs...)
    assemble_scopf_response_stages(immediate_study, settled_study, immediate,
        settled; validation_kwargs)
end

"""
    assemble_scopf_response_stages(immediate_study, settled_study, immediate, settled; ...)

Assemble and independently validate a paired response-stage assessment from
already solved results. This is the resumable/process-isolated counterpart to
`assess_scopf_response_stages`.
"""
function assemble_scopf_response_stages(immediate_study::Study,
    settled_study::Study, immediate::SCOPFResult, settled::SCOPFResult;
    validation_kwargs::NamedTuple=(;))
    _json_data(immediate_study.case) == _json_data(settled_study.case) ||
        throw(ArgumentError("response stages must use the same case"))
    _json_data(immediate_study.contingencies) == _json_data(settled_study.contingencies) ||
        throw(ArgumentError("response stages must use the same contingencies"))
    immediate_study.control_policy.taps == :preventive &&
        immediate_study.control_policy.shunts == :preventive ||
        throw(ArgumentError("the immediate stage must freeze taps and shunts"))
    immediate_report = equilibrium_report(immediate_study, immediate; validation_kwargs...)
    settled_report = equilibrium_report(settled_study, settled; validation_kwargs...)
    metrics = Dict{Symbol,NamedTuple}()
    for id in immediate_report.scenario_ids
        haskey(immediate_report.scenarios,id) && haskey(settled_report.scenarios,id) || continue
        a, b = immediate_report.scenarios[id], settled_report.scenarios[id]
        metrics[id] = (
            immediate_valid=isempty(immediate_report.violations[id]),
            settled_valid=isempty(settled_report.violations[id]),
            immediate_voltage_margin=min(a.voltage_min_margin,a.voltage_max_margin),
            settled_voltage_margin=min(b.voltage_min_margin,b.voltage_max_margin),
            immediate_thermal_margin=a.branch_thermal_min_margin,
            settled_thermal_margin=b.branch_thermal_min_margin,
            immediate_q_margin=min(a.generator_q_min_margin,a.generator_q_max_margin),
            settled_q_margin=min(b.generator_q_min_margin,b.generator_q_max_margin),
            immediate_movement=_stage_equipment_movement(immediate,id),
            settled_movement=_stage_equipment_movement(settled,id),
        )
    end
    SCOPFStageAssessment(immediate, settled, immediate_report, settled_report, metrics)
end

function markdown_report(assessment::SCOPFStageAssessment)
    lines = ["# SCOPF response-stage assessment", "",
        "- Immediate stage valid: `$(assessment.immediate_report.valid)`",
        "- Settled stage valid: `$(assessment.settled_report.valid)`",
        "- Interpretation: paired steady-state equilibria; no transient-time claim.", "",
        "| Scenario | Immediate V margin | Settled V margin | Immediate thermal margin | Settled thermal margin | Immediate Q margin | Settled Q margin | Settled max tap move | Settled max shunt move |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for id in assessment.immediate_report.scenario_ids
        haskey(assessment.scenario_metrics,id) || continue
        m = assessment.scenario_metrics[id]
        push!(lines, "| $id | $(m.immediate_voltage_margin) | $(m.settled_voltage_margin) | $(m.immediate_thermal_margin) | $(m.settled_thermal_margin) | $(m.immediate_q_margin) | $(m.settled_q_margin) | $(m.settled_movement.tap) | $(m.settled_movement.shunt) |")
    end
    join(lines,"\n")
end
