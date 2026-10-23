include("s1_restart_policy.jl")

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
