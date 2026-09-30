using JSON
using Statistics

finite_min(values...) = minimum(Float64[x for x in values if x isa Number && isfinite(x)])

function normalized_violation(report, scenario, id)
    tolerance = report["tolerances"]
    checks = [
        scenario["power_balance_max"] / tolerance["power_tolerance"],
        scenario["unavailable_generator_max"] / tolerance["unavailable_tolerance"],
        get(report["coupling_violation"], id, 0.0) / tolerance["coupling_tolerance"],
        get(report["equipment_coupling_violation"], id, 0.0) / tolerance["coupling_tolerance"],
    ]
    for key in ("voltage_min_margin", "voltage_max_margin",
        "generator_p_min_margin", "generator_p_max_margin",
        "generator_q_min_margin", "generator_q_max_margin",
        "branch_thermal_min_margin")
        push!(checks, max(0.0, -scenario[key]) / tolerance["limit_tolerance"])
    end
    return maximum(checks)
end

function append_ranking!(lines, title, rows, key, label, limit)
    push!(lines, "## $title", "",
        "| Rank | Contingency | Device | $label |",
        "|---:|---|---|---:|")
    for (rank, row) in enumerate(first(rows, min(limit, length(rows))))
        id, device, value = row["contingency_id"], row["device_kind"], row[key]
        push!(lines, "| $rank | $id | $device | $value |")
    end
    isempty(rows) && push!(lines, "| — | — | — | — |")
    push!(lines, "")
end

"""Build post-enumeration coverage, failure, timing, and metric-specific rankings."""
function m10_campaign_report(output::AbstractString; top::Integer=15)
    top > 0 || throw(ArgumentError("top must be positive"))
    output = abspath(output)
    campaign = JSON.parsefile(joinpath(output, "campaign.json"))
    catalog = JSON.parsefile(joinpath(output, "catalog.json"))["data"]
    rows = Dict{String,Any}[]
    violations = Dict{String,Int}()
    statuses = Dict{String,Int}()
    classifications = Dict{String,Int}()
    device_classifications = Dict{String,Int}()

    for outcome in campaign["outcomes"]
        get(outcome, "completed", false) === true || continue
        id = outcome["contingency_id"]
        report = JSON.parsefile(joinpath(output, outcome["directory"], "report.json"))["data"]
        scenario = report["scenarios"][id]
        scenario_violations = report["violations"][id]
        for violation in scenario_violations
            violations[violation] = get(violations, violation, 0) + 1
        end
        status, classification = outcome["termination_status"], outcome["classification"]
        device = first(split(id, '_'))
        statuses[status] = get(statuses, status, 0) + 1
        classifications[classification] = get(classifications, classification, 0) + 1
        group = "$device/$classification"
        device_classifications[group] = get(device_classifications, group, 0) + 1
        push!(rows, Dict{String,Any}(
            "index" => outcome["index"],
            "contingency_id" => id,
            "device_kind" => device,
            "classification" => classification,
            "termination_status" => status,
            "evaluation_seconds" => outcome["evaluation_seconds"],
            "violations" => scenario_violations,
            "normalized_violation" => normalized_violation(report, scenario, id),
            "power_balance_residual" => scenario["power_balance_max"],
            "voltage_headroom" => finite_min(
                scenario["voltage_min_margin"], scenario["voltage_max_margin"]),
            "thermal_headroom" => scenario["branch_thermal_min_margin"],
            "active_power_headroom" => finite_min(
                scenario["generator_p_min_margin"], scenario["generator_p_max_margin"]),
            "reactive_power_headroom" => finite_min(
                scenario["generator_q_min_margin"], scenario["generator_q_max_margin"]),
        ))
    end

    unresolved = sort(filter(row -> row["classification"] != "accepted", rows);
        by=row -> (-row["normalized_violation"], row["contingency_id"]))
    accepted = filter(row -> row["classification"] == "accepted", rows)
    by_voltage = sort(copy(accepted); by=row -> (row["voltage_headroom"], row["contingency_id"]))
    by_thermal = sort(copy(accepted); by=row -> (row["thermal_headroom"], row["contingency_id"]))
    by_reactive = sort(copy(accepted); by=row -> (row["reactive_power_headroom"], row["contingency_id"]))
    by_active = sort(copy(accepted); by=row -> (row["active_power_headroom"], row["contingency_id"]))
    timings = sort(Float64[row["evaluation_seconds"] for row in rows])
    percentile(q) = timings[round(Int, 1 + q * (length(timings) - 1))]
    exclusions = filter(entry -> entry["disposition"] == "excluded", catalog["entries"])
    timing = Dict("total" => sum(timings), "median" => median(timings),
        "p90" => percentile(0.90), "p95" => percentile(0.95),
        "p99" => percentile(0.99), "maximum" => maximum(timings))
    analysis = Dict{String,Any}(
        "schema_version" => 1,
        "kind" => "DroopOPF.M10CampaignAnalysis",
        "full_catalog_complete" => campaign["full_catalog_complete"],
        "candidate_count" => length(catalog["entries"]),
        "eligible_count" => campaign["eligible_catalog_entries"],
        "excluded_count" => length(exclusions),
        "completed_count" => length(rows),
        "classification_counts" => classifications,
        "device_classification_counts" => device_classifications,
        "status_counts" => statuses,
        "violation_counts" => violations,
        "timing_seconds" => timing,
        "excluded" => exclusions,
        "unresolved_by_normalized_violation" => unresolved,
        "accepted_by_voltage_headroom" => by_voltage,
        "accepted_by_thermal_headroom" => by_thermal,
        "accepted_by_reactive_power_headroom" => by_reactive,
        "accepted_by_active_power_headroom" => by_active,
    )
    open(joinpath(output, "analysis.json"), "w") do io
        JSON.print(io, analysis, 4)
        println(io)
    end

    full = campaign["full_catalog_complete"]
    candidate_count, eligible_count = analysis["candidate_count"], analysis["eligible_count"]
    excluded_count = analysis["excluded_count"]
    lines = ["# M10 IEEE contingency analysis", "",
        "- Full eligible catalog complete: $full.",
        "- Candidates: $candidate_count; eligible and evaluated: $eligible_count; structurally excluded: $excluded_count.",
        "- Classifications: $classifications.",
        "- Solver statuses: $statuses.",
        "- Validation failures: $violations.",
        "- Evaluation time: $(round(timing["total"]; digits=3)) s total; " *
        "$(round(timing["median"]; digits=3)) s median; " *
        "$(round(timing["p95"]; digits=3)) s p95; " *
        "$(round(timing["maximum"]; digits=3)) s maximum.", "",
        "All eligible outages were evaluated before ranking. Excluded islanding outages are unsupported, not safe. " *
        "Invalid and solver-limited outcomes are unresolved, not filtered failures.", "",
        "Normalized violation is the largest independent residual-to-tolerance ratio across AC balance, " *
        "availability, coupling, and operating-limit checks. It orders diagnostic attention; " *
        "it is not a physical stability index.", ""]
    append_ranking!(lines, "Unresolved outcomes", unresolved,
        "normalized_violation", "Normalized violation", top)
    append_ranking!(lines, "Accepted outcomes: lowest voltage headroom", by_voltage,
        "voltage_headroom", "Voltage headroom (p.u.)", top)
    append_ranking!(lines, "Accepted outcomes: lowest thermal headroom", by_thermal,
        "thermal_headroom", "Thermal headroom (p.u.)", top)
    append_ranking!(lines, "Accepted outcomes: lowest reactive-power headroom", by_reactive,
        "reactive_power_headroom", "Reactive headroom (p.u.)", top)
    append_ranking!(lines, "Accepted outcomes: lowest active-power headroom", by_active,
        "active_power_headroom", "Active headroom (p.u.)", top)
    push!(lines, "## Filtering baseline", "",
        "A future screening method must be compared against all $(length(rows)) completed exact evaluations. " *
        "At minimum it must report recall for all $(length(unresolved)) unresolved outcomes and separately account " *
        "for the $(length(exclusions)) unsupported islanding candidates. Accepted outcomes are not certified " *
        "dynamically safe; they only pass this steady-state fixed-base formulation and its declared tolerances.", "")
    write(joinpath(output, "analysis.md"), join(lines, "\n"))
    return analysis
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    output = abspath(get(ARGS, 1, joinpath(pwd(), "m10_contingency_campaign")))
    top = parse(Int, get(ARGS, 2, "15"))
    m10_campaign_report(output; top)
end
