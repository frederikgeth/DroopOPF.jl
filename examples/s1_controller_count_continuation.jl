include("s1_incremental_controls.jl")

"""Solve the original fixed five-controller models from same-backend valid
six-controller states. This changes only the initial state: equations, bounds,
smoothing, strict gates, and one-reset budget remain frozen.
"""
function s1_controller_count_continuation(out; solvers=(:ipopt, :madnlp))
    mkpath(out)
    source = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07",
        "pglib_opf_case300_ieee.m")
    original = load_matpower_case(source; base_frequency=60.0)
    anchor = read_joint_design(joinpath(@__DIR__, "..", "artifacts", "s1_public_controls",
        "public300-baseline-design.json"))
    incremental = joinpath(@__DIR__, "..", "artifacts", "s1_incremental_controls")
    cumulative5, _, _ = s1_incremental_case(original, anchor, source;
        droop_count=5, shunt_count=0)
    selected5, _ = s1_selected_droop_case(original, anchor, source, (5,))
    cases = Dict("cumulative_first_five" => s1_load(cumulative5, 1.02),
        "controller_5_only" => s1_load(selected5, 1.02))
    rows = Dict{String,Any}[]
    for solver in solvers
        witness_name = "public300-load1.02-$(solver)-droop6-fixed-anchor-attempt1"
        witness_path = joinpath(incremental, witness_name * "-design.json")
        witness = read_joint_design(witness_path)
        witness_check = validate_equilibrium(s1_load(
            s1_incremental_case(original, anchor, source; droop_count=6, shunt_count=0)[1],
            1.02), witness.opf)
        witness_check.valid || error("source six-controller witness is not strictly valid")
        for (model_name, case) in sort(collect(cases); by=first)
            name = "public300-load1.02-$(solver)-$(model_name)-from-six"
            tags = Dict("study" => "s1_controller_count_continuation_v1",
                "network" => 300, "load_factor" => 1.02,
                "target_model" => model_name, "target_controller_count" =>
                    model_name == "cumulative_first_five" ? 5 : 1,
                "source_controller_count" => 6, "source_solver" => string(solver),
                "source_witness" => relpath(witness_path, pwd()),
                "start" => "validated_six_controller_state",
                "model_change" => "remove controller equalities only")
            row, _ = s1_run_policy(out, name, case, witness.opf.state;
                policies=(tap_controls=TapControl[], shunt_controls=ShuntControl[],
                    droop_controls=DroopControl[]),
                solver, epsilon=1e-6, tags)
            row["reason"] = s1_incremental_reason(row)
            row["classification"] = row["valid"] ? "validated_feasible" :
                "continuation_path_failure_with_input_witness"
            push!(rows, row)
        end
    end
    payload = Dict("schema" => "s1-controller-count-continuation-v1",
        "scope" => "IEEE-300 load 1.02 fixed-droop six-to-five equality removal",
        "contract" => Dict("smooth_epsilon" => 1e-6,
            "exact_droop_tolerance" => 1e-5, "policy" => "one-reset-v1",
            "changed" => ["initial state", "removed controller equalities"],
            "unchanged" => ["network", "load", "controller curves", "bounds",
                "objective", "smoothing", "strict validation", "solve budget"]),
        "rows" => rows)
    write(joinpath(out, "summary.json"), JSON.json(payload; pretty=true) * "\n")
    open(joinpath(out, "report.md"), "w") do io
        println(io, "# IEEE-300 controller-count continuation\n")
        println(io, "Each original fixed five-controller or controller-5-only model is solved from the same backend's strictly valid cumulative-six state. Only the initial state and removal of controller equalities differ from the frozen target; physical equations, limits, smoothing, strict gates, and one-reset budget are unchanged.\n")
        println(io, "| Target model | Backend | Result | Final status | Attempts | Maximum balance residual | Maximum exact-droop residual |\n|---|---|---|---|---:|---:|---:|")
        for row in sort(rows; by=r -> (r["tags"]["target_model"], r["solver"]))
            final = last(row["attempts"])
            physical = get(final, "physical", Dict())
            println(io, "| ", row["tags"]["target_model"], " | ", row["solver"],
                " | ", row["valid"] ? "PASS" : "FAIL", " | ", final["status"],
                " | ", length(row["attempts"]), " | ",
                get(physical, "power_balance_max", nothing), " | ",
                get(physical, "droop_residual_max", nothing), " |")
        end
        println(io, "\nA pass demonstrates a reliable path from a stricter feasible model to the relaxed target for that backend. It does not replace the frozen direct-start outcome; both are retained.")
    end
    payload
end

abspath(PROGRAM_FILE) == (@__FILE__) && s1_controller_count_continuation(abspath(
    isempty(ARGS) ? joinpath(@__DIR__, "..", "artifacts", "s1_controller_count_continuation") : ARGS[1]))
