using JSON
using SHA

const S1_SOLVED_STATUSES = Set(("LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED"))

function s1_sha256(path)
    open(path) do io
        bytes2hex(sha256(io))
    end
end

function s1_frozen_group(row)
    "public$(row["buses"])_load$(row["tags"]["load_factor"])"
end

function s1_frozen_classification(row, witnesses)
    get(row, "valid", false) && return "validated_feasible"
    !isempty(witnesses) && return "solver_path_failure_with_witness"
    attempt = last(row["attempts"])
    get(attempt, "status", "") in S1_SOLVED_STATUSES && return "strict_audit_failure"
    "unknown_feasibility"
end

function s1_artifact_path(folder, name, suffix)
    path = joinpath(folder, name * suffix)
    isfile(path) ? relpath(path, pwd()) : nothing
end

function s1_seed_lineage(folder, attempts)
    [Dict(
        "attempt" => attempt["name"],
        "start_snapshot" => s1_artifact_path(folder, attempt["name"], "-start.json"),
        "recovery_seed" => s1_artifact_path(
            folder,
            replace(attempt["name"], r"-attempt[0-9]+$" => ""),
            "-recovery-seed.json",
        ),
        "context" => get(get(attempt, "tags", Dict()), "context", nothing),
        "dual_reset" => get(get(attempt, "tags", Dict()), "dual_reset", nothing),
        "builder_start_overridden" => get(
            get(attempt, "tags", Dict()), "builder_start_overridden", nothing
        ),
    ) for attempt in attempts]
end

function s1_frozen_cell(row, folder, feasibility)
    attempts = row["attempts"]
    final_attempt = last(attempts)
    physical = get(final_attempt, "physical", Dict())
    group = s1_frozen_group(row)
    group_audit = get(feasibility["groups"], group, Dict())
    witnesses = get(group_audit, "witnesses", String[])
    design_path = s1_artifact_path(folder, final_attempt["name"], "-design.json")
    diagnostics_path = s1_artifact_path(folder, final_attempt["name"], "-diagnostics.json")
    Dict(
        "cell" => row["name"],
        "case" => group,
        "buses" => row["buses"],
        "load_factor" => row["tags"]["load_factor"],
        "solver" => row["solver"],
        "declared_start" => row["tags"]["start"],
        "strict_accepted" => get(row, "valid", false),
        "classification" => s1_frozen_classification(row, witnesses),
        "known_witnesses" => witnesses,
        "attempt_count" => length(attempts),
        "events" => get(row, "events", String[]),
        "final_status" => get(final_attempt, "status", "UNKNOWN"),
        "solver_valid" => get(final_attempt, "solver_valid", false),
        "policy_valid" => get(final_attempt, "policy_valid", false),
        "physical_valid" => get(final_attempt, "physical_valid", false),
        "strict_residuals" => Dict(
            "power_balance_max" => get(physical, "power_balance_max", nothing),
            "exact_droop_max" => get(physical, "droop_residual_max", nothing),
            "smooth_exact_droop_gap" => get(physical, "smooth_exact_droop_gap", nothing),
            "violations" => get(physical, "violations", String[]),
        ),
        "last_retained_iterate" => design_path,
        "last_diagnostics" => diagnostics_path,
        "seed_lineage" => s1_seed_lineage(folder, attempts),
    )
end

function s1_assert_frozen_contract(cells)
    length(cells) == 24 || error("frozen contract requires 24 cells, found $(length(cells))")
    Set(cell["solver"] for cell in cells) == Set(("ipopt", "madnlp")) ||
        error("frozen contract solver set changed")
    Set(cell["buses"] for cell in cells) == Set((118, 300)) ||
        error("frozen contract network set changed")
    Set(cell["load_factor"] for cell in cells) == Set((1.0, 1.05)) ||
        error("frozen contract load set changed")
    Set(cell["declared_start"] for cell in cells) == Set(("anchor", "flat_low", "flat_high")) ||
        error("frozen contract start set changed")
    all(cell["last_retained_iterate"] !== nothing for cell in cells) ||
        error("one or more frozen cells has no retained final iterate")
    nothing
end

function s1_frozen_contract_ledger(ipopt_summary, madnlp_summary, feasibility_summary, out;
    enforce_contract=true)
    sources = (ipopt_summary, madnlp_summary)
    feasibility = JSON.parsefile(feasibility_summary)
    cells = Dict{String,Any}[]
    for summary in sources
        folder = dirname(summary)
        append!(cells, [s1_frozen_cell(row, folder, feasibility) for row in JSON.parsefile(summary)])
    end
    sort!(cells; by=cell -> (cell["buses"], cell["load_factor"], cell["solver"], cell["declared_start"]))
    enforce_contract && s1_assert_frozen_contract(cells)

    classifications = Dict{String,Int}()
    for cell in cells
        key = cell["classification"]
        classifications[key] = get(classifications, key, 0) + 1
    end
    contract = Dict(
        "schema" => "s1-frozen-contract-ledger-v1",
        "scope" => "unchanged 24-cell smooth S1 frozen acceptance matrix",
        "acceptance" => Dict(
            "solver_and_policy_must_accept" => true,
            "independent_physical_validation_must_pass" => true,
            "exact_droop_tolerance_pu" => 1e-5,
            "smooth_epsilon" => 1e-6,
            "relaxed_or_diagnostic_results_are_not_accepted" => true,
        ),
        "budget" => Dict(
            "policy" => "one-reset-v1",
            "attempt_iterations" => 1000,
            "attempt_seconds" => 60.0,
            "total_iterations" => 2000,
            "total_seconds" => 120.0,
        ),
        "dimensions" => Dict(
            "solvers" => ["ipopt", "madnlp"],
            "networks" => [118, 300],
            "load_factors" => [1.0, 1.05],
            "starts" => ["anchor", "flat_low", "flat_high"],
        ),
        "source_files" => [Dict("path" => relpath(path, pwd()), "sha256" => s1_sha256(path))
                           for path in (sources..., feasibility_summary)],
        "cell_count" => length(cells),
        "strict_accept_count" => count(cell -> cell["strict_accepted"], cells),
        "classifications" => classifications,
        "cells" => cells,
    )

    mkpath(out)
    write(joinpath(out, "contract-ledger.json"), JSON.json(contract; pretty=true) * "\n")
    contract
end

if abspath(PROGRAM_FILE) == (@__FILE__)
    length(ARGS) == 4 || error(
        "usage: julia --project=. examples/s1_frozen_contract_ledger.jl " *
        "IPOPT_SUMMARY MADNLP_SUMMARY FEASIBILITY_SUMMARY OUTPUT_DIR"
    )
    s1_frozen_contract_ledger(abspath.(ARGS)...)
end
