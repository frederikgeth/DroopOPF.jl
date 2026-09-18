"""Optimized M3 design and independent validation from one parameter start."""
struct DroopDesignMultiStartRun
    label::Symbol
    initial_settings::DroopSettings{Float64}
    design::DroopDesignResult
    report::SCOPFReport
end

"""Component-wise spread across independently valid optimized settings."""
struct DroopParameterSpread
    slope::Float64
    v_ref::Float64
    deadband_low::Float64
    deadband_high::Float64
end

"""M3 parameter multi-start comparison retaining every design attempt."""
struct DroopDesignMultiStartResult
    case_id::String
    control_id::Int
    runs::Vector{DroopDesignMultiStartRun}
    valid_run_ids::Vector{Symbol}
    best_run::Union{Nothing,Symbol}
    objective_min::Float64
    objective_max::Float64
    objective_spread::Float64
    parameter_spread::DroopParameterSpread
    classification::Symbol
    objective_atol::Float64
    objective_rtol::Float64
end

function _float_settings(settings::DroopSettings)
    return DroopSettings(Float64(settings.slope), Float64(settings.v_ref),
        Float64(settings.deadband_low), Float64(settings.deadband_high))
end

function _design_parameter_spread(runs)
    isempty(runs) && return DroopParameterSpread(NaN, NaN, NaN, NaN)
    values(field) = [Float64(getfield(run.design.settings, field)) for run in runs]
    spread(field) = maximum(values(field)) - minimum(values(field))
    return DroopParameterSpread(spread(:slope), spread(:v_ref),
        spread(:deadband_low), spread(:deadband_high))
end

"""
    optimize_droop_multistart(study, control_id, starts; ...)

Optimize the same bounded M3 design from every named `DroopSettings` start.
All attempts and exact-curve validation reports are retained. When omitted,
`reference_result` is solved once and shared by every design run.
"""
function optimize_droop_multistart(
    study::Study,
    control_id::Integer,
    starts::AbstractDict;
    objective_atol::Real = 1.0e-7,
    objective_rtol::Real = 1.0e-6,
    validation_kwargs::NamedTuple = (;),
    reference_result::Union{Nothing,SCOPFResult} = nothing,
    kwargs...,
)
    isempty(starts) && throw(ArgumentError("at least one named parameter start is required"))
    all(x -> isfinite(x) && x >= 0, (objective_atol, objective_rtol)) ||
        throw(ArgumentError("objective tolerances must be finite and nonnegative"))
    :initial_settings in keys(kwargs) &&
        throw(ArgumentError("pass initial settings through the named starts argument"))
    labels = Symbol.(collect(keys(starts)))
    length(unique(labels)) == length(labels) ||
        throw(ArgumentError("start labels must be unique after conversion to Symbol"))
    all(settings -> settings isa DroopSettings, values(starts)) ||
        throw(ArgumentError("each parameter start must be DroopSettings"))

    if isnothing(reference_result)
        reference_result = solve_scopf(study;
            smooth_epsilon=get(kwargs, :smooth_epsilon, 1.0e-5),
            smooth_reactive_relative_epsilon=get(kwargs, :smooth_reactive_relative_epsilon,
                get(kwargs, :smooth_epsilon, 1.0e-5)),
            smooth_reactive_epsilon=get(kwargs, :smooth_reactive_epsilon, nothing),
            optimizer_factory=get(kwargs, :optimizer_factory, Ipopt.Optimizer),
            optimizer_attributes=get(kwargs, :optimizer_attributes, Dict{String,Any}()),
            silent=get(kwargs, :silent, true))
    end

    runs = DroopDesignMultiStartRun[]
    for original_label in sort(collect(keys(starts)); by=x -> string(Symbol(x)))
        initial = _float_settings(starts[original_label])
        design = optimize_droop_parameters(study, control_id;
            initial_settings=initial, reference_result=reference_result, kwargs...)
        report = validate_droop_design(study, design; validation_kwargs...)
        push!(runs, DroopDesignMultiStartRun(Symbol(original_label), initial, design, report))
    end

    valid_runs = [run for run in runs if run.report.valid && isfinite(run.design.result.objective)]
    objectives = [run.design.result.objective for run in valid_runs]
    if isempty(objectives)
        best_run = nothing
        objective_min = objective_max = objective_spread = NaN
        classification = :no_valid_runs
    else
        best_run = valid_runs[argmin(objectives)].label
        objective_min, objective_max = extrema(objectives)
        objective_spread = objective_max - objective_min
        if length(objectives) == 1
            classification = :insufficient_valid_runs
        else
            threshold = objective_atol + objective_rtol * maximum(abs, objectives)
            classification = objective_spread <= threshold ? :comparable : :divergent
        end
    end
    return DroopDesignMultiStartResult(study.case.id, Int(control_id), runs,
        [run.label for run in valid_runs], best_run, Float64(objective_min),
        Float64(objective_max), Float64(objective_spread),
        _design_parameter_spread(valid_runs), classification,
        Float64(objective_atol), Float64(objective_rtol))
end

_json_data(spread::DroopParameterSpread) = Dict(string(field) =>
    _json_data(getfield(spread, field)) for field in fieldnames(typeof(spread)))
_json_data(run::DroopDesignMultiStartRun) = Dict(
    "label" => _json_data(run.label), "initial_settings" => _json_data(run.initial_settings),
    "design" => _json_data(run.design), "report" => _json_data(run.report))
_json_data(result::DroopDesignMultiStartResult) = Dict(string(field) =>
    _json_data(getfield(result, field)) for field in fieldnames(typeof(result)))

"""Write M3 parameter-start inputs, outcomes, and spreads to versioned JSON."""
write_droop_design_multistart(path::AbstractString, result::DroopDesignMultiStartResult) =
    _write_scopf_json(path, "DroopOPF.DroopDesignMultiStartResult", result)

"""Render M3 parameter multi-start results as Markdown."""
function markdown_report(comparison::DroopDesignMultiStartResult)
    lines = ["# Droop-design multi-start report: $(comparison.case_id)", "",
        "- Control: $(comparison.control_id)",
        "- Classification: `$(comparison.classification)`",
        "- Best independently valid run: `$(comparison.best_run)`",
        "- Objective spread: $(comparison.objective_spread)",
        "- Parameter spread: `$(comparison.parameter_spread)`", "",
        "| Start | Valid | Objective | Initial slope | Final slope | Initial Vref | Final Vref |",
        "|---|---:|---:|---:|---:|---:|---:|"]
    for run in comparison.runs
        push!(lines, "| $(run.label) | $(run.report.valid) | $(run.design.result.objective) | $(run.initial_settings.slope) | $(run.design.settings.slope) | $(run.initial_settings.v_ref) | $(run.design.settings.v_ref) |")
    end
    return join(lines, "\n")
end
