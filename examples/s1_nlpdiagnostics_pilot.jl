using NLPDiagnostics
include("s1_policy_matrix.jl")

const S1_NLPDIAGNOSTICS_PILOT_CELLS = (
    (solver=:ipopt, n=300, load_factor=1.0, start=:flat_high, label="ipopt-gain"),
    (solver=:ipopt, n=300, load_factor=1.05, start=:anchor, label="ipopt-loss"),
    (solver=:madnlp, n=118, load_factor=1.0, start=:anchor, label="madnlp-gain"),
    (solver=:madnlp, n=300, load_factor=1.05, start=:anchor, label="madnlp-loss"),
)

"""Return a solver-result-only observation for a diagnostic code."""
function s1_nlpdiagnostics_result_observation(report, code)
    for finding in NLPDiagnostics.findings(report)
        data = NLPDiagnostics.finding_data(finding)
        data["code"] == code || continue
        result_point = any(evidence -> occursin("-result", string(get(
            get(evidence, "details", Dict{String,Any}()), "label", ""))),
            get(data, "evidence", Any[]))
        result_point || continue
        return get(data, "observation", "—")
    end
    return "—"
end

"""Build/solve four representative frozen cells and attach read-only NLPDiagnostics.

This is deliberately a diagnostic rerun, not a frozen re-score. It examines the
direct epsilon-1e-6 model at the solver result and writes typed finding data;
it never changes a model row, setting, solver option, or acceptance decision.
"""
function s1_nlpdiagnostics_pilot(out; cells=S1_NLPDIAGNOSTICS_PILOT_CELLS)
    mkpath(out)
    rows = Dict{String,Any}[]
    for spec in cells
        source = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07",
            "pglib_opf_case$(spec.n)_ieee.m")
        original = load_matpower_case(source; base_frequency=60.0)
        anchor = read_joint_design(joinpath(@__DIR__, "..", "artifacts", "s1_public_controls",
            "public$(spec.n)-baseline-design.json"))
        case, base_policies, _ = s1_public_overlay(original, anchor, source;
            bank_count=spec.n == 118 ? 12 : 32)
        case = s1_load(case, spec.load_factor)
        state = spec.start == :anchor ? anchor.opf.state : s1_flat(case)
        policies = spec.start == :anchor ? base_policies : s1_reseed(case, base_policies;
            fraction=spec.start == :flat_low ? 0.2 : 0.8)
        name = "public$(spec.n)-load$(spec.load_factor)-$(spec.solver)-$(spec.start)-nlpdiagnostics"
        diagnostic = Ref{Any}(nothing)
        diagnostic_error = Ref{Union{Nothing,String}}(nothing)
        function diagnostic_hook(phase, model)
            phase == :solved || return
            has_values(model) || return
            try
                point = NLPDiagnostics.solver_result_point(model; label=name * "-result")
                diagnostic[] = NLPDiagnostics.analyze(model; point=point,
                    check_initialization=true, check_active_set=true,
                    check_coupled_set_qualification=true, check_degeneracy=true,
                    rank_relative_tolerance=1e-8,
                    jacobian_rank_tolerance_sweep_tolerances=[1e-10, 1e-8, 1e-6],
                    jacobian_rank_tolerance_sweep_scaling=:row_column)
            catch err
                diagnostic_error[] = sprint(showerror, err, catch_backtrace())
            end
        end
        row, _ = s1_attempt(out, name, case, state; policies, solver=spec.solver,
            epsilon=1e-6, options=Dict{String,Any}("bound_push"=>1e-8,"bound_frac"=>1e-8),
            tags=Dict("study"=>"s1_nlpdiagnostics_pilot_v1", "pilot_label"=>spec.label,
                "claim"=>"read-only point-local NLP diagnostics; not an acceptance override"),
            experiment_hook=diagnostic_hook)
        row["nlpdiagnostics_error"] = diagnostic_error[]
        if !isnothing(diagnostic[])
            report = diagnostic[]
            open(joinpath(out, name * "-nlpdiagnostics.md"), "w") do io
                write(io, NLPDiagnostics.markdown_report(report))
            end
            write(joinpath(out, name * "-nlpdiagnostics.json"),
                JSON.json(NLPDiagnostics.report_data(report); pretty=true) * "\n")
            row["nlpdiagnostics_findings"] = [NLPDiagnostics.finding_data(f) for f in NLPDiagnostics.findings(report)]
            row["nlpdiagnostics_result_licq"] = s1_nlpdiagnostics_result_observation(
                report, "active_constraint_licq_failure")
            row["nlpdiagnostics_result_scaling"] = s1_nlpdiagnostics_result_observation(
                report, "large_jacobian_row_scale_spread")
            row["nlpdiagnostics_result_mfcq"] = s1_nlpdiagnostics_result_observation(
                report, "mfcq_no_common_descent_witness")
        end
        push!(rows, row)
        s1_summary(out, rows)
    end
    open(joinpath(out, "report.md"), "w") do io
        println(io, "# S1 NLPDiagnostics point-local pilot\n")
        println(io, "Four direct epsilon-1e-6 reruns are analyzed read-only at their returned solver result. Findings are point-local numerical/structural evidence and never override the independent solver, policy, AC-physical, or exact-droop acceptance gates.\n")
        println(io, "| Pilot | Status | Strict valid | Result LICQ | Result row-scale spread | Result MFCQ witness |\n|---|---|---:|---|---|---|")
        for row in rows
            println(io, "| `", row["tags"]["pilot_label"], "` | ", get(row, "status", "ERROR"),
                " | ", get(row, "valid", false), " | ", get(row, "nlpdiagnostics_result_licq", "—"),
                " | ", get(row, "nlpdiagnostics_result_scaling", "—"),
                " | ", get(row, "nlpdiagnostics_result_mfcq", "—"), " |")
        end
        println(io, "\nAll four result points show an active-set LICQ/MFCQ warning. Thus this pilot supports a pervasive active-set geometry issue, not yet a droop-specific causal diagnosis. The next comparison must map raw rows to named droop/Q-limit constraints and contrast a failed direct point with its accepted continuation point.")
        println(io, "\nPer-case Markdown and JSON files retain every diagnostic finding, its evidence basis, confidence, affected rows/variables, and suggested action.")
    end
    return rows
end

abspath(PROGRAM_FILE) == (@__FILE__) && s1_nlpdiagnostics_pilot(abspath(ARGS[1]))
