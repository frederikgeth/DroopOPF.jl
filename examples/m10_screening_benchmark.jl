include(joinpath(@__DIR__, "m10_contingency_baseline.jl"))
using Statistics

function m10_screening_rows(output::AbstractString)
    campaign = JSON.parsefile(joinpath(output, "campaign.json"))
    campaign["full_catalog_complete"] === true ||
        error("screening benchmark requires a complete exact-enumeration baseline")
    name = campaign["case"]
    source = m10_source(name)
    case = load_matpower_case(source; base_frequency=60.0)
    cache = joinpath(dirname(output), "ieee$(name)-base-state.json")
    base = m10_read_base_cache(cache, source, case)
    catalog = contingency_catalog(case)
    entries = Dict(string(entry.contingency.id) => entry for entry in catalog.entries
        if entry.disposition == :eligible)
    outcomes = Dict(row["contingency_id"] => row for row in campaign["outcomes"]
        if get(row, "completed", false) === true)
    Set(keys(entries)) == Set(keys(outcomes)) ||
        error("campaign outcomes do not exactly cover the eligible catalog")

    flows = branch_flows(case.network, base.state)
    branch_index = Dict(branch.id => i for (i, branch) in enumerate(case.network.branches))
    generator_index = Dict(generator.id => i for (i, generator) in enumerate(case.generators))
    total_generation = sum(abs, base.state.pg)
    rows = Dict{String,Any}[]
    for (id, entry) in entries
        raw_score = if entry.device_kind == :branch
            i = branch_index[entry.device_id]
            limit = case.network.branches[i].thermal_limit
            isfinite(limit) && limit > 0 ?
                max(abs(flows.from[i]), abs(flows.to[i])) / limit : 0.0
        else
            i = generator_index[entry.device_id]
            total_generation > 0 ? abs(base.state.pg[i]) / total_generation : 0.0
        end
        outcome = outcomes[id]
        push!(rows, Dict{String,Any}(
            "contingency_id" => id,
            "device_kind" => string(entry.device_kind),
            "device_id" => entry.device_id,
            "raw_score" => raw_score,
            "classification" => outcome["classification"],
            "unresolved" => outcome["classification"] != "accepted",
        ))
    end

    # Raw scores have different units by device family. Convert each family to
    # an empirical percentile before producing one combined priority queue.
    for device in ("branch", "generator")
        group = filter(row -> row["device_kind"] == device, rows)
        ordered = sort(group; by=row -> (row["raw_score"], row["contingency_id"]))
        denominator = max(length(ordered) - 1, 1)
        for (rank, row) in enumerate(ordered)
            row["screening_score"] = (rank - 1) / denominator
        end
    end
    return sort(rows; by=row -> (-row["screening_score"], -row["raw_score"],
        row["contingency_id"]))
end

function m10_screening_benchmark(output::AbstractString)
    output = abspath(output)
    rows = m10_screening_rows(output)
    unresolved_count = count(row -> row["unresolved"], rows)
    accepted_count = length(rows) - unresolved_count
    curve = Dict{String,Any}[]
    for fraction in (0.25, 0.50, 0.75, 0.90, 0.95, 1.00)
        evaluated = ceil(Int, fraction * length(rows))
        selected = rows[1:evaluated]
        captured = count(row -> row["unresolved"], selected)
        push!(curve, Dict{String,Any}(
            "budget_fraction" => fraction,
            "evaluated" => evaluated,
            "unresolved_captured" => captured,
            "unresolved_omitted" => unresolved_count - captured,
            "unresolved_recall" => unresolved_count == 0 ? 1.0 : captured / unresolved_count,
            "accepted_omitted" => count(row -> !row["unresolved"], rows[evaluated+1:end]),
        ))
    end
    last_unresolved_rank = maximum(i for (i, row) in enumerate(rows) if row["unresolved"])
    family = Dict{String,Any}()
    for device in ("branch", "generator")
        device_rows = filter(row -> row["device_kind"] == device, rows)
        unresolved_ranks = [i for (i, row) in enumerate(device_rows) if row["unresolved"]]
        family[device] = Dict(
            "eligible" => length(device_rows),
            "unresolved" => length(unresolved_ranks),
            "evaluations_for_full_unresolved_recall" =>
                isempty(unresolved_ranks) ? 0 : maximum(unresolved_ranks),
        )
    end
    benchmark = Dict{String,Any}(
        "schema_version" => 1,
        "kind" => "DroopOPF.M10ScreeningBenchmark",
        "method" => "within-device percentile of base AC branch loading or generator active-power share",
        "eligible_count" => length(rows),
        "unresolved_count" => unresolved_count,
        "accepted_count" => accepted_count,
        "evaluations_for_full_unresolved_recall" => last_unresolved_rank,
        "maximum_omission_at_full_unresolved_recall" => length(rows) - last_unresolved_rank,
        "family" => family,
        "recall_curve" => curve,
        "ranking" => rows,
    )
    open(joinpath(output, "screening-benchmark.json"), "w") do io
        JSON.print(io, benchmark, 4)
        println(io)
    end

    lines = ["# M10 pre-solve screening benchmark", "",
        "- Method: $(benchmark["method"]).",
        "- Exact baseline: $(length(rows)) eligible outages; $unresolved_count unresolved; $accepted_count accepted.",
        "- Evaluations required for 100% retrospective unresolved recall: $last_unresolved_rank/$(length(rows)).",
        "- Maximum retrospective omissions at that recall: $(length(rows) - last_unresolved_rank).", "",
        "This heuristic uses only the validated base state and device data. It did not select the exact-enumeration " *
        "baseline. Results are retrospective and do not authorize filtering in a new case.", "",
        "| Evaluation budget | Evaluated | Unresolved captured | Unresolved omitted | Recall | Accepted omitted |",
        "|---:|---:|---:|---:|---:|---:|"]
    for point in curve
        push!(lines, "| $(point["budget_fraction"]) | $(point["evaluated"]) | " *
            "$(point["unresolved_captured"]) | $(point["unresolved_omitted"]) | " *
            "$(point["unresolved_recall"]) | $(point["accepted_omitted"]) |")
    end
    push!(lines, "", "## Highest-priority outages", "",
        "| Rank | Contingency | Device | Raw score | Percentile score | Exact class |",
        "|---:|---|---|---:|---:|---|")
    for (rank, row) in enumerate(first(rows, min(25, length(rows))))
        push!(lines, "| $rank | $(row["contingency_id"]) | $(row["device_kind"]) | " *
            "$(row["raw_score"]) | $(row["screening_score"]) | $(row["classification"]) |")
    end
    push!(lines, "", "## Interpretation", "",
        "A useful filter must set its threshold on separate training evidence and then demonstrate high recall on held-out " *
        "exact evaluations. Any unresolved omission is a false negative. Structurally excluded islanding outages remain " *
        "outside this heuristic and require an island-aware formulation; they cannot be labelled safe.", "")
    write(joinpath(output, "screening-benchmark.md"), join(lines, "\n"))
    return benchmark
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    output = abspath(get(ARGS, 1, joinpath(pwd(), "m10_contingency_campaign")))
    m10_screening_benchmark(output)
end
