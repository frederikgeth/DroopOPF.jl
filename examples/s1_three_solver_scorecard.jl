using JSON

function s1_scorecard_rows(path)
    parsed = JSON.parsefile(path)
    rows = parsed isa AbstractVector ? parsed : parsed["rows"]
    Dict{String,Any}[Dict{String,Any}(row) for row in rows]
end

function s1_scorecard_final(row)
    haskey(row, "attempts") ? last(row["attempts"]) : row
end

function s1_scorecard_residual(row, final)
    if haskey(final, "exact_droop_audit")
        return final["exact_droop_audit"]["max_residual_pu"]
    end
    get(get(final, "physical", Dict()), "droop_residual_max", nothing)
end

function s1_scorecard_relaxed_valid(row; droop_tolerance=1e-2)
    final = s1_scorecard_final(row)
    get(final, "solver_valid", false) && get(final, "policy_valid", false) || return false
    physical = get(final, "physical", Dict())
    violations = Symbol.(get(physical, "violations", String[]))
    all(v -> v == :droop, violations) || return false
    residual = s1_scorecard_residual(row, final)
    !isnothing(residual) && isfinite(residual) && residual <= droop_tolerance
end

"""Summarize the comparable public S1 direct-solve lanes. CCOpt uses exact
complementarity and its native one-solve budget, so it is a third solver family
and a formulation comparison—not a like-for-like smooth-backend replacement.
"""
function s1_three_solver_scorecard(out;
    ipopt_summary=joinpath(@__DIR__, "..", "artifacts", "s1_policy_ipopt", "summary.json"),
    madnlp_summary=joinpath(@__DIR__, "..", "artifacts", "s1_policy_madnlp", "summary.json"),
    ccopt_summary=joinpath(@__DIR__, "..", "artifacts", "s1_ccopt_frozen", "summary.json"))
    lanes = [
        (solver="Ipopt", formulation="smooth explicit droop", budget="one reset; 2000 iterations / 120 s", path=ipopt_summary),
        (solver="MadNLP", formulation="smooth explicit droop", budget="one reset; 2000 iterations / 120 s", path=madnlp_summary),
        (solver="CCOpt", formulation="exact complementarity", budget="native direct; 1000 iterations / 60 s", path=ccopt_summary),
    ]
    rows = Dict{String,Any}[]
    for lane in lanes
        source_rows = s1_scorecard_rows(lane.path)
        push!(rows, Dict(
            "solver" => lane.solver,
            "formulation" => lane.formulation,
            "budget" => lane.budget,
            "cells" => length(source_rows),
            "strict_passes" => count(row -> get(row, "valid", false), source_rows),
            "relaxed_droop_1e2_passes" => count(row -> s1_scorecard_relaxed_valid(row), source_rows),
            "source" => relpath(lane.path, pwd()),
        ))
    end
    payload = Dict("schema" => "s1-three-solver-scorecard-v1",
        "scope" => "public 12-cell direct-start S1 lanes",
        "strict_exact_droop_tolerance_pu" => 1e-5,
        "relaxed_exact_droop_tolerance_pu" => 1e-2,
        "rows" => rows,
        "interpretation" => "CCOpt is an exact-complementarity third-solver lane with a native direct budget. Its score is comparable in cell coverage and independent acceptance, but not a same-formulation budget comparison with the smooth lanes.")
    mkpath(out)
    write(joinpath(out, "summary.json"), JSON.json(payload; pretty=true) * "\n")
    open(joinpath(out, "report.md"), "w") do io
        println(io, "# S1 three-solver direct-start scorecard\n")
        println(io, "All lanes cover the same 12 public cells: IEEE 118/300, nominal/+5% demand, and anchor/flat-low/flat-high starts. Ipopt and MadNLP use the frozen smooth explicit-droop model with their one-reset policy. CCOpt uses the exact-complementarity model and a native one-solve budget; it is retained as a third solver family, not pooled as a like-for-like smooth-solver result.\n")
        println(io, "| Solver | Formulation | Budget | Strict `1e-5` passes | Relaxed `1e-2` passes |\n|---|---|---|---:|---:|")
        for row in rows
            println(io, "| ", row["solver"], " | ", row["formulation"], " | ", row["budget"],
                " | ", row["strict_passes"], "/", row["cells"], " | ",
                row["relaxed_droop_1e2_passes"], "/", row["cells"], " |")
        end
        println(io, "\nThe `1e-2` column changes only exact-droop acceptance. Solver status, policy, AC balance, voltage, generator, and thermal gates remain mandatory. CCOpt does not gain a pass because every rejected CCOpt cell also fails solver or power-balance gates.")
    end
    payload
end

abspath(PROGRAM_FILE) == (@__FILE__) && s1_three_solver_scorecard(abspath(
    isempty(ARGS) ? joinpath(@__DIR__, "..", "artifacts", "s1_three_solver_scorecard") : ARGS[1]))
