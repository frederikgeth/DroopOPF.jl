include("s1_policy_matrix.jl")

"""Audit the untouched PGLib imports at the uniform +5% P/Q stress point.

No overlay is applied: no synthetic droop attachments, no synthetic shunt banks,
and no adjustable transformer ratios. The source's generator limits, fixed
transformer ratios, fixed shunts, and branch data are retained verbatim. This
is a feasibility/solver check for the data path, not a reproduction of PGLib's
cost objective (DroopOPF uses its dispatch-deviation objective).
"""
function s1_source_stress_audit(out; networks=(118, 300), solvers=(:ipopt, :madnlp),
    factor=1.05)
    mkpath(out)
    rows = isfile(joinpath(out, "summary.json")) ?
        Dict{String,Any}[Dict{String,Any}(r) for r in JSON.parsefile(joinpath(out, "summary.json"))] :
        Dict{String,Any}[]
    completed = Set(r["name"] for r in rows)
    for n in networks
        source = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07",
            "pglib_opf_case$(n)_ieee.m")
        original = load_matpower_case(source; base_frequency=60.0)
        anchor = read_joint_design(joinpath(@__DIR__, "..", "artifacts",
            "s1_public_controls", "public$n-baseline-design.json"))
        validate_joint_design(original, anchor).valid || error("stored source anchor is invalid")
        stressed = s1_load(original, factor)
        for solver in solvers
            name = "pglib$n-raw-load$factor-$solver-anchor"
            name in completed && continue
            row, _ = s1_run_policy(out, name, stressed, anchor.opf.state;
                solver, tags=Dict("study"=>"s1_source_stress_audit_v1",
                    "network"=>n, "load_factor"=>factor,
                    "overlay"=>"none", "droop_attachments"=>0,
                    "adjustable_taps"=>0, "adjustable_banks"=>0,
                    "initialization"=>"validated raw nominal source solution"))
            push!(rows, row); push!(completed, name)
            write(joinpath(out, "summary.json"), JSON.json(rows; pretty=true) * "\n")
        end
    end
    open(joinpath(out, "report.md"), "w") do io
        println(io, "# Raw PGLib +5% stress audit\n")
        println(io, "The original imported cases are tested without the S1 overlay. Both active and reactive loads are multiplied by `", factor, "`; source generator limits, fixed shunts and fixed transformer ratios are unchanged. The solver starts from the validated nominal raw-source solution and receives the same one-reset policy used by the frozen matrix.\n")
        println(io, "| Network | Solver | Status | Strict valid |\n|---:|---|---|---:|")
        for row in sort(rows; by=r -> (r["tags"]["network"], r["solver"]))
            status = get(row, "selected", nothing)
            selected = isnothing(status) ? last(get(row, "attempts", [Dict("status"=>"ERROR")])) :
                only(filter(a -> a["name"] == status, row["attempts"]))
            println(io, "| ", row["tags"]["network"], " | ", row["solver"], " | ",
                get(selected, "status", "ERROR"), " | ", row["valid"], " |")
        end
        println(io, "\nA valid result is a local witness for the raw stressed DroopOPF import. An invalid result is solver/path evidence only and does not establish raw-case infeasibility.")
    end
    return rows
end

"""Find the verified raw-source loading path without the S1 overlay.

Each accepted point seeds only the next higher load. A failed stage is retained
and stops that solver's path, so the result is a verified continuation range,
not a claim about the actual loadability boundary.
"""
function s1_raw_load_continuation(out; network=300, solvers=(:ipopt, :madnlp),
    schedule=(1.00, 1.01, 1.02, 1.03, 1.04, 1.05))
    mkpath(out)
    rows = isfile(joinpath(out, "summary.json")) ?
        Dict{String,Any}[Dict{String,Any}(r) for r in JSON.parsefile(joinpath(out, "summary.json"))] :
        Dict{String,Any}[]
    completed = Set(r["name"] for r in rows)
    source = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07",
        "pglib_opf_case$(network)_ieee.m")
    original = load_matpower_case(source; base_frequency=60.0)
    anchor = read_joint_design(joinpath(@__DIR__, "..", "artifacts",
        "s1_public_controls", "public$(network)-baseline-design.json"))
    validate_joint_design(original, anchor).valid || error("stored source anchor is invalid")
    for solver in solvers
        state = anchor.opf.state
        active = true
        for factor in schedule
            name = "pglib$(network)-raw-continuation-load$(factor)-$solver"
            old = findfirst(r -> r["name"] == name, rows)
            if !isnothing(old)
                row = rows[old]
                if get(row, "valid", false)
                    design = read_joint_design(joinpath(out, row["selected"] * "-design.json"))
                    state = design.opf.state
                else
                    active = false
                end
                continue
            end
            active || break
            row, result = s1_run_policy(out, name, s1_load(original, factor), state; solver,
                tags=Dict("study"=>"s1_raw_load_continuation_v1", "network"=>network,
                    "load_factor"=>factor, "overlay"=>"none", "droop_attachments"=>0,
                    "adjustable_taps"=>0, "adjustable_banks"=>0,
                    "warm_start"=>factor != first(schedule)))
            push!(rows, row); push!(completed, name)
            write(joinpath(out, "summary.json"), JSON.json(rows; pretty=true) * "\n")
            if get(row, "valid", false) && !isnothing(result) && !isnothing(result.opf.state)
                state = result.opf.state
            else
                active = false
            end
        end
    end
    open(joinpath(out, "report.md"), "w") do io
        println(io, "# Raw PGLib load continuation\n")
        println(io, "Untouched PGLib IEEE-", network, " case: no droop overlay, synthetic bank, or adjustable transformer ratio. An accepted factor warm-starts only the next factor. A failed factor terminates that solver's path, so this is a conservative verified path rather than a loadability limit.\n")
        println(io, "| Solver | Load multiplier | Status | Strict valid |\n|---|---:|---|---:|")
        for row in sort(rows; by=r -> (r["solver"], r["tags"]["load_factor"]))
            attempt = isnothing(row["selected"]) ? last(row["attempts"]) :
                only(filter(a -> a["name"] == row["selected"], row["attempts"]))
            println(io, "| ", row["solver"], " | ", row["tags"]["load_factor"], " | ",
                get(attempt, "status", "ERROR"), " | ", row["valid"], " |")
        end
    end
    return rows
end

abspath(PROGRAM_FILE) == (@__FILE__) && s1_source_stress_audit(abspath(ARGS[1]))
