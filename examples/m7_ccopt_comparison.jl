using DroopOPF, JSON, MadNLP
include("m7_2_case.jl")

function m7_ccopt_comparison(out)
    mkpath(out)
    case = m72_case()
    start = m5_initial_state(case)
    base = solve_opf(case; smooth_epsilon=1e-5, initial_state=start)
    attempts = Dict{String,Any}[]
    selected = Dict{String,Any}[]
    for solver in (:ipopt, :madnlp, :ccopt)
        candidates = Dict{String,Any}[]
        for run in 1:2
            taps = [TapControl(11; lower=.95, upper=1.05, initial=run==1 ? 1.02 : 1.)]
            shunts = [ShuntControl(201; initial=run==1 ? .02 : .04)]
            initial = run==1 ? start : base.state
            kwargs = solver==:ipopt ? (;smooth_epsilon=1e-5) :
                solver==:madnlp ? (;smooth_epsilon=1e-5,optimizer_factory=MadNLP.Optimizer) :
                (;encoding=:complementarity,optimizer_attributes=m5_ccopt_options())
            measured = @timed optimize_joint_design(case;tap_controls=taps,
                shunt_controls=shunts,initial_state=initial,kwargs...)
            result = measured.value
            check = validate_joint_design(case, result)
            physical = check.physical
            row = Dict(
            "solver" => String(solver),
            "run" => run,
            "start" => run==1 ? "supplied equipment / proportional state" :
                "tap=1 / B=.04 / solved fixed-equipment state",
            "encoding" => String(result.encoding),
            "status" => String(result.opf.termination_status),
            "primal_status" => String(result.opf.primal_status),
            "valid" => check.valid,
            "objective" => result.opf.objective,
            "tap" => result.taps[11],
            "shunt_B" => result.susceptances[201],
            "vm" => result.opf.state.vm,
            "qg" => result.opf.state.qg,
            "ac_residual" => physical.power_balance_max,
            "exact_droop_residual" => physical.droop_residual_max,
            "smooth_exact_gap" => physical.smooth_exact_droop_gap,
            "complementarity_residual" => result.complementarity_residual_max,
            "elapsed_seconds" => measured.time,
            "julia_allocated_bytes" => measured.bytes,
            )
            push!(attempts,row)
            row["valid"] && push!(candidates,row)
            write_joint_design(joinpath(out, "$(solver)-run$(run)-design.json"), result)
        end
        isempty(candidates) || push!(selected,deepcopy(candidates[argmin([r["objective"] for r in candidates])]))
    end
    reference = only(filter(r -> r["solver"] == "ipopt", selected))
    for row in selected
        row["objective_delta_from_ipopt"] = row["objective"] - reference["objective"]
        row["tap_delta_from_ipopt"] = row["tap"] - reference["tap"]
        row["shunt_delta_from_ipopt"] = row["shunt_B"] - reference["shunt_B"]
        same = filter(r -> r["solver"]==row["solver"] && r["valid"],attempts)
        row["valid_starts"] = length(same)
        row["objective_spread"] = maximum(r["objective"] for r in same)-minimum(r["objective"] for r in same)
        row["tap_spread"] = maximum(r["tap"] for r in same)-minimum(r["tap"] for r in same)
        row["shunt_spread"] = maximum(r["shunt_B"] for r in same)-minimum(r["shunt_B"] for r in same)
    end
    passed = length(selected)==3 && all(row["valid"] for row in attempts) &&
        only(filter(r -> r["solver"] == "ccopt", selected))["complementarity_residual"] < 1e-5
    evidence = Dict(
        "pass" => passed,
        "case_id" => case.id,
        "smooth_epsilon" => 1e-5,
        "continuous_equipment" => true,
        "fixed_droop_parameters" => true,
        "attempts" => attempts,
        "selected" => selected,
    )
    write(joinpath(out, "evidence.json"), JSON.json(evidence; pretty=true) * "\n")
    open(joinpath(out, "report.md"), "w") do io
        println(io, "# M7 exact-droop solver comparison\n")
        println(io, "Acceptance: **", passed ? "PASS" : "FAIL", "**. Ipopt and MadNLP use the same smoothed droop width (1e-5); CCOpt uses the exact fixed PWL droop graph. All three optimize identical continuous tap and simple-bank bounds, objective and physical model from two declared starts. Every attempt is retained; selection uses the lowest objective among independently valid outcomes.\n")
        println(io, "| Solver | Run | Encoding | Status | Valid | Objective | Tap 11 | Bank 201 B | Exact droop residual | Complementarity | Seconds |\n|---|---:|---|---|---|---:|---:|---:|---:|---:|---:|")
        for row in attempts
            println(io, "| ", row["solver"], " | ",row["run"]," | ", row["encoding"], " | ", row["status"], " | ", row["valid"], " | ", row["objective"], " | ", row["tap"], " | ", row["shunt_B"], " | ", row["exact_droop_residual"], " | ", row["complementarity_residual"], " | ",row["elapsed_seconds"]," |")
        end
        println(io, "\n| Solver | Selected run | Valid starts | Objective delta from Ipopt | Objective spread | Tap spread | Shunt-B spread |\n|---|---:|---:|---:|---:|---:|---:|")
        for row in selected
            println(io, "| ", row["solver"], " | ",row["run"]," | ",row["valid_starts"],"/2 | ", row["objective_delta_from_ipopt"], " | ",row["objective_spread"]," | ",row["tap_spread"]," | ",row["shunt_spread"]," |")
        end
        println(io, "\nThis is a local continuous comparison, not a discrete tap/shunt result or a global-optimality claim. Every result is replayed against reconstructed physical equipment and the exact droop curve.")
    end
    passed || error("matched CCOpt comparison failed")
    evidence
end

m7_ccopt_comparison(abspath(ARGS[1]))
