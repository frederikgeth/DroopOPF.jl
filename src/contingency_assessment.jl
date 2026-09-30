"""One independently validated fixed-base evaluation from a contingency catalog."""
struct ContingencyAssessment
    contingency::Contingency
    result::SCOPFResult
    report::SCOPFReport
    rank::ContingencyRank
end

"""
    evaluate_contingency_catalog(case, base_state; catalog, participation, kwargs...)

Evaluate every structurally eligible catalog entry as an independent fixed-base
problem. The base state must independently validate. Excluded entries remain in
the catalog and are never silently treated as safe.
"""
function evaluate_contingency_catalog(case::Case, base_state::ACState;
    catalog::ContingencyCatalog=contingency_catalog(case),
    participation::AbstractDict=Dict(g.id => 1.0 for g in case.generators if g.available),
    kwargs...)
    catalog.case_id == case.id || throw(ArgumentError("catalog case ID does not match case"))
    validate_equilibrium(case, base_state).valid ||
        throw(ArgumentError("base state must independently validate"))
    assessments = ContingencyAssessment[]
    for contingency in eligible_contingencies(catalog)
        study = Study(case; contingencies=[contingency], participation=participation)
        result = evaluate_contingencies(study, base_state; kwargs...)
        report = equilibrium_report(study, result)
        ranks = rank_contingencies(catalog, report)
        length(ranks) == 1 || error("one-outage assessment did not produce one rank")
        push!(assessments, ContingencyAssessment(contingency, result, report, only(ranks)))
    end
    return assessments
end
