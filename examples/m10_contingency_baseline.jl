using DroopOPF
using SHA

"""Return the bundled PGLib source for a named public test case."""
function m10_source(name::AbstractString)
    filename = name == "118" ? "pglib_opf_case118_ieee.m" :
        name == "300" ? "pglib_opf_case300_ieee.m" :
        throw(ArgumentError("case must be 118 or 300"))
    return joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07", filename)
end

"""
    m10_contingency_baseline(name, output; batch_size=1, batch_number=1)

Create a deterministic N-1 catalog and evaluate one numbered batch of its
eligible contingencies against one independently validated fixed base OPF
state.  This is a security *assessment* baseline, not a security-constrained
redispatch optimization.  Run every batch before drawing a conclusion about a
case; islanding outages remain recorded as unsupported exclusions.
"""
function m10_contingency_baseline(name::AbstractString, output::AbstractString;
    batch_size::Integer=1, batch_number::Integer=1)
    batch_size > 0 || throw(ArgumentError("batch_size must be positive"))
    batch_number > 0 || throw(ArgumentError("batch_number must be positive"))
    mkpath(output)
    source = m10_source(name)
    case = load_matpower_case(source; base_frequency=60.0)
    catalog = contingency_catalog(case)
    eligible = eligible_contingencies(catalog)
    first_index = (batch_number - 1) * batch_size + 1
    first_index <= length(eligible) || throw(ArgumentError("batch_number exceeds eligible catalog"))
    last_index = min(first_index + batch_size - 1, length(eligible))
    batch = eligible[first_index:last_index]

    write_contingency_catalog(joinpath(output, "catalog.json"), catalog)
    write(joinpath(output, "catalog.md"), markdown_report(catalog) * "\n")

    base = solve_opf(case)
    base_report = equilibrium_report(case, base)
    write(joinpath(output, "baseline.md"), "# M10 fixed-base assessment\n\n" *
        "- Source SHA-256: `$(bytes2hex(sha256(read(source))))`\n" *
        "- Eligible catalog entries: $(length(eligible))\n" *
        "- Structurally excluded entries: $(length(excluded_contingencies(catalog)))\n" *
        "- Batch: $(first_index)-$(last_index) of $(length(eligible))\n" *
        "- Base solver status: `$(base.termination_status)`\n" *
        "- Base independently valid: `$(base_report.valid)`\n\n" *
        "This evaluates each listed outage while holding the validated base state fixed. " *
        "It does not claim a SCOPF redispatch solution or safety for omitted batches.\n")
    base_report.valid || error("base OPF did not independently validate")

    participation = Dict(g.id => 1.0 for g in case.generators if g.available)
    study = Study(case; contingencies=batch, participation=participation)
    result = evaluate_contingencies(study, base.state)
    report = equilibrium_report(study, result)
    ranks = rank_contingencies(catalog, report)
    write_study(joinpath(output, "study.json"), study)
    write_scopf_result(joinpath(output, "result.json"), result)
    write_scopf_report(joinpath(output, "report.json"), report)
    write_contingency_ranking(joinpath(output, "ranking.json"), ranks)
    write(joinpath(output, "report.md"), markdown_report(report) * "\n")
    write(joinpath(output, "ranking.md"), markdown_report(ranks) * "\n")
    println("M10 assessed $(length(batch)) eligible contingencies in $(abspath(output))")
    return (; catalog, study, result, report, ranks)
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    name = get(ARGS, 1, "118")
    output = abspath(get(ARGS, 2, joinpath(pwd(), "m10_contingency_baseline")))
    batch_size = parse(Int, get(ARGS, 3, "1"))
    batch_number = parse(Int, get(ARGS, 4, "1"))
    m10_contingency_baseline(name, output; batch_size, batch_number)
end
