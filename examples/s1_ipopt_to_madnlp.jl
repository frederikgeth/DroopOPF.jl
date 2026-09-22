include("s1_restart_policy.jl")

function s1_valid_objective(row)
    index = findfirst(attempt -> attempt["valid"], row["attempts"])
    isnothing(index) ? nothing : row["attempts"][index]["objective"]
end

"""Run MadNLP from each independently validated explicit-formulation Ipopt result.

Only physical primal information is transferred: AC state plus tap, shunt and
droop-design settings. Solver multipliers are intentionally not transferred
between backends. Each target keeps the frozen one-reset budget and independent
physical validation used by the policy matrix.
"""
function s1_ipopt_to_madnlp(out;
    ipopt_summary=joinpath(@__DIR__, "..", "artifacts", "s1_policy_ipopt", "summary.json"),
    madnlp_summary=joinpath(@__DIR__, "..", "artifacts", "s1_policy_madnlp", "summary.json"),
)
    mkpath(out)
    ipopt_rows = JSON.parsefile(ipopt_summary)
    madnlp_rows = JSON.parsefile(madnlp_summary)
    direct_by_key = Dict(
        (row["buses"], Float64(row["tags"]["load_factor"]), row["tags"]["start"]) => row
        for row in madnlp_rows
    )
    rows = Any[]
    comparisons = Any[]
    for source_row in ipopt_rows
        source_row["valid"] || continue
        buses = Int(source_row["buses"])
        load_factor = Float64(source_row["tags"]["load_factor"])
        start_kind = String(source_row["tags"]["start"])
        source = joinpath(
            @__DIR__, "..", "test", "data", "pglib", "v23.07",
            "pglib_opf_case$(buses)_ieee.m",
        )
        original = load_matpower_case(source; base_frequency=60.)
        anchor = read_joint_design(joinpath(
            @__DIR__, "..", "artifacts", "s1_public_controls",
            "public$(buses)-baseline-design.json",
        ))
        case, policies, _ = s1_public_overlay(
            original, anchor, source; bank_count=buses == 118 ? 12 : 32,
        )
        case = s1_load(case, load_factor)
        selected = source_row["selected"]
        source_result = read_joint_design(joinpath(dirname(ipopt_summary), selected * "-design.json"))
        source_check = validate_joint_design(case, source_result)
        source_check.valid || error("retained Ipopt source is not physically valid: $selected")
        warm_policies = s1_reseed(case, policies; result=source_result)
        name = "public$(buses)-load$(load_factor)-madnlp-from-ipopt-$(start_kind)"
        tags = Dict(
            "study" => "cross_solver_physical_warm_start",
            "load_factor" => load_factor,
            "start" => start_kind,
            "source_solver" => "ipopt",
            "source_case" => source_row["name"],
            "source_attempt" => selected,
            "source_objective" => source_result.opf.objective,
            "initialization" => "Ipopt validated AC state and optimized physical settings; no dual transfer",
        )
        row, result = s1_run_policy(
            out, name, case, source_result.opf.state;
            policies=warm_policies, solver=:madnlp, tags,
        )
        row["valid"] && (row["source_audit"] = s1_source_audit(case, result, source))
        direct = direct_by_key[(buses, load_factor, start_kind)]
        push!(comparisons, Dict(
            "case" => source_row["name"],
            "buses" => buses,
            "load_factor" => load_factor,
            "start" => start_kind,
            "ipopt_valid" => source_row["valid"],
            "ipopt_objective" => source_result.opf.objective,
            "madnlp_direct_valid" => direct["valid"],
            "madnlp_direct_objective" => s1_valid_objective(direct),
            "madnlp_warm_valid" => row["valid"],
            "madnlp_warm_objective" => row["valid"] ? result.opf.objective : nothing,
            "madnlp_warm_events" => row["events"],
            "madnlp_warm_iterations" => row["iterations"],
        ))
        push!(rows, row)
        write(joinpath(out, "summary.json"), JSON.json(rows; pretty=true))
        write(joinpath(out, "comparison.json"), JSON.json(comparisons; pretty=true))
        println("COMPARISON ", name, " valid=", row["valid"]); flush(stdout)
    end
    comparisons
end

abspath(PROGRAM_FILE) == (@__FILE__) && s1_ipopt_to_madnlp(abspath(ARGS[1]))
