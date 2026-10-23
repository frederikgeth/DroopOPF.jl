"""Shared multi-controller droop design and its ordinary SCOPF scenario states."""
struct SCOPFDroopDesignResult
    controls::Vector{DroopControl}
    reference_settings::Dict{Int,DroopSettings{Float64}}
    settings::Dict{Int,DroopSettings{Float64}}
    result::SCOPFResult
end

"""Optimize several shared droop curves using the normal smooth SCOPF builder.

The Study equipment and active-response policies are preserved. Explicit mixed
assignments may design matching attached droop controls. Initial states
are numerical starts only; independently replay the returned exact curves.
"""
function optimize_droop_parameters(study::Study, controls::AbstractVector{<:DroopControl};
    smooth_epsilon::Real=1e-5, initial_states::AbstractDict=Dict(), kwargs...)
    study = _validated_study(study)
    _check_mixed_design(study.case,study.reactive_assignments,controls)
    length(unique(c.control_id for c in controls)) == length(controls) ||
        throw(ArgumentError("duplicate droop control IDs"))
    policies = Dict(c.control_id => _joint_droop_policy(study.case, c) for c in controls)
    forbidden = (:encoding, :fixed_base_state, :_droop_parameter_builder,
        :_phase1_power_balance, :_model_hook)
    any(k in keys(kwargs) for k in forbidden) &&
        throw(ArgumentError("design owns the encoding, base freedom and model hooks"))
    get(kwargs, :optimizer_factory, Ipopt.Optimizer) === CCOpt.Optimizer &&
        throw(ArgumentError("multi-controller SCOPF design currently uses smooth NLP solvers"))
    parameters = Dict{Int,NamedTuple}()
    captured = Ref{Any}(nothing)
    function build_parameters(model)
        captured[] = model
        for c in controls
            p = policies[c.control_id]
            names = keys(p.ranges)
            parameters[c.control_id] = NamedTuple{names}(Tuple(
                _droop_design_variable(model, "security_$(c.control_id)_$k",
                    getfield(p.ranges,k), getfield(p.initial,k)) for k in names))
        end
        parameters
    end
    result = solve_scopf(study; smooth_epsilon, initial_states,
        _droop_parameter_builder=build_parameters, kwargs...)
    settings = Dict{Int,DroopSettings{Float64}}()
    if has_values(captured[])
        for c in controls
            values = [_droop_design_value(getfield(parameters[c.control_id], k))
                for k in (:slope,:v_ref,:deadband_low,:deadband_high)]
            all(isfinite, values) || continue
            # Failed iterates may lie outside even the physical settings domain.
            try
                settings[c.control_id] = DroopSettings(Float64.(values)...)
            catch error
                error isa ArgumentError || rethrow()
            end
        end
    end
    references = Dict(c.control_id => _float_settings(DroopSettings(
        study.case.controls[c.control_id])) for c in controls)
    assignments=_settings_assignments(study.case,study.reactive_assignments,settings)
    result=SCOPFResult(result.states,result.balancing_power,result.objective,result.termination_status,
        result.primal_status,result.mode,result.encoding,result.smooth_epsilon,
        result.smooth_reactive_relative_epsilon,result.smooth_reactive_epsilon,result.solver,
        assignments,result.tap_settings,result.shunt_settings,result.tap_controls,result.shunt_controls,result.control_policy)
    SCOPFDroopDesignResult(collect(controls), references, settings, result)
end

"""Reconstruct all shared curves while retaining the complete Study policy."""
function with_droop_settings(study::Study, design::SCOPFDroopDesignResult)
    Set(keys(design.settings)) == Set(c.control_id for c in design.controls) ||
        throw(ArgumentError("design has missing controller settings"))
    for id in sort(collect(keys(design.settings)))
        study = with_droop_settings(study, id, design.settings[id])
    end
    study
end

"""Check shared parameter bounds and independently replay exact SCOPF physics."""
function validate_droop_design(study::Study, design::SCOPFDroopDesignResult;
    setting_tolerance::Real=1e-8, kwargs...)
    isfinite(setting_tolerance) && setting_tolerance >= 0 ||
        throw(ArgumentError("invalid setting tolerance"))
    ids = [c.control_id for c in design.controls]
    complete = length(unique(ids)) == length(ids) && Set(keys(design.settings)) == Set(ids)
    complete || return (valid=false, policy_valid=false, report=nothing)
    policy_valid = all(design.controls) do c
        p = _joint_droop_policy(study.case,c)
        all(keys(p.ranges)) do k
            lo, hi = getfield(p.ranges,k)
            lo-setting_tolerance <= getfield(design.settings[c.control_id],k) <= hi+setting_tolerance
        end
    end
    report = equilibrium_report(with_droop_settings(study,design), design.result; kwargs...)
    (; valid=policy_valid && report.valid, policy_valid, report)
end

"""One design round, including all executed independent assessments and errors."""
struct DroopSecurityIteration
    iteration::Int
    study::Study
    design::SCOPFDroopDesignResult
    policy_valid::Bool
    report::Union{Nothing,SCOPFReport}
    decisions::Vector{ContingencyFilterDecision}
    assessments::Vector{ContingencyAssessment}
    errors::Dict{Symbol,String}
    added_ids::Vector{Symbol}
    exhaustive_audit::Bool
    master_seconds::Float64
    assessment_seconds::Float64
end

"""Contingency-addition result; eligible acceptance and full N-1 coverage differ."""
struct DroopSecurityResult
    status::Symbol
    eligible_accepted::Bool
    full_n1_accepted::Bool
    catalog::ContingencyCatalog
    iterations::Vector{DroopSecurityIteration}
end

# Freeze the solved base equipment solely for computing physical screening data.
function _droop_security_base_case(study, result)
    case = study.case
    isempty(study.tap_controls) ||
        (case = with_tap_settings(case,result.tap_settings[:base]))
    isempty(study.shunt_controls) ||
        (case = with_shunt_settings(case,result.shunt_settings[:base]))
    case
end

function _droop_security_assess!(assessments, errors, study, result, entries;
    solver_kwargs, validation_kwargs)
    base = result.states[:base]
    for entry in entries
        try
            single = _copy_study(study; contingencies=[entry.contingency])
            starts = Dict(id=>state for (id,state) in result.states
                if id in (:base,entry.contingency.id) && !isnothing(state))
            solved = evaluate_contingencies(single,base; initial_states=starts,
                fixed_base_tap_settings=get(result.tap_settings,:base,Dict()),
                fixed_base_shunt_settings=get(result.shunt_settings,:base,Dict()),
                solver_kwargs...)
            report = equilibrium_report(single,solved; validation_kwargs...)
            rank = only(rank_contingencies(ContingencyCatalog(study.case.id,[entry]),report))
            push!(assessments,ContingencyAssessment(entry.contingency,solved,report,rank))
        catch error
            error isa InterruptException && rethrow()
            errors[entry.contingency.id] = sprint(showerror,error)
        end
    end
end

"""
    optimize_droop_security(study, controls; catalog=contingency_catalog(study.case), ...)

Iteratively add unresolved N-1 outages to shared droop design. Study contingencies
are the initial training set and must use catalog identities. Every successful
termination requires independent full AC assessment of all eligible catalog
entries at the final settings/base. Excluded islands and catalog subsets cannot
produce full_n1_accepted. Errors, rejected masters and round limits are retained.
The callback receives a complete immutable round after its decisions are made.
"""
function optimize_droop_security(study::Study, controls::AbstractVector{<:DroopControl};
    catalog::ContingencyCatalog=contingency_catalog(study.case),
    max_rounds::Integer=5, batch_size::Integer=2, screening_enabled::Bool=true,
    filter_kwargs::NamedTuple=(;), solver_kwargs::NamedTuple=(;),
    evaluation_kwargs::NamedTuple=(;), validation_kwargs::NamedTuple=(;),
    initial_states::AbstractDict=Dict(), on_iteration=identity)
    study = _validated_study(study)
    max_rounds > 0 && batch_size > 0 || throw(ArgumentError("round and batch limits must be positive"))
    canonical = contingency_catalog(study.case)
    by_id = Dict(e.contingency.id=>e for e in canonical.entries)
    catalog.case_id == study.case.id || throw(ArgumentError("catalog case mismatch"))
    length(unique(e.contingency.id for e in catalog.entries)) == length(catalog.entries) ||
        throw(ArgumentError("duplicate catalog entries"))
    all(e -> haskey(by_id,e.contingency.id) &&
        _json_data(e) == _json_data(by_id[e.contingency.id]), catalog.entries) ||
        throw(ArgumentError("catalog does not match current network"))
    eligible = [e for e in catalog.entries if e.disposition == :eligible]
    allowed = Dict(e.contingency.id=>e for e in eligible)
    all(c -> haskey(allowed,c.id) && _json_data(c) == _json_data(allowed[c.id].contingency),
        study.contingencies) || throw(ArgumentError("training outages must match eligible catalog entries"))
    # Evaluation must replay the master's physical encoding; only solver settings
    # may differ. Explicitly reject overrides that could change the audit problem.
    audit_allowed = (:optimizer_factory,:optimizer_attributes,:silent)
    all(k in audit_allowed for k in keys(evaluation_kwargs)) ||
        throw(ArgumentError("evaluation overrides may only select solver, limits and logging"))
    eval_options = merge((;smooth_epsilon=1e-5),solver_kwargs,evaluation_kwargs)
    audit_validation = (; (k=>v for (k,v) in pairs(validation_kwargs) if k != :setting_tolerance)...)
    forbidden = (:initial_states,:fixed_base_state,:fixed_base_tap_settings,
        :fixed_base_shunt_settings,:_phase1_power_balance,:_droop_parameter_builder,:_model_hook,:encoding)
    any(k in keys(solver_kwargs) for k in forbidden) &&
        throw(ArgumentError("security driver owns states, encoding and fixed-base audit"))
    training = copy(study.contingencies)
    rounds = DroopSecurityIteration[]
    starts = initial_states
    current_controls = collect(controls)
    status = :iteration_limit
    eligible_accepted = false
    for round in 1:max_rounds
        master = _copy_study(study; contingencies=training)
        seconds = @elapsed design = optimize_droop_parameters(master,current_controls;
            initial_states=starts,solver_kwargs...)
        validation = validate_droop_design(master,design;validation_kwargs...)
        assessments = ContingencyAssessment[]
        errors = Dict{Symbol,String}()
        decisions = ContingencyFilterDecision[]
        added = Symbol[]
        exhaustive = false
        assessment_seconds = 0.0
        if !validation.valid
            status = :master_rejected
        else
            optimized = with_droop_settings(master,design)
            basecase = _droop_security_base_case(optimized,design.result)
            assessment_seconds = @elapsed begin
                decisions = filter_contingencies(basecase,design.result.states[:base];
                    catalog,merge((;participation=optimized.participation),filter_kwargs)...)
                decision_by_id = Dict(d.contingency_id=>d for d in decisions)
                required = [e for e in eligible if !screening_enabled ||
                    decision_by_id[e.contingency.id].action != :screened]
                _droop_security_assess!(assessments,errors,optimized,design.result,required;
                    solver_kwargs=eval_options,validation_kwargs=audit_validation)
                unresolved = [a.contingency.id for a in assessments if !a.report.valid]
                append!(unresolved,keys(errors))
                trained = Set(c.id for c in training)
                # An apparent screened pass always triggers the exhaustive audit.
                # Also audit at the final round, even when the design is unresolved.
                if isempty(setdiff(unresolved,trained)) || round == max_rounds
                    evaluated = union(Set(a.contingency.id for a in assessments),Set(keys(errors)))
                    omitted = [e for e in eligible if !(e.contingency.id in evaluated)]
                    _droop_security_assess!(assessments,errors,optimized,design.result,omitted;
                        solver_kwargs=eval_options,validation_kwargs=audit_validation)
                end
                exhaustive = length(assessments)+length(errors) == length(eligible)
                # Reject/error first, then larger independently measured violations.
                priority(a) = maximum([0.0; [max(r.power_balance_max/a.report.tolerances.power_tolerance,
                    r.droop_residual_max/a.report.tolerances.droop_tolerance) for r in values(a.report.scenarios)]])
                bad = sort([a for a in assessments if !a.report.valid];
                    by=a -> (-priority(a),string(a.contingency.id)))
                unresolved = unique([sort(collect(keys(errors));by=string);
                    [a.contingency.id for a in bad]])
                new_ids = [id for id in unresolved if !(id in trained)]
                if exhaustive && isempty(unresolved)
                    eligible_accepted = true
                    status = :eligible_secure
                elseif !isempty(new_ids) && round < max_rounds
                    added = new_ids[1:min(batch_size,length(new_ids))]
                    append!(training,[allowed[id].contingency for id in added])
                else
                    status = round == max_rounds && !isempty(new_ids) ? :iteration_limit : :audit_unresolved
                end
            end
        end
        item = DroopSecurityIteration(round,master,design,validation.policy_valid,
            validation.report,decisions,assessments,errors,added,exhaustive,
            seconds,assessment_seconds)
        push!(rounds,item)
        on_iteration(item)
        isempty(added) && break
        starts = Dict(id=>state for (id,state) in design.result.states if !isnothing(state))
        # Transfer accepted witnesses only; failed evaluation states are not seeds.
        for a in assessments
            a.report.valid || continue
            starts[a.contingency.id] = a.result.states[a.contingency.id]
        end
        ids = Set([:base; [c.id for c in training]])
        filter!(p -> first(p) in ids,starts)
        current_controls = map(controls) do c
            ranges = _joint_droop_policy(study.case,c).ranges
            settings = design.settings[c.control_id]
            # This projection affects the next numerical start only. The saved
            # design and its independent physical/bound checks stay unchanged.
            initial = DroopSettings((clamp(getfield(settings,k),getfield(ranges,k)...)
                for k in (:slope,:v_ref,:deadband_low,:deadband_high))...)
            DroopControl(c.control_id;
                slope_bounds=c.bounds.slope,v_ref_bounds=c.bounds.v_ref,
                deadband_low_bounds=c.bounds.deadband_low,deadband_high_bounds=c.bounds.deadband_high,
                initial)
        end
    end
    full_catalog = Set(e.contingency.id for e in catalog.entries) == Set(keys(by_id))
    full_n1 = eligible_accepted && full_catalog && isempty(excluded_contingencies(catalog))
    DroopSecurityResult(status,eligible_accepted,full_n1,catalog,rounds)
end

for T in (DroopControl,SCOPFDroopDesignResult,DroopSecurityIteration,DroopSecurityResult)
    @eval function _json_data(x::$T)
        data = Dict{String,Any}()
        for k in fieldnames($T)
            data[string(k)] = Base.invokelatest(_json_data,getfield(x,k))
        end
        data
    end
end

"""Persist shared droop settings, complete iteration evidence and final coverage."""
write_droop_security(path::AbstractString,result::Union{SCOPFDroopDesignResult,DroopSecurityResult}) =
    _write_scopf_json(path,"DroopOPF.$(nameof(typeof(result)))",result)

"""Summarize contingency addition without converting unresolved cases into passes."""
function markdown_report(result::DroopSecurityResult)
    lines = ["# Droop security design", "", "- Status: `$(result.status)`",
        "- Eligible catalog accepted: $(result.eligible_accepted)",
        "- Full network N-1 accepted: $(result.full_n1_accepted)",
        "- Excluded islands: $(length(excluded_contingencies(result.catalog)))", "",
        "| Round | Training | Objective | Master valid | AC evaluations | Errors | Full audit | Added | Seconds |",
        "|---:|---:|---:|---|---:|---:|---|---|---:|"]
    for r in result.iterations
        valid = r.policy_valid && !isnothing(r.report) && r.report.valid
        push!(lines,"| $(r.iteration) | $(length(r.study.contingencies)) | $(r.design.result.objective) | $valid | $(length(r.assessments)) | $(length(r.errors)) | $(r.exhaustive_audit) | $(join(r.added_ids, ", ")) | $(r.master_seconds+r.assessment_seconds) |")
    end
    join(lines,"\n") * "\n\nAcceptance is steady-state and local, with declared solver budgets and exact physical replay.\n"
end
