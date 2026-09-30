include(joinpath(@__DIR__, "m10_contingency_baseline.jl"))

function m10_atomic_json(path::AbstractString, value)
    temporary = path * ".tmp"
    open(temporary, "w") do io
        JSON.print(io, value, 4)
        println(io)
    end
    mv(temporary, path; force=true)
    return path
end

function m10_completed_outcome(path::AbstractString)
    isfile(path) || return nothing
    outcome = try
        JSON.parsefile(path)
    catch
        return nothing
    end
    get(outcome, "completed", false) === true || return nothing
    return outcome
end

function m10_campaign_summary(output::AbstractString, name::AbstractString,
    first_index::Int, last_index::Int, eligible_count::Int, outcomes)
    completed = count(row -> get(row, "completed", false) === true, outcomes)
    accepted = count(row -> get(row, "classification", "") == "accepted", outcomes)
    physical_only = count(row -> get(row, "classification", "") == "physical_only", outcomes)
    invalid = count(row -> get(row, "classification", "") == "invalid", outcomes)
    errors = count(row -> get(row, "classification", "") == "error", outcomes)
    requested_complete = completed == last_index - first_index + 1
    catalog_complete = requested_complete && first_index == 1 && last_index == eligible_count
    summary = Dict(
        "schema_version" => 1,
        "kind" => "DroopOPF.M10ContingencyCampaign",
        "case" => name,
        "eligible_catalog_entries" => eligible_count,
        "requested_first_index" => first_index,
        "requested_last_index" => last_index,
        "completed" => completed,
        "accepted" => accepted,
        "physical_only" => physical_only,
        "invalid" => invalid,
        "errors" => errors,
        "requested_range_complete" => requested_complete,
        "full_catalog_complete" => catalog_complete,
        "outcomes" => outcomes,
    )
    m10_atomic_json(joinpath(output, "campaign.json"), summary)

    lines = ["# M10 contingency campaign", "",
        "- Case: IEEE-$name",
        "- Eligible catalog entries: $eligible_count",
        "- Requested range: $first_index-$last_index",
        "- Completed outcomes: $completed/$(last_index - first_index + 1)",
        "- Accepted: $accepted; physical-only: $physical_only; invalid: $invalid; errors: $errors",
        "- Requested range complete: `$requested_complete`",
        "- Full eligible catalog complete: `$catalog_complete`", "",
        "Invalid, limited, and error outcomes are unresolved evidence, never safety claims. " *
        "Ranking is based only on completed exact evaluations; no pre-solve severity filter is applied.", "",
        "| Index | Contingency | Classification | Solver status | Valid | Seconds |",
        "|---:|---|---|---|---|---:|"]
    for row in outcomes
        index = row["index"]
        contingency_id = row["contingency_id"]
        classification = get(row, "classification", "error")
        termination_status = get(row, "termination_status", "ERROR")
        independently_valid = get(row, "independently_valid", false)
        evaluation_seconds = get(row, "evaluation_seconds", "—")
        push!(lines, "| $index | $contingency_id | $classification | " *
            "$termination_status | $independently_valid | $evaluation_seconds |")
    end
    write(joinpath(output, "campaign.md"), join(lines, "\n") * "\n")
    return summary
end

"""
    m10_contingency_campaign(name, output; first_index=1, last_index=nothing)

Evaluate a contiguous range of eligible N-1 outages in one Julia process. The
case, validated base state, and compiled methods are reused. Each completed
outage is persisted before the next begins, and reruns skip only outcomes whose
completion marker can be parsed and explicitly says `completed=true`.
"""
function m10_contingency_campaign(name::AbstractString, output::AbstractString;
    first_index::Integer=1, last_index::Union{Nothing,Integer}=nothing,
    base_cache::Union{Nothing,AbstractString}=nothing,
    base_max_cpu_time::Real=120.0, scenario_max_cpu_time::Real=120.0,
    max_iter::Integer=1_000)
    first_index > 0 || throw(ArgumentError("first_index must be positive"))
    isfinite(base_max_cpu_time) && base_max_cpu_time > 0 ||
        throw(ArgumentError("base_max_cpu_time must be positive and finite"))
    isfinite(scenario_max_cpu_time) && scenario_max_cpu_time > 0 ||
        throw(ArgumentError("scenario_max_cpu_time must be positive and finite"))
    max_iter > 0 || throw(ArgumentError("max_iter must be positive"))

    output = abspath(output)
    mkpath(joinpath(output, "cases"))
    source = m10_source(name)
    case = load_matpower_case(source; base_frequency=60.0)
    catalog = contingency_catalog(case)
    eligible = eligible_contingencies(catalog)
    final_index = isnothing(last_index) ? length(eligible) : Int(last_index)
    first = Int(first_index)
    first <= final_index <= length(eligible) ||
        throw(ArgumentError("requested range must lie within 1:$(length(eligible))"))
    cache_path = isnothing(base_cache) ?
        joinpath(dirname(output), "ieee$(name)-base-state.json") : abspath(base_cache)

    write_contingency_catalog(joinpath(output, "catalog.json"), catalog)
    write(joinpath(output, "catalog.md"), markdown_report(catalog) * "\n")
    write(joinpath(output, "run-policy.md"), "# M10 campaign policy\n\n" *
        "- One Julia process reuses compilation across all requested outages.\n" *
        "- Base Ipopt CPU/wall-time limit: $(base_max_cpu_time) seconds.\n" *
        "- Per-outage Ipopt CPU/wall-time limit: $(scenario_max_cpu_time) seconds.\n" *
        "- Per-outage Ipopt iteration limit: $(max_iter).\n" *
        "- Every eligible outage in the requested range is evaluated; there is no severity pre-filter.\n\n" *
        "A time or iteration limit, invalid result, or exception is unresolved evidence and never a safety claim.\n")

    base = if isfile(cache_path)
        m10_read_base_cache(cache_path, source, case)
    else
        base_result = solve_opf(case; optimizer_attributes=Dict(
            "max_cpu_time" => Float64(base_max_cpu_time),
            "max_wall_time" => Float64(base_max_cpu_time), "max_iter" => Int(max_iter)))
        isnothing(base_result.state) && error("base OPF returned no state")
        equilibrium_report(case, base_result).valid ||
            error("base OPF failed independent validation")
        m10_write_base_cache(cache_path, source, case, base_result)
    end
    base.report.valid || error("base OPF did not independently validate")
    write(joinpath(output, "baseline.md"), "# M10 fixed-base campaign\n\n" *
        "- Source SHA-256: `$(bytes2hex(sha256(read(source))))`\n" *
        "- Base-state cache: `$(abspath(cache_path))` ($(base.cached ? "reused and revalidated" : "created and validated"))\n" *
        "- Base solver status: `$(base.termination_status)`\n" *
        "- Base independently valid: `$(base.report.valid)`\n\n" *
        "This is a fixed-base security assessment, not a security-constrained redispatch optimization.\n")

    participation = Dict(g.id => 1.0 for g in case.generators if g.available)
    outcomes = Dict{String,Any}[]
    ranks = ContingencyRank[]
    for index in first:final_index
        contingency = eligible[index]
        directory = joinpath(output, "cases", lpad(string(index), 4, '0') * "-" * string(contingency.id))
        mkpath(directory)
        outcome_path = joinpath(directory, "outcome.json")
        previous = m10_completed_outcome(outcome_path)
        if !isnothing(previous)
            push!(outcomes, previous)
            ranking_path = joinpath(directory, "ranking.json")
            if isfile(ranking_path)
                data = JSON.parsefile(ranking_path)["data"]
                for row in data
                    push!(ranks, ContingencyRank(Symbol(row["contingency_id"]),
                        Symbol(row["device_kind"]), row["device_id"],
                        Symbol(row["classification"]),
                        isnothing(row["severity"]) ? Inf : row["severity"],
                        isnothing(row["minimum_operating_margin"]) ? -Inf : row["minimum_operating_margin"],
                        Symbol(row["termination_status"])))
                end
            end
            println("[$index/$final_index] $(contingency.id): resumed completed outcome")
            flush(stdout)
            continue
        end

        println("[$index/$final_index] $(contingency.id): evaluating")
        flush(stdout)
        started = time_ns()
        build_seconds = Ref(0.0)
        outcome = try
            study = Study(case; contingencies=[contingency], participation=participation)
            result = evaluate_contingencies(study, base.state; optimizer_attributes=Dict(
                "max_cpu_time" => Float64(scenario_max_cpu_time),
                "max_wall_time" => Float64(scenario_max_cpu_time), "max_iter" => Int(max_iter)),
                _model_hook=model -> (build_seconds[] = (time_ns() - started) / 1e9))
            evaluation_seconds = (time_ns() - started) / 1e9
            report = equilibrium_report(study, result)
            case_ranks = rank_contingencies(catalog, report)
            append!(ranks, case_ranks)
            classification = isempty(case_ranks) ? :invalid : only(case_ranks).classification

            write_study(joinpath(directory, "study.json"), study)
            write_scopf_result(joinpath(directory, "result.json"), result)
            write_scopf_report(joinpath(directory, "report.json"), report)
            write_contingency_ranking(joinpath(directory, "ranking.json"), case_ranks)
            write(joinpath(directory, "report.md"), markdown_report(report) * "\n")
            write(joinpath(directory, "ranking.md"), markdown_report(case_ranks) * "\n")
            timing = Dict("build_including_compilation_seconds" => build_seconds[],
                "optimize_and_extract_seconds" => evaluation_seconds - build_seconds[],
                "evaluation_seconds" => evaluation_seconds,
                "termination_status" => string(result.termination_status),
                "independently_valid" => report.valid)
            m10_atomic_json(joinpath(directory, "timing.json"), timing)
            Dict{String,Any}("completed" => true, "index" => index,
                "contingency_id" => string(contingency.id),
                "classification" => string(classification),
                "termination_status" => string(result.termination_status),
                "independently_valid" => report.valid,
                "evaluation_seconds" => evaluation_seconds,
                "directory" => relpath(directory, output))
        catch error
            elapsed = (time_ns() - started) / 1e9
            failure = Dict{String,Any}("completed" => false, "index" => index,
                "contingency_id" => string(contingency.id), "classification" => "error",
                "termination_status" => "ERROR", "independently_valid" => false,
                "evaluation_seconds" => elapsed, "directory" => relpath(directory, output),
                "error" => sprint(showerror, error, catch_backtrace()))
            m10_atomic_json(joinpath(directory, "failure.json"), failure)
            failure
        end
        m10_atomic_json(outcome_path, outcome)
        push!(outcomes, outcome)
        sort!(ranks; by=x -> (-x.severity, string(x.contingency_id)))
        write_contingency_ranking(joinpath(output, "ranking.json"), ranks)
        write(joinpath(output, "ranking.md"), markdown_report(ranks) * "\n")
        m10_campaign_summary(output, name, first, final_index, length(eligible), outcomes)
        classification = outcome["classification"]
        elapsed = round(outcome["evaluation_seconds"]; digits=3)
        println("[$index/$final_index] $(contingency.id): $classification in $elapsed s")
        flush(stdout)
    end

    summary = m10_campaign_summary(output, name, first, final_index, length(eligible), outcomes)
    completed = summary["completed"]
    requested = final_index - first + 1
    println("M10 campaign completed $completed/$requested requested outcomes in $output")
    return (; catalog, outcomes, ranks, summary)
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    name = get(ARGS, 1, "118")
    output = abspath(get(ARGS, 2, joinpath(pwd(), "m10_contingency_campaign")))
    first_index = parse(Int, get(ARGS, 3, "1"))
    last_argument = get(ARGS, 4, "all")
    last_index = last_argument == "all" ? nothing : parse(Int, last_argument)
    scenario_seconds = parse(Float64, get(ARGS, 5, "120"))
    max_iter = parse(Int, get(ARGS, 6, "1000"))
    m10_contingency_campaign(name, output; first_index, last_index,
        scenario_max_cpu_time=scenario_seconds, max_iter)
end
