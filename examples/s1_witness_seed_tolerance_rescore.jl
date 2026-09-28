include("s1_policy_matrix.jl")

"""Re-score retained witness-seed outcomes with only the exact-droop tolerance
relaxed. No solver is called and the frozen or strict witness-seed decisions are
not modified.
"""
function s1_witness_seed_tolerance_rescore(out;
    source_dir=joinpath(@__DIR__, "..", "artifacts", "s1_frozen_witness_seed_matrix"),
    droop_tolerance=1e-2)
    droop_tolerance > 0 || throw(ArgumentError("droop tolerance must be positive"))
    source_summary = JSON.parsefile(joinpath(source_dir, "summary.json"))
    rows = Dict{String,Any}[]
    for source_row in source_summary["rows"]
        tags = source_row["tags"]
        n, load = source_row["buses"], tags["load_factor"]
        source = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07",
            "pglib_opf_case$(n)_ieee.m")
        original = load_matpower_case(source; base_frequency=60.0)
        anchor = read_joint_design(joinpath(@__DIR__, "..", "artifacts", "s1_public_controls",
            "public$(n)-baseline-design.json"))
        case, _, _ = s1_public_overlay(original, anchor, source;
            bank_count=n == 118 ? 12 : 32)
        case = s1_load(case, load)
        final = last(source_row["attempts"])
        design_path = joinpath(source_dir, final["name"] * "-design.json")
        design = read_joint_design(design_path)
        strict = validate_joint_design(case, design)
        relaxed = validate_joint_design(case, design; droop_tolerance=droop_tolerance)
        push!(rows, Dict(
            "direct_cell" => tags["direct_cell"],
            "solver" => source_row["solver"],
            "direct_frozen_valid" => source_row["valid"],
            "strict_witness_seed_valid" => strict.valid,
            "relaxed_witness_seed_valid" => relaxed.valid,
            "final_status" => final["status"],
            "raw_exact_droop_max" => isnothing(strict.physical) ? nothing :
                strict.physical.droop_residual_max,
            "other_gates_valid" => relaxed.solver_valid && relaxed.policy_valid &&
                !isnothing(relaxed.physical) &&
                isempty(setdiff(relaxed.physical.violations, [:droop])),
            "design" => relpath(design_path, pwd()),
        ))
    end
    strict_count = count(row -> row["strict_witness_seed_valid"], rows)
    relaxed_count = count(row -> row["relaxed_witness_seed_valid"], rows)
    payload = Dict("schema" => "s1-witness-seed-tolerance-rescore-v1",
        "scope" => "read-only re-score of retained full-decision witness-seed outcomes",
        "strict_exact_droop_tolerance_pu" => 1e-5,
        "relaxed_exact_droop_tolerance_pu" => droop_tolerance,
        "strict_passes" => strict_count, "relaxed_passes" => relaxed_count,
        "rows" => rows,
        "unchanged_gates" => ["solver termination", "policy", "power balance",
            "voltage", "generator limits", "thermal limits"],
        "not_claimed" => "The relaxed decision does not replace the frozen or strict witness-seed decision.")
    mkpath(out)
    write(joinpath(out, "summary.json"), JSON.json(payload; pretty=true) * "\n")
    open(joinpath(out, "report.md"), "w") do io
        println(io, "# Witness-seed exact-droop tolerance re-score\n")
        println(io, "This is a read-only re-score of the retained full-decision witness-seed matrix. Only exact-droop tolerance changes from `1e-5` to `", droop_tolerance, "` pu; solver, policy, balance, voltage, generator-limit, and thermal gates remain mandatory. No solver run or frozen artifact is modified.\n")
        println(io, "| Direct cell | Solver | Strict witness-seed | Relaxed witness-seed | Final status | Raw exact-droop mismatch |\n|---|---|---:|---:|---|---:|")
        for row in sort(rows; by=row -> row["direct_cell"])
            println(io, "| ", row["direct_cell"], " | ", row["solver"], " | ",
                row["strict_witness_seed_valid"], " | ", row["relaxed_witness_seed_valid"],
                " | ", row["final_status"], " | ", row["raw_exact_droop_max"], " |")
        end
        println(io, "\nStrict passes: **", strict_count, "/", length(rows),
            "**. Relaxed passes: **", relaxed_count, "/", length(rows), "**.")
    end
    payload
end

abspath(PROGRAM_FILE) == (@__FILE__) && s1_witness_seed_tolerance_rescore(abspath(
    isempty(ARGS) ? joinpath(@__DIR__, "..", "artifacts", "s1_witness_seed_tolerance_1e-2") : ARGS[1]))
