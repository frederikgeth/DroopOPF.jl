"""One independently solved and validated SCOPF start."""
struct SCOPFMultiStartRun
    label::Symbol
    initial_states::Dict{Symbol,Union{Nothing,ACState{Float64}}}
    result::SCOPFResult
    report::SCOPFReport
end

"""Comparison of named SCOPF starts without discarding divergent or invalid runs."""
struct SCOPFMultiStartResult
    case_id::String
    runs::Vector{SCOPFMultiStartRun}
    valid_run_ids::Vector{Symbol}
    best_run::Union{Nothing,Symbol}
    objective_min::Float64
    objective_max::Float64
    objective_spread::Float64
    classification::Symbol
    objective_atol::Float64
    objective_rtol::Float64
end

"""
    solve_scopf_multistart(study, starts; objective_atol=1e-7, objective_rtol=1e-6, ...)

Solve and independently validate every named initial-state dictionary. A start may
be empty for a cold solve. All runs are retained. Valid objectives are classified
as `:comparable`, `:divergent`, `:insufficient_valid_runs`, or `:no_valid_runs`;
the best run is identified only among independently valid results.
"""
function solve_scopf_multistart(
    study::Study,
    starts::AbstractDict;
    objective_atol::Real = 1.0e-7,
    objective_rtol::Real = 1.0e-6,
    validation_kwargs::NamedTuple = (;),
    kwargs...,
)
    isempty(starts) && throw(ArgumentError("at least one named start is required"))
    all(x -> isfinite(x) && x >= 0, (objective_atol, objective_rtol)) ||
        throw(ArgumentError("objective tolerances must be finite and nonnegative"))
    :initial_states in keys(kwargs) &&
        throw(ArgumentError("pass initial states through the named starts argument"))

    runs = SCOPFMultiStartRun[]
    converted_labels = Symbol.(collect(keys(starts)))
    length(unique(converted_labels)) == length(converted_labels) ||
        throw(ArgumentError("start labels must be unique after conversion to Symbol"))
    for original_label in sort(collect(keys(starts)); by=x -> string(Symbol(x)))
        label = Symbol(original_label)
        initial_states = starts[original_label]
        initial_states isa AbstractDict ||
            throw(ArgumentError("each named start must be an initial-state dictionary"))
        initial_snapshot = Dict{Symbol,Union{Nothing,ACState{Float64}}}()
        for (scenario, state) in initial_states
            scenario isa Symbol || throw(ArgumentError("initial-state scenario IDs must be Symbols"))
            if isnothing(state)
                initial_snapshot[scenario] = nothing
            elseif state isa ACState
                initial_snapshot[scenario] = ACState(Float64.(state.vm), Float64.(state.va),
                    Float64.(state.pg), Float64.(state.qg))
            else
                throw(ArgumentError("each initial state must be an ACState or nothing"))
            end
        end
        result = solve_scopf(study; initial_states=initial_states, kwargs...)
        report = equilibrium_report(study, result; validation_kwargs...)
        push!(runs, SCOPFMultiStartRun(label, initial_snapshot, result, report))
    end

    valid_runs = [run for run in runs if run.report.valid && isfinite(run.result.objective)]
    valid_run_ids = [run.label for run in valid_runs]
    objectives = [run.result.objective for run in valid_runs]
    if isempty(objectives)
        best_run = nothing
        objective_min = objective_max = objective_spread = NaN
        classification = :no_valid_runs
    else
        best_index = argmin(objectives)
        best_run = valid_runs[best_index].label
        objective_min, objective_max = extrema(objectives)
        objective_spread = objective_max - objective_min
        if length(objectives) == 1
            classification = :insufficient_valid_runs
        else
            scale = maximum(abs, objectives)
            threshold = objective_atol + objective_rtol * scale
            classification = objective_spread <= threshold ? :comparable : :divergent
        end
    end
    return SCOPFMultiStartResult(
        study.case.id, runs, valid_run_ids, best_run,
        Float64(objective_min), Float64(objective_max), Float64(objective_spread),
        classification, Float64(objective_atol), Float64(objective_rtol),
    )
end

"""Render every multi-start outcome and the comparison decision as Markdown."""
function markdown_report(comparison::SCOPFMultiStartResult)
    lines = [
        "# SCOPF multi-start report: $(comparison.case_id)", "",
        "- Classification: `$(comparison.classification)`",
        "- Best independently valid run: `$(comparison.best_run)`",
        "- Valid objective range: $(comparison.objective_min) to $(comparison.objective_max)",
        "- Objective spread: $(comparison.objective_spread)",
        "- Comparison tolerance: atol=$(comparison.objective_atol), rtol=$(comparison.objective_rtol)", "",
        "| Start | Seeded scenarios | Valid | Termination | Objective | Solver |",
        "|---|---:|---:|---|---:|---|",
    ]
    for run in comparison.runs
        push!(lines, "| $(run.label) | $(length(run.initial_states)) | $(run.report.valid) | $(run.result.termination_status) | $(run.result.objective) | $(run.result.solver) |")
    end
    push!(lines, "", "Invalid and divergent runs are retained; `best_run` never refers to an invalid result.")
    return join(lines, "\n")
end
