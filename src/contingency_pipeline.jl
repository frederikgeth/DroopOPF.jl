# Independent models may be built concurrently. Serialize native optimizer calls
# so threaded campaigns do not depend on a particular MUMPS build's mutex.
const _CONTINGENCY_SOLVE_LOCK = ReentrantLock()

"""Unified operational rank for screened, exact, and island-aware outcomes."""
struct ContingencyPipelineRank
    contingency_id::Symbol
    device_kind::Symbol
    device_id::Int
    classification::Symbol
    priority_tier::Int
    severity::Float64
    minimum_operating_margin::Union{Nothing,Float64}
    discarded_load_p::Float64
    evaluation_source::Symbol
end

"""One routed contingency and any evaluation retained for it."""
struct ContingencyPipelineAssessment
    entry::ContingencyCatalogEntry
    decision::ContingencyFilterDecision
    outcome::Symbol
    exact_assessment::Union{Nothing,ContingencyAssessment}
    island_assessment::Union{Nothing,IslandedContingencyAssessment}
    error_message::Union{Nothing,String}
    rank::ContingencyPipelineRank
end

"""Complete, coverage-checked result of the contingency assessment pipeline."""
struct ContingencyPipelineResult
    case_id::String
    assessments::Vector{ContingencyPipelineAssessment}
    combined_ranking::Vector{ContingencyPipelineRank}
    branch_ranking::Vector{ContingencyPipelineRank}
    line_ranking::Vector{ContingencyPipelineRank}
    transformer_ranking::Vector{ContingencyPipelineRank}
    generator_ranking::Vector{ContingencyPipelineRank}
    checks::NamedTuple
end

function _pipeline_minimum_margin(validation::EquilibriumValidationReport)
    minimum((validation.voltage_min_margin, validation.voltage_max_margin,
        validation.generator_p_min_margin, validation.generator_p_max_margin,
        validation.generator_q_min_margin, validation.generator_q_max_margin,
        validation.branch_thermal_min_margin))
end

function _pipeline_rank(entry::ContingencyCatalogEntry,
    decision::ContingencyFilterDecision; exact=nothing, island=nothing,
    error_message=nothing, audited::Bool=false)
    if !isnothing(error_message)
        return ContingencyPipelineRank(entry.contingency.id, entry.device_kind,
            entry.device_id, :evaluation_error, 6, 0.0, nothing, 0.0, :error)
    elseif !isnothing(exact)
        original = exact.rank
        audit_failed = audited && original.classification != :accepted
        classification = audit_failed ? :screening_audit_failure :
            audited ? :screening_audit_pass : original.classification
        tier = audit_failed ? 7 : original.classification == :invalid ? 5 :
            original.classification == :physical_only ? 3 : audited ? 1 : 2
        severity = isfinite(original.severity) ? original.severity : 0.0
        return ContingencyPipelineRank(entry.contingency.id, entry.device_kind,
            entry.device_id, classification, tier, severity,
            original.minimum_operating_margin, 0.0,
            audited ? :screening_audit : :exact_ac)
    elseif !isnothing(island)
        validation = island.report.validation
        margin = _pipeline_minimum_margin(validation)
        physical = validation.valid
        solver_accepted = island.report.termination_status in
            (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED, :OPTIMAL, :ALMOST_OPTIMAL)
        classification = !physical ? :invalid : !solver_accepted ? :physical_only :
            island.selection.discarded_load_p > 0 ? :island_load_loss : :accepted
        tier = classification == :invalid ? 5 : classification == :island_load_loss ? 4 :
            classification == :physical_only ? 3 : 2
        return ContingencyPipelineRank(entry.contingency.id, entry.device_kind,
            entry.device_id, classification, tier, -margin, margin,
            island.selection.discarded_load_p, :island_aware_ac)
    end
    prediction = something(decision.predicted_loading, 0.0)
    ContingencyPipelineRank(entry.contingency.id, entry.device_kind,
        entry.device_id, :screened_not_evaluated, 1, prediction, nothing, 0.0,
        :filter)
end

_sort_pipeline_ranks(ranks) = sort!(ranks; by=rank ->
    (-rank.priority_tier, -rank.discarded_load_p, -rank.severity,
        string(rank.contingency_id)))

function _evaluate_exact_entry(case::Case, base_state::ACState,
    entry::ContingencyCatalogEntry, catalog::ContingencyCatalog,
    participation::AbstractDict; _phase_timings=nothing, _model_hook=nothing, kwargs...)
    started = time_ns()
    built = Ref(started)
    study = Study(case; contingencies=[entry.contingency], participation)
    result = evaluate_contingencies(study, base_state; kwargs...,
        _model_hook=model -> begin
            built[] = time_ns()
            isnothing(_model_hook) || _model_hook(model)
        end)
    solved = time_ns()
    report = equilibrium_report(study, result)
    ranks = rank_contingencies(catalog, report)
    length(ranks) == 1 || error("one-outage assessment did not produce one rank")
    if !isnothing(_phase_timings)
        for (key,value) in ((:prepare_build,(built[]-started)/1e9),
            (:optimize_extract,(solved-built[])/1e9),
            (:validate_rank,(time_ns()-solved)/1e9))
            _phase_timings[key] = get(_phase_timings,key,0.0)+value
        end
    end
    ContingencyAssessment(entry.contingency, result, report, only(ranks))
end

"""
    assess_contingency_pipeline(case, base_state; ...)

Run a coverage-checked M10 assessment pipeline. Every catalog entry receives
exactly one route. `audit_screened_ids` names screened entries that must also
receive exact evaluation. Set `screening_enabled=false` for an exact connected-
outage baseline. Evaluation errors are retained unless
`continue_on_error=false`. `workers=1` preserves serial execution. Larger values
use bounded threaded batches with independent models, serial native solves,
and deterministic coordinator callbacks/checkpoints. Start Julia with enough
threads. Phase timings sum worker durations and are not parallel wall time.
User model hooks, if supplied, must be thread-safe.
"""
function assess_contingency_pipeline(case::Case, base_state::ACState;
    catalog::ContingencyCatalog=contingency_catalog(case),
    participation::AbstractDict=default_participation(case),
    screening_enabled::Bool=true, audit_screened_ids::AbstractVector{Symbol}=Symbol[],
    continue_on_error::Bool=true, loading_threshold::Real=0.8,
    voltage_guard::Real=0.02, lodf_tolerance::Real=1e-8,
    reactive_guard::Real=0.1, ac_risk_guard::Bool=true, droop_response_guard::Bool=false,
    workers::Integer=1,
    _phase_timings=nothing,
    _assessment_loader=(entry, decision, audited)->nothing,
    _assessment_callback=identity, kwargs...)
    1 <= workers <= Threads.nthreads() || throw(ArgumentError("workers must be between 1 and Threads.nthreads()"))
    workers > 1 && (get(kwargs,:optimizer_factory,Ipopt.Optimizer) !== Ipopt.Optimizer || get(kwargs,:encoding,:smooth) != :smooth) &&
        throw(ArgumentError("threaded assessment currently supports smooth Ipopt evaluation"))
    haskey(kwargs,:_optimizer_lock) && throw(ArgumentError("the pipeline owns the optimizer lock"))
    validate_equilibrium(case, base_state).valid ||
        throw(ArgumentError("base state must independently validate"))
    catalog.case_id == case.id || throw(ArgumentError("catalog case ID does not match case"))
    audit_ids = Set(audit_screened_ids)
    !screening_enabled && !isempty(audit_ids) &&
        throw(ArgumentError("screening audits require screening_enabled=true"))
    known_ids = Set(entry.contingency.id for entry in catalog.entries)
    issubset(audit_ids, known_ids) ||
        throw(ArgumentError("screening audit references an unknown contingency"))
    filter_started = time_ns()
    decisions = filter_contingencies(case, base_state; catalog, loading_threshold,
        voltage_guard, lodf_tolerance, reactive_guard, ac_risk_guard, droop_response_guard, participation)
    isnothing(_phase_timings) || (_phase_timings[:filter] = (time_ns()-filter_started)/1e9)
    length(decisions) == length(catalog.entries) || error("filter did not cover the catalog")
    decision_by_id = Dict(decision.contingency_id => decision for decision in decisions)
    length(decision_by_id) == length(decisions) || error("filter returned duplicate decisions")
    screened_ids = Set(decision.contingency_id for decision in decisions
        if decision.action == :screened)
    issubset(audit_ids, screened_ids) ||
        throw(ArgumentError("screening audit IDs must refer to screened contingencies"))
    function evaluate_entry(entry, decision, audited)
        phases = isnothing(_phase_timings) ? nothing : Dict{Symbol,Float64}()
        exact = nothing
        island = nothing
        error_message = nothing
        outcome = decision.action
        try
            if decision.action == :exact || audited
                exact = _evaluate_exact_entry(case, base_state, entry, catalog,
                    participation; _phase_timings=phases, _optimizer_lock=workers > 1 ? _CONTINGENCY_SOLVE_LOCK : nothing, kwargs...)
                outcome = audited ? :screened_audited : :exact_evaluated
            elseif decision.action == :island_aware
                island = if workers == 1
                    evaluate_islanding_contingency(case, entry.contingency, base_state; kwargs...)
                else
                    lock(_CONTINGENCY_SOLVE_LOCK) do
                        evaluate_islanding_contingency(case, entry.contingency, base_state; kwargs...)
                    end
                end
                outcome = :island_evaluated
            elseif decision.action == :screened
                outcome = :screened
            else
                error("unknown filtering action $(decision.action)")
            end
        catch error
            error isa InterruptException && rethrow()
            continue_on_error || rethrow()
            error_message = sprint(showerror, error)
            outcome = :evaluation_error
        end
        rank = _pipeline_rank(entry, decision; exact, island, error_message, audited)
        assessment = ContingencyPipelineAssessment(entry, decision, outcome,
            exact, island, error_message, rank)
        (;assessment, phases)
    end
    assessments = ContingencyPipelineAssessment[]
    # Load and commit on the coordinator. At most `workers` models/results are
    # live in a batch, and every task is joined before invoking user callbacks.
    for batch_start in 1:workers:length(catalog.entries)
        batch = catalog.entries[batch_start:min(batch_start+workers-1,length(catalog.entries))]
        jobs = map(batch) do entry
            decision = decision_by_id[entry.contingency.id]
            decision.device_kind == entry.device_kind && decision.device_id == entry.device_id ||
                error("filter decision does not match catalog entry")
            if !screening_enabled && decision.action == :screened
                decision = ContingencyFilterDecision(decision.contingency_id,
                    decision.device_kind, decision.device_id, :exact,
                    :screening_disabled, decision.predicted_loading)
            end
            audited = decision.action == :screened && entry.contingency.id in audit_ids
            previous = _assessment_loader(entry,decision,audited)
            (;entry,decision,audited,previous)
        end
        execute = function(job)
            !isnothing(job.previous) && return (;value=(;assessment=job.previous,phases=nothing),failure=nothing)
            try
                (;value=evaluate_entry(job.entry,job.decision,job.audited),failure=nothing)
            catch error
                (;value=nothing,failure=error)
            end
        end
        results = if workers == 1
            [execute(only(jobs))]
        else
            tasks = [Threads.@spawn execute(job) for job in jobs]
            fetch.(tasks)
        end
        for (job,result) in zip(jobs,results)
            isnothing(result.failure) || throw(result.failure)
            value=result.value
            push!(assessments,value.assessment)
            if !isnothing(value.phases)
                for (key,seconds) in value.phases
                    _phase_timings[key]=get(_phase_timings,key,0.)+seconds
                end
            end
            # Durable writes and interruption remain outside solver-error handling.
            isnothing(job.previous) && _assessment_callback(value.assessment)
        end
    end
    ids = [assessment.entry.contingency.id for assessment in assessments]
    expected_ids = [entry.contingency.id for entry in catalog.entries]
    coverage_complete = ids == expected_ids && length(unique(ids)) == length(ids)
    route_consistent = all(assessment ->
        assessment.outcome == :evaluation_error ||
        assessment.decision.action == :screened &&
            assessment.outcome in (:screened, :screened_audited) ||
        assessment.decision.action == :exact && assessment.outcome == :exact_evaluated ||
        assessment.decision.action == :island_aware &&
            assessment.outcome == :island_evaluated, assessments)
    audited = [assessment for assessment in assessments
        if assessment.outcome == :screened_audited]
    audit_pass = all(assessment.rank.classification == :screening_audit_pass
        for assessment in audited) &&
        all(id -> any(assessment.entry.contingency.id == id &&
            assessment.outcome == :screened_audited for assessment in assessments), audit_ids)
    error_count = count(assessment -> assessment.outcome == :evaluation_error, assessments)
    screened_count = count(a -> a.outcome == :screened, assessments)
    routing_complete = coverage_complete && route_consistent && audit_pass && error_count == 0
    full_ac_coverage = routing_complete && screened_count == 0
    accepted_classes = Set((:accepted, :screening_audit_pass))
    all_outcomes_accepted = full_ac_coverage &&
        all(assessment.rank.classification in accepted_classes for assessment in assessments)
    checks = (base_valid=true, coverage_complete, route_consistent,
        screening_audit_pass=audit_pass, error_count,
        screened_count,
        audited_screened_count=length(audited),
        exact_evaluated_count=count(a -> a.outcome == :exact_evaluated, assessments),
        island_evaluated_count=count(a -> a.outcome == :island_evaluated, assessments),
        routing_complete, full_ac_coverage, all_outcomes_accepted,
        complete=routing_complete)
    combined = _sort_pipeline_ranks([assessment.rank for assessment in assessments])
    branches = _sort_pipeline_ranks([rank for rank in combined
        if rank.device_kind in (:line, :transformer)])
    lines = _sort_pipeline_ranks([rank for rank in combined if rank.device_kind == :line])
    transformers = _sort_pipeline_ranks([rank for rank in combined
        if rank.device_kind == :transformer])
    generators = _sort_pipeline_ranks([rank for rank in combined if rank.device_kind == :generator])
    ContingencyPipelineResult(case.id, assessments, combined, branches, lines,
        transformers, generators, checks)
end

function markdown_report(result::ContingencyPipelineResult)
    lines = ["# Contingency pipeline: $(result.case_id)", "",
        "- Routing complete: `$(result.checks.routing_complete)`",
        "- Coverage complete: `$(result.checks.coverage_complete)`",
        "- Routes consistent: `$(result.checks.route_consistent)`",
        "- Full AC coverage: `$(result.checks.full_ac_coverage)`",
        "- All outcomes accepted: `$(result.checks.all_outcomes_accepted)`",
        "- Screening audit passed: `$(result.checks.screening_audit_pass)`",
        "- Evaluation errors: `$(result.checks.error_count)`", "",
        "| Rank | ID | Device | Route | Outcome | Classification | Margin | Discarded load | Source |",
        "|---:|---|---|---|---|---|---:|---:|---|"]
    by_id = Dict(assessment.entry.contingency.id => assessment
        for assessment in result.assessments)
    for (index, rank) in enumerate(result.combined_ranking)
        assessment = by_id[rank.contingency_id]
        margin = isnothing(rank.minimum_operating_margin) ? "—" :
            string(rank.minimum_operating_margin)
        push!(lines, "| $index | $(rank.contingency_id) | $(rank.device_kind) | " *
            "$(assessment.decision.action) | $(assessment.outcome) | " *
            "$(rank.classification) | $margin | $(rank.discarded_load_p) | " *
            "$(rank.evaluation_source) |")
    end
    push!(lines, "",
        "A screened-not-evaluated entry is a workload decision, not an AC-security certificate.", "",
        "Connected outages use fixed-base preventive participation. Island-aware outcomes validate only the retained component, with independent OPF redispatch; discarded components are not balanced. Full AC coverage means each route was evaluated, not every island was validated. Discarded load is excluded demand, not a claim that its local service is physically impossible. Dynamic security is outside scope.")
    join(lines, "\n")
end
