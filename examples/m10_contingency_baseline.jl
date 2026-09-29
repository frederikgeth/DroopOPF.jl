using DroopOPF
using SHA
using JSON

"""Return the bundled PGLib source for a named public test case."""
function m10_source(name::AbstractString)
    filename = name == "118" ? "pglib_opf_case118_ieee.m" :
        name == "300" ? "pglib_opf_case300_ieee.m" :
        throw(ArgumentError("case must be 118 or 300"))
    return joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07", filename)
end

function m10_write_base_cache(path::AbstractString, source::AbstractString,
    case::Case, result::ACOPFResult)
    report = equilibrium_report(case, result)
    report.valid || error("refusing to cache a base OPF that did not independently validate")
    state = result.state
    document = Dict(
        "schema_version" => 1,
        "kind" => "DroopOPF.M10BaseState",
        "source_sha256" => bytes2hex(sha256(read(source))),
        "case_id" => case.id,
        "termination_status" => string(result.termination_status),
        "primal_status" => string(result.primal_status),
        "objective" => result.objective,
        "smooth_epsilon" => result.smooth_epsilon,
        "smooth_reactive_relative_epsilon" => result.smooth_reactive_relative_epsilon,
        "smooth_reactive_epsilon" => result.smooth_reactive_epsilon,
        "state" => Dict("vm" => state.vm, "va" => state.va,
            "pg" => state.pg, "qg" => state.qg),
    )
    open(path, "w") do io
        JSON.print(io, document, 4)
        println(io)
    end
    return (; state, report, cached=false, termination_status=result.termination_status)
end

function m10_read_base_cache(path::AbstractString, source::AbstractString, case::Case)
    document = JSON.parsefile(path)
    get(document, "schema_version", nothing) == 1 ||
        throw(ArgumentError("unsupported M10 base-state cache schema"))
    get(document, "kind", nothing) == "DroopOPF.M10BaseState" ||
        throw(ArgumentError("unexpected M10 base-state cache kind"))
    get(document, "source_sha256", nothing) == bytes2hex(sha256(read(source))) ||
        throw(ArgumentError("M10 base-state cache source hash does not match"))
    get(document, "case_id", nothing) == case.id ||
        throw(ArgumentError("M10 base-state cache case ID does not match"))
    values = document["state"]
    state = ACState(Float64.(values["vm"]), Float64.(values["va"]),
        Float64.(values["pg"]), Float64.(values["qg"]))
    validation = validate_equilibrium(case, state;
        smooth_epsilon=document["smooth_epsilon"],
        smooth_reactive_relative_epsilon=document["smooth_reactive_relative_epsilon"],
        smooth_reactive_epsilon=document["smooth_reactive_epsilon"])
    validation.valid || error("cached M10 base state no longer independently validates")
    status = Symbol(document["termination_status"])
    status in (:LOCALLY_SOLVED, :ALMOST_LOCALLY_SOLVED, :OPTIMAL, :ALMOST_OPTIMAL) ||
        error("cached M10 base state lacks an accepted solver status")
    return (; state, report=validation, cached=true, termination_status=status)
end

"""
    m10_contingency_baseline(name, output; batch_size=1, batch_number=1,
        base_cache=nothing)

Create a deterministic N-1 catalog and evaluate one numbered batch of its
eligible contingencies against one independently validated fixed base OPF
state.  This is a security *assessment* baseline, not a security-constrained
redispatch optimization.  Run every batch before drawing a conclusion about a
case; islanding outages remain recorded as unsupported exclusions.
"""
function m10_contingency_baseline(name::AbstractString, output::AbstractString;
    batch_size::Integer=1, batch_number::Integer=1,
    base_cache::Union{Nothing,AbstractString}=nothing)
    batch_size > 0 || throw(ArgumentError("batch_size must be positive"))
    batch_number > 0 || throw(ArgumentError("batch_number must be positive"))
    mkpath(output)
    source = m10_source(name)
    case = load_matpower_case(source; base_frequency=60.0)
    cache_path = isnothing(base_cache) ?
        joinpath(dirname(output), "ieee$(name)-base-state.json") : abspath(base_cache)
    catalog = contingency_catalog(case)
    eligible = eligible_contingencies(catalog)
    first_index = (batch_number - 1) * batch_size + 1
    first_index <= length(eligible) || throw(ArgumentError("batch_number exceeds eligible catalog"))
    last_index = min(first_index + batch_size - 1, length(eligible))
    batch = eligible[first_index:last_index]

    write_contingency_catalog(joinpath(output, "catalog.json"), catalog)
    write(joinpath(output, "catalog.md"), markdown_report(catalog) * "\n")

    base = isfile(cache_path) ? m10_read_base_cache(cache_path, source, case) :
        m10_write_base_cache(cache_path, source, case, solve_opf(case))
    write(joinpath(output, "baseline.md"), "# M10 fixed-base assessment\n\n" *
        "- Source SHA-256: `$(bytes2hex(sha256(read(source))))`\n" *
        "- Eligible catalog entries: $(length(eligible))\n" *
        "- Structurally excluded entries: $(length(excluded_contingencies(catalog)))\n" *
        "- Batch: $(first_index)-$(last_index) of $(length(eligible))\n" *
        "- Base-state cache: `$(abspath(cache_path))` ($(base.cached ? "reused and revalidated" : "created and validated"))\n" *
        "- Base solver status: `$(base.termination_status)`\n" *
        "- Base independently valid: `$(base.report.valid)`\n\n" *
        "This evaluates each listed outage while holding the validated base state fixed. " *
        "It does not claim a SCOPF redispatch solution or safety for omitted batches.\n")
    base.report.valid || error("base OPF did not independently validate")

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
