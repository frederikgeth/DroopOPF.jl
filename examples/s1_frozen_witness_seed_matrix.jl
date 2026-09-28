include("s1_policy_matrix.jl")

function s1_witness_seed_candidates(rows, target)
    same_case = filter(row -> row["buses"] == target["buses"] &&
        row["tags"]["load_factor"] == target["tags"]["load_factor"] &&
        get(row, "valid", false), rows)
    same_solver = filter(row -> row["solver"] == target["solver"], same_case)
    pool = isempty(same_solver) ? same_case : same_solver
    isempty(pool) && return nothing
    witness = first(sort(pool; by=row -> row["name"]))
    Dict("row" => witness,
        "compatibility" => witness["solver"] == target["solver"] ?
            "same_backend_primal" : "cross_backend_primal_no_duals")
end

"""Replay every unresolved frozen direct-start cell from a validated same-case
witness, preferring the same backend. The target model and one-reset budget are
unchanged; this is a separately labelled seed-sensitivity matrix.
"""
function s1_frozen_witness_seed_matrix(out;
    ipopt_dir=joinpath(@__DIR__, "..", "artifacts", "s1_policy_ipopt"),
    madnlp_dir=joinpath(@__DIR__, "..", "artifacts", "s1_policy_madnlp"))
    mkpath(out)
    source_dirs = Dict(:ipopt => ipopt_dir, :madnlp => madnlp_dir)
    baseline_rows = Dict{String,Any}[]
    for dir in values(source_dirs)
        append!(baseline_rows, Dict{String,Any}[Dict{String,Any}(row)
            for row in JSON.parsefile(joinpath(dir, "summary.json"))])
    end
    targets = filter(row -> !get(row, "valid", false), baseline_rows)
    rows = Dict{String,Any}[]
    for target in sort(targets; by=row -> row["name"])
        seed = s1_witness_seed_candidates(baseline_rows, target)
        seed === nothing && error("no validated same-case witness for $(target["name"])")
        witness = seed["row"]
        witness_dir = source_dirs[Symbol(witness["solver"])]
        witness_design = joinpath(witness_dir, witness["selected"] * "-design.json")
        witness_result = read_joint_design(witness_design)
        witness_state = witness_result.opf.state
        isnothing(witness_state) && error("witness has no state: $witness_design")
        n = target["buses"]
        load = target["tags"]["load_factor"]
        source = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07",
            "pglib_opf_case$(n)_ieee.m")
        original = load_matpower_case(source; base_frequency=60.0)
        anchor = read_joint_design(joinpath(@__DIR__, "..", "artifacts", "s1_public_controls",
            "public$(n)-baseline-design.json"))
        case, policies, _ = s1_public_overlay(original, anchor, source;
            bank_count=n == 118 ? 12 : 32)
        case = s1_load(case, load)
        target_solver = Symbol(target["solver"])
        name = target["name"] * "-from-witness"
        tags = Dict("study" => "s1_frozen_witness_seed_matrix_v1",
            "start" => "validated_same_case_witness",
            "load_factor" => load,
            "direct_cell" => target["name"],
            "direct_final_status" => last(target["attempts"])["status"],
            "witness_cell" => witness["name"],
            "witness_solver" => witness["solver"],
            "witness_design" => relpath(witness_design, pwd()),
            "seed_compatibility" => seed["compatibility"],
            "seed_duals" => "not transferred",
            "target_equations" => "unchanged frozen explicit smooth model",
            "frozen_acceptance_replaced" => false)
        witness_policies = s1_reseed(case, policies; result=witness_result)
        tags["seed_settings"] = "validated tap, shunt, and droop settings from witness"
        row, _ = s1_run_policy(out, name, case, witness_state;
            policies=witness_policies, solver=target_solver, epsilon=1e-6, tags)
        row["classification"] = row["valid"] ? "witness_seed_strict_pass" :
            "witness_seed_path_failure"
        push!(rows, row)
    end
    payload = Dict("schema" => "s1-frozen-witness-seed-matrix-v1",
        "scope" => "unresolved frozen direct-start cells only",
        "direct_frozen_cells" => length(targets),
        "strict_witness_seed_passes" => count(row -> row["valid"], rows),
        "rows" => rows,
        "interpretation" => "A witness-seed pass establishes basin sensitivity for that direct failure. A witness-seed failure does not establish infeasibility.")
    write(joinpath(out, "summary.json"), JSON.json(payload; pretty=true) * "\n")
    open(joinpath(out, "report.md"), "w") do io
        println(io, "# Frozen S1 same-case witness-seed matrix\n")
        println(io, "Each unresolved direct frozen cell is rerun with unchanged model, smoothing, strict validation and one-reset budget, using a validated witness from the same network/load case. The seed contains the full physical decision: AC state plus tap, shunt, and droop settings. Same-backend seeds are preferred; cross-backend seeds transfer physical primals only, never duals. This does not replace the direct-start matrix.\n")
        println(io, "| Direct cell | Direct status | Target backend | Witness | Seed compatibility | Result | Final status | Attempts |\n|---|---|---|---|---|---|---|---:|")
        for row in sort(rows; by=row -> row["tags"]["direct_cell"])
            final = last(row["attempts"])
            println(io, "| ", row["tags"]["direct_cell"], " | ",
                row["tags"]["direct_final_status"], " | ", row["solver"], " | ",
                row["tags"]["witness_cell"], " | ", row["tags"]["seed_compatibility"],
                " | ", row["valid"] ? "PASS" : "FAIL", " | ", final["status"],
                " | ", length(row["attempts"]), " |")
        end
        println(io, "\nStrict witness-seed passes: **", payload["strict_witness_seed_passes"],
            "/", length(rows), "**. A failure remains solver-path evidence, not an infeasibility certificate.")
    end
    payload
end

abspath(PROGRAM_FILE) == (@__FILE__) && s1_frozen_witness_seed_matrix(abspath(
    isempty(ARGS) ? joinpath(@__DIR__, "..", "artifacts", "s1_frozen_witness_seed_matrix") : ARGS[1]))
