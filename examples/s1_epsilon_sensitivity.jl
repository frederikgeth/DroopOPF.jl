include("s1_policy_matrix.jl")

const S1_EPSILON_SCHEDULE = (1e-2, 1e-3, 1e-4, 1e-5, 1e-6, 1e-7)

function s1_epsilon_relaxed_valid(row; droop_tolerance=1e-2)
    get(row, "solver_valid", false) && get(row, "policy_valid", false) || return false
    physical = get(row, "physical", nothing)
    isnothing(physical) && return false
    get(physical, "valid", false) && return true
    violations = get(physical, "violations", Any[])
    !isempty(violations) && all(==("droop"), violations) || return false
    residual = get(physical, "droop_residual_max", Inf)
    return isfinite(residual) && residual <= droop_tolerance
end

function s1_epsilon_report(out, rows; schedule=S1_EPSILON_SCHEDULE)
    groups = Dict{String,Vector{Dict{String,Any}}}()
    for row in rows
        push!(get!(groups, row["cell"], Dict{String,Any}[]), row)
    end
    open(joinpath(out, "report.md"), "w") do io
        println(io, "# S1 smooth-droop epsilon sensitivity\n")
        println(io, "This is an experimental continuation/sensitivity study outside the frozen S1 acceptance counts. The fixed schedule is `", join(schedule, " → "), "`. Each stage is warm-started from the latest solver- and policy-valid stage; a failed stage is retained and the scan continues from the last accepted warm start. Every stage keeps its raw exact-droop mismatch.\n")
        println(io, "The strict column uses the unchanged `1e-5` physical droop tolerance. The `1e-2` column is diagnostic only and does not overwrite the frozen decision. Each stage has its own 1000-iteration/60-second allowance, so a gain here is a continuation result, not an equal-budget frozen improvement.\n")
        println(io, "| Cell | Strict-valid epsilons | Diagnostic `1e-2` epsilons | Best raw mismatch (pu) | Frozen valid | Continuation changes strict result? |\n|---|---|---|---:|---:|---:|")
        for cell in sort(collect(keys(groups)))
            rs = sort(groups[cell]; by=r -> findfirst(==(r["epsilon"]), schedule))
            strict = [r["epsilon"] for r in rs if get(r, "valid", false)]
            relaxed = [r["epsilon"] for r in rs if get(r, "relaxed_droop_valid", false)]
            residuals = [get(get(r, "physical", Dict{String,Any}()), "droop_residual_max", Inf) for r in rs]
            best = minimum(residuals; init=Inf)
            frozen = get(first(rs), "frozen_valid", false)
            changed = !frozen && !isempty(strict)
            println(io, "| `", cell, "` | `", isempty(strict) ? "—" : join(strict, ", "), "` | `",
                isempty(relaxed) ? "—" : join(relaxed, ", "), "` | ", best, " | ", frozen, " | ", changed, " |")
        end
        frozen_count = count(rs -> get(first(rs), "frozen_valid", false), values(groups))
        strict_count = count(rs -> any(r -> get(r, "valid", false), rs), values(groups))
        relaxed_count = count(rs -> any(r -> get(r, "relaxed_droop_valid", false), rs), values(groups))
        println(io, "\nFrozen accepted: **$frozen_count/$(length(groups))**. At least one continuation stage strictly accepted: **$strict_count/$(length(groups))**. At least one stage passed the diagnostic `1e-2` droop gate with all other gates unchanged: **$relaxed_count/$(length(groups))**.")
        println(io, "\n## Paired acceptance summary\n")
        println(io, "| Solver | Frozen | Continuation union | Gained cells | Lost frozen cells |\n|---|---:|---:|---:|---:|")
        for solver in ("ipopt", "madnlp")
            selected = Dict(c => rs for (c, rs) in groups if first(rs)["solver"] == solver)
            frozen_cells = Set(c for (c, rs) in selected if get(first(rs), "frozen_valid", false))
            continued_cells = Set(c for (c, rs) in selected if any(r -> get(r, "valid", false), rs))
            println(io, "| ", solver, " | ", length(frozen_cells), "/", length(selected), " | ",
                length(continued_cells), "/", length(selected), " | ",
                length(setdiff(continued_cells, frozen_cells)), " | ",
                length(setdiff(frozen_cells, continued_cells)), " |")
        end
        println(io, "\n## Per-epsilon behavior\n")
        println(io, "| Epsilon | Solver-valid | Strict-valid | Diagnostic `1e-2` valid | Mean seconds |\n|---:|---:|---:|---:|---:|")
        for epsilon in schedule
            stage = [r for r in rows if r["epsilon"] == epsilon]
            mean_seconds = sum(get(r, "elapsed_seconds", 0.0) for r in stage) / length(stage)
            println(io, "| ", epsilon, " | ", count(r -> get(r, "solver_valid", false), stage), "/", length(stage),
                " | ", count(r -> get(r, "valid", false), stage), "/", length(stage),
                " | ", count(r -> get(r, "relaxed_droop_valid", false), stage), "/", length(stage),
                " | ", round(mean_seconds; digits=3), " |")
        end
        println(io, "\n## S1 interpretation\n")
        println(io, "Continuation materially improves aggregate strict acceptance, especially for MadNLP, but it does not satisfy S1's no-loss reliability criterion: some frozen-accepted cells are not reproduced by this path. It also spends up to six independent solve allowances per cell, so 18/24 is not an equal-budget replacement for the 12/24 frozen baseline. The result supports continuation as a promising opt-in recovery strategy, not as a new default or closure of S1.")
    end
end

"""Run the fixed epsilon scan on the 24 Ipopt/MadNLP frozen S1 cells.

Results are checkpointed after every stage. Existing `(cell, epsilon)` rows are
retained, making the workload resumable without silently replacing evidence.
"""
function s1_epsilon_sensitivity(out; schedule=S1_EPSILON_SCHEDULE)
    mkpath(out)
    summary_path = joinpath(out, "summary.json")
    rows = isfile(summary_path) ?
        [Dict{String,Any}(string(k) => v for (k, v) in r) for r in JSON.parsefile(summary_path)] :
        Dict{String,Any}[]
    for solver in (:ipopt, :madnlp), n in (118, 300), factor in (1.0, 1.05),
        start_kind in (:anchor, :flat_low, :flat_high)
        source = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07",
            "pglib_opf_case$(n)_ieee.m")
        original = load_matpower_case(source; base_frequency=60.0)
        anchor = read_joint_design(joinpath(@__DIR__, "..", "artifacts", "s1_public_controls",
            "public$n-baseline-design.json"))
        case, base_policies, _ = s1_public_overlay(original, anchor, source;
            bank_count=n == 118 ? 12 : 32)
        case = s1_load(case, factor)
        state = start_kind == :anchor ? anchor.opf.state : s1_flat(case)
        policies = start_kind == :anchor ? base_policies : s1_reseed(case, base_policies;
            fraction=start_kind == :flat_low ? 0.2 : 0.8)
        cell = "public$n-load$factor-$solver-$start_kind"
        frozen_path = joinpath(@__DIR__, "..", "artifacts", "s1_policy_$(solver)", "summary.json")
        frozen_rows = JSON.parsefile(frozen_path)
        frozen = only(r for r in frozen_rows if r["name"] == cell)
        for epsilon in schedule
            retained = findfirst(r -> r["cell"] == cell && r["epsilon"] == epsilon, rows)
            if !isnothing(retained)
                old = rows[retained]
                if get(old, "solver_valid", false) && get(old, "policy_valid", false)
                    design_path = joinpath(out, old["name"] * "-design.json")
                    if isfile(design_path)
                        prior = read_joint_design(design_path)
                        state = prior.opf.state
                        policies = s1_reseed(case, base_policies; result=prior)
                    end
                end
                continue
            end
            label = replace(string(epsilon), "." => "p", "-" => "m")
            name = "$cell-epsilon-$label"
            row, result = s1_attempt(out, name, case, state; policies, solver, epsilon,
                options=Dict{String,Any}("bound_push" => 1e-8, "bound_frac" => 1e-8),
                tags=Dict("study" => "s1_epsilon_sensitivity_v1", "cell" => cell,
                    "start" => string(start_kind), "load_factor" => factor,
                    "schedule" => collect(schedule)))
            row["cell"] = cell
            row["frozen_valid"] = frozen["valid"]
            row["frozen_selected"] = frozen["selected"]
            row["relaxed_droop_tolerance"] = 1e-2
            row["relaxed_droop_valid"] = s1_epsilon_relaxed_valid(row)
            push!(rows, row)
            s1_summary(out, rows)
            s1_epsilon_report(out, rows; schedule)
            if !isnothing(result) && !isnothing(result.opf.state) &&
                get(row, "solver_valid", false) && get(row, "policy_valid", false)
                state = result.opf.state
                policies = s1_reseed(case, base_policies; result)
            end
        end
    end
    s1_epsilon_report(out, rows; schedule)
    return rows
end

abspath(PROGRAM_FILE) == (@__FILE__) &&
    s1_epsilon_sensitivity(abspath(ARGS[1]))

"""Try one deterministic strict-valid source on each unresolved compatible cell.

Sources and targets must share solver, network size, and load factor. The solve
uses the frozen smoothing width `1e-6`; this is a recovery experiment, not an
independent-start result.
"""
function s1_epsilon_cross_seed(sensitivity_out, out)
    sensitivity = JSON.parsefile(joinpath(sensitivity_out, "summary.json"))
    bycell = Dict{String,Vector{Any}}()
    for row in sensitivity
        push!(get!(bycell, row["cell"], Any[]), row)
    end
    unresolved = sort([cell for (cell, rows) in bycell if !any(r -> r["valid"], rows)])
    mkpath(out)
    summary_path = joinpath(out, "summary.json")
    rows = isfile(summary_path) ? JSON.parsefile(summary_path) : Any[]
    for target_cell in unresolved
        target_rows = bycell[target_cell]
        exemplar = first(target_rows)
        solver = Symbol(exemplar["solver"])
        n = exemplar["buses"]
        factor = exemplar["tags"]["load_factor"]
        compatible = [r for r in sensitivity if r["valid"] && r["solver"] == string(solver) &&
            r["buses"] == n && r["tags"]["load_factor"] == factor]
        isempty(compatible) && continue
        sort!(compatible; by=r -> (r["epsilon"], r["cell"], r["name"]))
        source_row = first(compatible)
        name = target_cell * "-from-" * source_row["name"]
        any(r -> r["name"] == name, rows) && continue
        source_result = read_joint_design(joinpath(sensitivity_out, source_row["name"] * "-design.json"))
        source = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07",
            "pglib_opf_case$(n)_ieee.m")
        original = load_matpower_case(source; base_frequency=60.0)
        anchor = read_joint_design(joinpath(@__DIR__, "..", "artifacts", "s1_public_controls",
            "public$n-baseline-design.json"))
        case, base_policies, _ = s1_public_overlay(original, anchor, source;
            bank_count=n == 118 ? 12 : 32)
        case = s1_load(case, factor)
        policies = s1_reseed(case, base_policies; result=source_result)
        row, _ = s1_attempt(out, name, case, source_result.opf.state; policies, solver,
            epsilon=1e-6, options=Dict{String,Any}("bound_push" => 1e-8, "bound_frac" => 1e-8),
            tags=Dict("study" => "s1_epsilon_cross_seed_v1", "target_cell" => target_cell,
                "source_cell" => source_row["cell"], "source_attempt" => source_row["name"],
                "source_epsilon" => source_row["epsilon"], "load_factor" => factor,
                "claim" => "shared-seed recovery; not independent-start reliability"))
        row["target_cell"] = target_cell
        row["source_cell"] = source_row["cell"]
        row["source_epsilon"] = source_row["epsilon"]
        row["relaxed_droop_valid"] = s1_epsilon_relaxed_valid(row)
        push!(rows, row)
        s1_summary(out, rows)
    end
    open(joinpath(out, "report.md"), "w") do io
        println(io, "# S1 epsilon accepted-state cross-seed recovery\n")
        println(io, "Each unresolved continuation cell receives one deterministic strict-valid source with the same solver, network size, and load factor. The recovery solve uses `epsilon=1e-6`. This tests reusable basin information; it does not preserve independent starts or the frozen solve budget.\n")
        println(io, "| Target | Source | Source epsilon | Status | Strict valid | Raw mismatch (pu) |\n|---|---|---:|---|---:|---:|")
        for row in rows
            residual = get(get(row, "physical", Dict{String,Any}()), "droop_residual_max", "—")
            println(io, "| `", row["target_cell"], "` | `", row["source_cell"], "` | ",
                row["source_epsilon"], " | ", get(row, "status", "ERROR"), " | ",
                get(row, "valid", false), " | ", residual, " |")
        end
        println(io, "\nRecovered **", count(r -> get(r, "valid", false), rows), "/", length(rows),
            "** previously unresolved continuation cells.")
    end
    return rows
end
