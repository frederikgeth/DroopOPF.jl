import SHA

# Canonical encoding avoids depending on dictionary insertion order.
function _campaign_canonical(value)
    if value isa AbstractDict
        return "{" * join([JSON.json(string(k)) * ":" * _campaign_canonical(value[k])
            for k in sort!(collect(keys(value)); by=string)], ",") * "}"
    elseif value isa AbstractVector
        return "[" * join(_campaign_canonical.(value), ",") * "]"
    end
    JSON.json(value)
end
_campaign_digest(value) = bytes2hex(SHA.sha256(_campaign_canonical(_json_data(value))))

function _campaign_atomic(path, value)
    temporary, io = mktemp(dirname(path))
    try
        JSON.json(io, value; pretty=true)
        close(io)
        mv(temporary, path; force=true)
    finally
        isopen(io) && close(io)
        isfile(temporary) && rm(temporary)
    end
    path
end

function _campaign_restore(data, case, base, entry, decision, catalog, participation, audited)
    # Recompute all validation and ranking; cached PASS flags are never trusted.
    outcome = Symbol(data["outcome"])
    outcome == :evaluation_error && return nothing # errors are retried
    exact = nothing
    island = nothing
    if decision.action == :exact || audited
        outcome == (audited ? :screened_audited : :exact_evaluated) || return nothing
        result = _scopf_result_from_data(data["exact_assessment"]["result"])
        _json_data(get(result.states, :base, nothing)) == _json_data(base) || return nothing
        study = Study(case; contingencies=[entry.contingency], participation)
        report = equilibrium_report(study, result)
        exact = ContingencyAssessment(entry.contingency, result, report,
            only(rank_contingencies(catalog, report)))
    elseif decision.action == :island_aware
        outcome == :island_evaluated || return nothing
        scenario = islanded_scenario_case(case, entry.contingency, base)
        saved = data["island_assessment"]["result"]
        state = saved["state"]
        isnothing(state) && return nothing
        acstate = ACState((Float64.(state[k]) for k in ("vm", "va", "pg", "qg"))...)
        result = ACOPFResult(acstate,
            isnothing(saved["objective"]) ? NaN : Float64(saved["objective"]),
            Symbol(saved["termination_status"]), Symbol(saved["primal_status"]),
            (isnothing(saved[k]) ? nothing : Float64(saved[k]) for k in
                ("smooth_epsilon", "smooth_reactive_relative_epsilon", "smooth_reactive_epsilon"))...)
        island = IslandedContingencyAssessment(scenario.selection, scenario.case,
            result, equilibrium_report(scenario.case, result))
    else
        outcome == :screened || return nothing
    end
    rank = _pipeline_rank(entry, decision; exact, island, audited)
    ContingencyPipelineAssessment(entry, decision, outcome, exact, island, nothing, rank)
end

"""
    run_contingency_campaign(directory, case, base_state; ...)

Run the integrated pipeline with atomic per-outage JSON checkpoints. Resume
requires identical case, catalog, base state, participation, screening/audit
policy, solver settings, Julia version, source and dependency environment.
Mismatched contracts are rejected without overwriting prior evidence. Corrupt
checkpoints and evaluation errors are rerun; saved states are independently
revalidated. A directory lock prevents concurrent writers. `on_checkpoint`
is a progress callback after durable writes (and can interrupt the campaign).
Returns `(result, resumed_count, evaluated_count, fingerprint)`.
"""
function run_contingency_campaign(directory::AbstractString, case::Case, base::ACState;
    catalog::ContingencyCatalog=contingency_catalog(case),
    participation::AbstractDict=default_participation(case),
    screening_enabled::Bool=true, audit_screened_ids::AbstractVector{Symbol}=Symbol[],
    loading_threshold::Real=0.8, voltage_guard::Real=0.02, lodf_tolerance::Real=1e-8,
    reactive_guard::Real=0.1, ac_risk_guard::Bool=true, droop_response_guard::Bool=false,
    smooth_epsilon::Real=1e-4,
    sparse_balance::Bool=false,
    workers::Integer=1,
    optimizer_attributes::AbstractDict=Dict("max_iter"=>1000, "max_cpu_time"=>120.0),
    on_checkpoint=identity)
    validate_equilibrium(case, base).valid || throw(ArgumentError("base state must independently validate"))
    source = Dict(basename(p)=>bytes2hex(SHA.sha256(read(p))) for p in
        readdir(@__DIR__; join=true) if endswith(p, ".jl"))
    project = isnothing(Base.active_project()) ? dirname(@__DIR__) : dirname(Base.active_project())
    environment = Dict(name => isfile(joinpath(project,name)) ?
        bytes2hex(SHA.sha256(read(joinpath(project,name)))) : nothing
        for name in ("Project.toml", "Manifest.toml", "Manifest-v$(VERSION.major).$(VERSION.minor).toml"))
    policy = (; active_response="limit_aware_v1", screening_enabled, audit_screened_ids=sort(unique(audit_screened_ids)),
        loading_threshold, voltage_guard, lodf_tolerance, reactive_guard, ac_risk_guard, droop_response_guard, smooth_epsilon,
        optimizer_attributes, participation, sparse_balance, workers)
    contract = _json_data((; schema_version=1, case, base, catalog, policy,
        julia_version=string(VERSION), ipopt_version=string(Base.pkgversion(Ipopt)),
        jump_version=string(Base.pkgversion(JuMP)), source, environment))
    fingerprint = _campaign_digest(contract)
    mkpath(directory)
    lock = joinpath(directory, ".campaign-lock")
    ispath(lock) && throw(ArgumentError("campaign directory is locked; verify no writer is active before removing the lock"))
    mkdir(lock)
    resumed = Ref(0)
    evaluated = Ref(0)
    try
        manifest = joinpath(directory, "campaign-inputs.json")
        if isfile(manifest)
            saved = JSON.parsefile(manifest)
            get(saved, "fingerprint", nothing) == fingerprint &&
                _campaign_digest(saved["contract"]) == fingerprint ||
                throw(ArgumentError("campaign inputs/settings/code changed; use a new output directory"))
        else
            isempty(setdiff(readdir(directory), [".campaign-lock"])) ||
                throw(ArgumentError("nonempty directory has no campaign contract; use a new output directory"))
            _campaign_atomic(manifest, Dict("fingerprint"=>fingerprint, "contract"=>contract))
        end
        checkpoint_dir = joinpath(directory, "checkpoints")
        mkpath(checkpoint_dir)
        # Index-based paths do not use user-supplied identifiers as filenames.
        indices = Dict(e.contingency.id=>i for (i,e) in enumerate(catalog.entries))
        checkpoint_path(entry) = joinpath(checkpoint_dir, "$(indices[entry.contingency.id]).json")
        loader = function(entry, decision, audited)
            path = checkpoint_path(entry)
            isfile(path) || return nothing
            restored = try
                saved = JSON.parsefile(path)
                saved["fingerprint"] == fingerprint || return nothing
                _campaign_digest(saved["assessment"]) == saved["checksum"] || return nothing
                data = saved["assessment"]
                _campaign_canonical(data["entry"]) == _campaign_canonical(_json_data(entry)) || return nothing
                _campaign_canonical(data["decision"]) == _campaign_canonical(_json_data(decision)) || return nothing
                _campaign_restore(data, case, base, entry, decision, catalog, participation, audited)
            catch error
                error isa InterruptException && rethrow()
                nothing
            end
            isnothing(restored) || (resumed[] += 1)
            restored
        end
        checkpoint = function(assessment)
            data = _json_data(assessment)
            _campaign_atomic(checkpoint_path(assessment.entry),
                Dict("fingerprint"=>fingerprint, "checksum"=>_campaign_digest(data), "assessment"=>data))
            evaluated[] += 1
            on_checkpoint(assessment)
        end
        result = assess_contingency_pipeline(case, base; catalog, participation,
            screening_enabled, audit_screened_ids, loading_threshold, voltage_guard,
            lodf_tolerance, reactive_guard, ac_risk_guard, droop_response_guard, smooth_epsilon, optimizer_attributes, sparse_balance, workers,
            _assessment_loader=loader, _assessment_callback=checkpoint)
        _campaign_atomic(joinpath(directory,"campaign.json"),
            Dict("fingerprint"=>fingerprint, "resumed_count"=>resumed[],
                "evaluated_count"=>evaluated[], "data"=>_json_data(result)))
        write(joinpath(directory,"campaign.md"), markdown_report(result) * "\n\n" *
            "Fingerprint: `$fingerprint`. Reused $(resumed[]) checkpoints; executed $(evaluated[]) routes. Full input contract: campaign-inputs.json.\n")
        return (; result, resumed_count=resumed[], evaluated_count=evaluated[], fingerprint)
    finally
        rm(lock) # only the empty lock directory owned by this invocation
    end
end

"""
    validate_contingency_filter(case, base_state; ...)

Compare screening with exhaustive AC routes on the same catalog and base.
Returns per-device-family counts of screened unresolved results, confirmed
physical failures, and recall of unresolved outcomes at each ranking budget.
An unresolved result includes solver rejection/error and is not a proof of
infeasibility. Zero observed misses is evidence only for this input set.
"""
function validate_contingency_filter(case::Case, base::ACState;
    catalog::ContingencyCatalog=contingency_catalog(case),
    loading_threshold::Real=0.8, voltage_guard::Real=0.02,
    reactive_guard::Real=0.1, ac_risk_guard::Bool=true, droop_response_guard::Bool=false, kwargs...)
    decisions = filter_contingencies(case, base; catalog, loading_threshold, voltage_guard,
        reactive_guard, ac_risk_guard, droop_response_guard, participation=get(kwargs,:participation,default_participation(case)))
    exact = assess_contingency_pipeline(case, base; catalog, screening_enabled=false, loading_threshold, voltage_guard,
        reactive_guard, ac_risk_guard, droop_response_guard, kwargs...)
    by_id = Dict(a.entry.contingency.id=>a for a in exact.assessments)
    rows = NamedTuple[]
    for kind in (:line, :transformer, :generator)
        family = filter(d -> d.device_kind == kind, decisions)
        unresolved = [d for d in family if by_id[d.contingency_id].rank.classification != :accepted]
        missed = filter(d -> d.action == :screened, unresolved)
        physical = count(d -> begin
            a = by_id[d.contingency_id]
            !isnothing(a.exact_assessment) &&
                haskey(a.exact_assessment.report.scenarios,d.contingency_id) &&
                !a.exact_assessment.report.physical_valid ||
                !isnothing(a.island_assessment) && !a.island_assessment.report.validation.valid
        end, missed)
        # Operational evaluation order: mandatory routes before screened entries,
        # then descending predicted loading with stable identifier tie-breaks.
        ordered = sort(family; by=d -> (d.action == :screened,
            -something(d.predicted_loading, 0.0), string(d.contingency_id)))
        unresolved_ids = Set(d.contingency_id for d in unresolved)
        budgets = [(budget=k, found=count(d -> d.contingency_id in unresolved_ids, ordered[1:k]),
            total=length(unresolved_ids)) for k in 0:length(ordered)]
        push!(rows, (; device_kind=kind, total=length(family),
            screened=count(d -> d.action == :screened, family),
            unresolved=length(unresolved), screened_unresolved=length(missed),
            screened_physical_failures=physical, ranking_budgets=budgets))
    end
    (; case, base_state=base, catalog,
        settings=(;loading_threshold,voltage_guard,reactive_guard,ac_risk_guard,droop_response_guard,solver_options=Dict(kwargs)),
        decisions, exact, families=rows,
        no_observed_misses=all(row.screened_unresolved == 0 for row in rows))
end
