include("s1_incremental_controls.jl")

function s1_validation_data(report)
    Dict(
        "valid" => report.valid,
        "power_balance_max" => report.power_balance_max,
        "exact_droop_max" => report.droop_residual_max,
        "violations" => string.(report.violations),
        "voltage_min_margin" => report.voltage_min_margin,
        "voltage_max_margin" => report.voltage_max_margin,
        "generator_q_min_margin" => report.generator_q_min_margin,
        "generator_q_max_margin" => report.generator_q_max_margin,
        "branch_thermal_min_margin" => report.branch_thermal_min_margin,
    )
end

function s1_named_row(summary, name)
    parsed = JSON.parsefile(summary)
    rows = parsed isa AbstractVector ? parsed : parsed["rows"]
    matches = filter(row -> row["name"] == name, rows)
    length(matches) == 1 || error("expected one row named $name in $summary")
    only(matches)
end

"""Replay a valid six-controller state after removing controller equalities.

This is a no-solve feasibility proof for the raw, cumulative-five, and
controller-5-only models. It deliberately preserves the load, network,
generator bounds, controller curves, and strict validation tolerances.
"""
function s1_controller5_witness_audit(out;
    incremental_dir=joinpath(@__DIR__, "..", "artifacts", "s1_incremental_controls"),
    selected_dir=joinpath(@__DIR__, "..", "artifacts", "s1_incremental_control5"),
    solvers=(:ipopt, :madnlp))
    source = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07",
        "pglib_opf_case300_ieee.m")
    original = load_matpower_case(source; base_frequency=60.0)
    anchor = read_joint_design(joinpath(@__DIR__, "..", "artifacts", "s1_public_controls",
        "public300-baseline-design.json"))
    raw, _, _ = s1_incremental_case(original, anchor, source; droop_count=0, shunt_count=0)
    cumulative5, _, _ = s1_incremental_case(original, anchor, source;
        droop_count=5, shunt_count=0)
    selected5, _ = s1_selected_droop_case(original, anchor, source, (5,))
    raw = s1_load(raw, 1.02)
    cumulative5 = s1_load(cumulative5, 1.02)
    selected5 = s1_load(selected5, 1.02)

    rows = Dict{String,Any}[]
    for solver in solvers
        witness_name = "public300-load1.02-$(solver)-droop6-fixed-anchor-attempt1"
        witness_path = joinpath(incremental_dir, witness_name * "-design.json")
        isfile(witness_path) || error("missing six-controller witness $witness_path")
        witness = read_joint_design(witness_path)
        audits = Dict(
            "raw" => s1_validation_data(validate_equilibrium(raw, witness.opf)),
            "cumulative_first_five" =>
                s1_validation_data(validate_equilibrium(cumulative5, witness.opf)),
            "controller_5_only" =>
                s1_validation_data(validate_equilibrium(selected5, witness.opf)),
        )
        all(audit["valid"] for audit in values(audits)) ||
            error("six-controller $solver witness did not survive constraint removal")

        cumulative_failure = s1_named_row(joinpath(incremental_dir, "summary.json"),
            "public300-load1.02-$(solver)-droop5-fixed-anchor")
        selected_failure = s1_named_row(joinpath(selected_dir, "summary.json"),
            "public300-load1.02-$(solver)-selected5-fixed-anchor")
        push!(rows, Dict(
            "solver" => string(solver),
            "witness" => relpath(witness_path, pwd()),
            "witness_source_model" => "cumulative first six fixed droop controllers",
            "replayed_models" => audits,
            "failed_direct_paths" => [Dict(
                "cell" => failure["name"],
                "final_status" => last(failure["attempts"])["status"],
                "strict_accepted" => failure["valid"],
            ) for failure in (cumulative_failure, selected_failure)],
            "classification" => "solver_path_failure_with_witness",
        ))
    end

    payload = Dict(
        "schema" => "s1-controller5-witness-audit-v1",
        "network" => 300,
        "load_factor" => 1.02,
        "control" => Dict("overlay_id" => 5, "generator_id" => 11, "bus_id" => 119),
        "method" => "remove droop equalities from a strictly validated six-controller state and independently revalidate",
        "changes_to_physical_problem" => "none; only controller equalities are removed",
        "conclusion" => "the direct five-controller and controller-5-only failures are solver-path failures, not infeasibility certificates",
        "rows" => rows,
    )
    mkpath(out)
    write(joinpath(out, "summary.json"), JSON.json(payload; pretty=true) * "\n")
    open(joinpath(out, "report.md"), "w") do io
        println(io, "# IEEE-300 controller-5 deterministic witness replay\n")
        println(io, "At load 1.02, both backends' strictly valid cumulative-six fixed-droop states remain strictly valid after removing controller 6, and after retaining controller 5 alone. No solve, relaxation, re-anchoring, or tolerance change is used.\n")
        println(io, "| Witness backend | Replayed model | Valid | Max balance residual | Max exact-droop residual |\n|---|---|---:|---:|---:|")
        for row in rows, model in ("raw", "cumulative_first_five", "controller_5_only")
            audit = row["replayed_models"][model]
            println(io, "| ", row["solver"], " | ", model, " | ", audit["valid"],
                " | ", audit["power_balance_max"], " | ", audit["exact_droop_max"], " |")
        end
        println(io, "\nThe matching direct five-controller and controller-5-only anchor paths fail for both Ipopt and MadNLP. The retained feasible states therefore classify those failures as `solver_path_failure_with_witness`; `LOCALLY_INFEASIBLE` is not a case-level infeasibility certificate here.")
    end
    payload
end

abspath(PROGRAM_FILE) == (@__FILE__) && s1_controller5_witness_audit(
    abspath(isempty(ARGS) ? joinpath(@__DIR__, "..", "artifacts", "s1_controller5_witness") : ARGS[1]))
