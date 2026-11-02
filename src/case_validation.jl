export validate_imported_state

function _io_import_validation_signature(c, s, md)
    evidence = (ratings=sort!(collect(md.branch_rating_mva);by=first),
        presence=[(key,get(md.saved_field_presence,key,Symbol[])) for key in (:VM,:VA,:PG,:QG)])
    bytes2hex(SHA.sha256(codeunits(_io_model_signature(c)*_io_model_encoding(s)*JSON.json(evidence))))
end

"""
    validate_imported_state(imported; power_tolerance_mw=0.01,
        reactive_tolerance_mvar=0.01, limit_tolerance_pu=1e-6)

Evaluate the imported operating state without solving. Return a JSON-compatible
report separating numerical AC consistency, source saved-field evidence and
original thermal-rating coverage. A substituted unrated limit never becomes
an engineering rating. `valid` requires all three plus supported operating
limits; it covers the static AC import profile, not source automatic controls.
The legacy RAW validation APIs and their report schemas remain unchanged.
"""
function validate_imported_state(imported::CaseImport;
    power_tolerance_mw=0.01, reactive_tolerance_mvar=0.01, limit_tolerance_pu=1e-6)
    all(x -> x isa Real && !(x isa Bool) && isfinite(x) && x >= 0,
        (power_tolerance_mw, reactive_tolerance_mvar, limit_tolerance_pu)) ||
        throw(ArgumentError("validation tolerances must be finite and nonnegative"))
    c = imported.case; s = imported.initial_state; md = imported.metadata
    _io_import_validation_signature(c,s,md) == imported.validation_signature ||
        _io_error(:import_context_mismatch, :validate,
            "imported model, state or source evidence changed; validate the original snapshot")
    length(s.vm) == length(s.va) == length(c.network.buses) &&
        length(s.pg) == length(s.qg) == length(c.generators) ||
        _io_error(:state_shape_mismatch, :validate, "imported state dimensions do not match case")
    missing = String[]
    for (kind, items, fields) in ((:bus, c.network.buses, (:VM,:VA)),
        (:generator, c.generators, (:PG,:QG))), field in fields
        evidence = get(md.saved_field_presence, field, Symbol[])
        length(evidence) == length(items) || isempty(evidence) ||
            _io_error(:invalid_presence_evidence, :validate, "$field evidence dimensions do not match case")
        for (i,item) in enumerate(items)
            presence = isempty(evidence) ? :unknown : evidence[i]
            presence == :supplied || push!(missing, "$kind $(item.id): $field $presence")
        end
    end
    balance = power_balance(c,s)
    peak_p = maximum(abs,balance.active;init=0.) * c.base_power
    peak_q = maximum(abs,balance.reactive;init=0.) * c.base_power
    consistent = peak_p <= power_tolerance_mw && peak_q <= reactive_tolerance_mvar
    flows = branch_flows(c.network,s)
    unrated = Int[]; thermal_violations = Int[]; branch_rows = Dict{String,Any}[]
    for (i,b) in enumerate(c.network.branches)
        rating = get(md.branch_rating_mva,b.id,nothing)
        isnothing(rating) || (isfinite(rating) && rating > 0) ||
            _io_error(:invalid_rating_evidence, :validate, "invalid source rating for branch $(b.id)")
        from = flows.from[i] * c.base_power; to = flows.to[i] * c.base_power
        margin = isnothing(rating) ? nothing : rating - max(abs(from),abs(to))
        b.available && isnothing(rating) && push!(unrated,b.id)
        b.available && !isnothing(margin) && margin < -limit_tolerance_pu*c.base_power &&
            push!(thermal_violations,b.id)
        push!(branch_rows,Dict("branch_id"=>b.id,"available"=>b.available,
            "normal_rating_mva"=>rating,"thermal_margin_mva"=>margin,
            "p_from_mw"=>real(from),"q_from_mvar"=>imag(from),
            "p_to_mw"=>real(to),"q_to_mvar"=>imag(to)))
    end
    eq = validate_equilibrium(c,s;limit_tolerance=limit_tolerance_pu)
    violations = Symbol[v for v in eq.violations if !(v in (:power_balance,:branch_thermal))]
    isempty(thermal_violations) || push!(violations,:branch_thermal)
    limits_valid = isempty(violations)
    complete = isempty(missing); thermal_complete = isempty(unrated)
    valid = consistent && complete && thermal_complete && limits_valid
    status = !complete ? "saved_evidence_incomplete" : !consistent ? "power_flow_mismatch" :
        !limits_valid ? "limits_violated" : !thermal_complete ? "limits_unassessed" : "passed"
    Dict{String,Any}("schema_version"=>1,"kind"=>"DroopOPF.ImportedStateValidation",
        "source"=>imported.source.path,"source_text_sha256"=>imported.source.sha256,
        "backend"=>string(imported.source.backend),"format"=>string(imported.source.format),
        "status"=>status,"valid"=>valid,"power_flow_consistent"=>consistent,
        "saved_state_complete"=>complete,"missing_saved_fields"=>missing,
        "known_limits_valid"=>limits_valid,"thermal_coverage_complete"=>thermal_complete,
        "unrated_branches"=>unrated,"thermal_violations"=>thermal_violations,
        "limit_violations"=>string.(violations),"max_p_mismatch_mw"=>peak_p,
        "max_q_mismatch_mvar"=>peak_q,"branch_flows"=>branch_rows,
        "tolerances"=>Dict("power_mw"=>power_tolerance_mw,"reactive_mvar"=>reactive_tolerance_mvar,
            "limits_pu"=>limit_tolerance_pu),"optimization_performed"=>false,
        "scope"=>"Imported static AC profile only; no source control, solver or dynamic certification.")
end
