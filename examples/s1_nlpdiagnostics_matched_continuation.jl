using NLPDiagnostics
include("s1_policy_matrix.jl")

const S1_MATCHED_EPSILON_SCHEDULE = (1e-2, 1e-3, 1e-4, 1e-5, 1e-6)

"""Analyze a result point without modifying the solve model or its acceptance."""
function s1_matched_diagnostic_hook(label, destination)
    function hook(phase, model)
        phase == :solved || return
        has_values(model) || return
        point = NLPDiagnostics.solver_result_point(model; label=label * "-result")
        destination[] = NLPDiagnostics.analyze(model; point=point,
            check_initialization=false, check_active_set=true,
            check_coupled_set_qualification=true, check_degeneracy=true,
            rank_relative_tolerance=1e-8,
            jacobian_rank_tolerance_sweep_tolerances=[1e-10, 1e-8, 1e-6],
            jacobian_rank_tolerance_sweep_scaling=:row_column)
    end
end

"""Compare a failed direct solve and its accepted epsilon-continuation result.

The selected frozen cell, 118-bus/MadNLP/load 1.0/flat-low, was invalid in the
direct frozen run and strict-valid at epsilon=1e-6 after the fixed continuation
schedule. This is a diagnostic reproduction only: continuation remains outside
the frozen acceptance budget and diagnostics never change acceptance.
"""
function s1_nlpdiagnostics_matched_continuation(out;
    schedule=S1_MATCHED_EPSILON_SCHEDULE)
    mkpath(out)
    n, factor, solver, start_kind = 118, 1.0, :madnlp, :flat_low
    source = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07",
        "pglib_opf_case$(n)_ieee.m")
    original = load_matpower_case(source; base_frequency=60.0)
    anchor = read_joint_design(joinpath(@__DIR__, "..", "artifacts", "s1_public_controls",
        "public$(n)-baseline-design.json"))
    case, base_policies, _ = s1_public_overlay(original, anchor, source; bank_count=12)
    case = s1_load(case, factor)
    initial_state = s1_flat(case)
    initial_policies = s1_reseed(case, base_policies; fraction=0.2)

    direct_report = Ref{Any}(nothing)
    direct_row, _ = s1_attempt(out, "direct-epsilon-1e-6", case, initial_state;
        policies=initial_policies, solver, epsilon=1e-6,
        options=Dict{String,Any}("bound_push"=>1e-8, "bound_frac"=>1e-8),
        tags=Dict("study"=>"s1_nlpdiagnostics_matched_continuation_v1",
            "role"=>"failed_direct", "cell"=>"public118-load1.0-madnlp-flat_low"),
        experiment_hook=s1_matched_diagnostic_hook("direct-epsilon-1e-6", direct_report))

    state, policies = initial_state, initial_policies
    continuation_rows = Dict{String,Any}[]
    final_report = Ref{Any}(nothing)
    for epsilon in schedule
        name = "continuation-epsilon-$(replace(string(epsilon), "."=>"p", "-"=>"m"))"
        hook = epsilon == last(schedule) ?
            s1_matched_diagnostic_hook(name, final_report) : nothing
        row, result = s1_attempt(out, name, case, state; policies, solver, epsilon,
            options=Dict{String,Any}("bound_push"=>1e-8, "bound_frac"=>1e-8),
            tags=Dict("study"=>"s1_nlpdiagnostics_matched_continuation_v1",
                "role"=>"continuation_stage", "cell"=>"public118-load1.0-madnlp-flat_low",
                "warm_started"=>state !== initial_state), experiment_hook=hook)
        push!(continuation_rows, row)
        if !isnothing(result) && !isnothing(result.opf.state) &&
            get(row, "solver_valid", false) && get(row, "policy_valid", false)
            state = result.opf.state
            policies = s1_reseed(case, base_policies; result)
        end
    end

    # The immutable sensitivity artifact supplies the accepted endpoint even if
    # a fresh continuation replay takes a different numerical path. Re-solving
    # from that accepted state tests the basin without relabelling it as a new
    # frozen result.
    saved = read_joint_design(joinpath(@__DIR__, "..", "artifacts",
        "s1_epsilon_sensitivity",
        "public118-load1.0-madnlp-flat_low-epsilon-1p0em6-design.json"))
    accepted_report = Ref{Any}(nothing)
    accepted_row, _ = s1_attempt(out, "accepted-continuation-state-epsilon-1e-6",
        case, saved.opf.state; policies=s1_reseed(case, base_policies; result=saved), solver,
        epsilon=1e-6, options=Dict{String,Any}("bound_push"=>1e-8, "bound_frac"=>1e-8),
        tags=Dict("study"=>"s1_nlpdiagnostics_matched_continuation_v1",
            "role"=>"saved_accepted_continuation_state",
            "cell"=>"public118-load1.0-madnlp-flat_low"),
        experiment_hook=s1_matched_diagnostic_hook(
            "accepted-continuation-state-epsilon-1e-6", accepted_report))

    reports = Dict("failed_direct"=>direct_report[],
        "fresh_continuation_endpoint"=>final_report[],
        "saved_accepted_continuation"=>accepted_report[])
    for (role, report) in reports
        isnothing(report) && continue
        write(joinpath(out, role * "-nlpdiagnostics.md"), NLPDiagnostics.markdown_report(report))
        write(joinpath(out, role * "-nlpdiagnostics.json"),
            JSON.json(NLPDiagnostics.report_data(report); pretty=true) * "\n")
    end
    write(joinpath(out, "summary.json"), JSON.json(Dict(
        "cell"=>"public118-load1.0-madnlp-flat_low", "direct"=>direct_row,
        "continuation"=>continuation_rows, "saved_accepted_continuation"=>accepted_row,
        "diagnostic_reports"=>Dict(role=>isnothing(report) ? nothing :
            NLPDiagnostics.report_data(report) for (role, report) in reports)); pretty=true) * "\n")
    open(joinpath(out, "report.md"), "w") do io
        println(io, "# S1 matched direct-versus-continuation diagnostic\n")
        println(io, "One formerly invalid frozen cell is replayed from the same flat-low start both directly at epsilon=1e-6 and through the fixed continuation schedule. Diagnostics are attached only to those two endpoint result points; intermediate stages are retained as solve evidence.\n")
        println(io, "| Role | Status | Strict valid |\n|---|---|---:|")
        println(io, "| direct epsilon=1e-6 | ", get(direct_row, "status", "ERROR"), " | ", get(direct_row, "valid", false), " |")
        for row in continuation_rows
            println(io, "| continuation epsilon=", row["epsilon"], " | ", get(row, "status", "ERROR"), " | ", get(row, "valid", false), " |")
        end
        println(io, "| archived accepted continuation state, epsilon=1e-6 | ",
            get(accepted_row, "status", "ERROR"), " | ", get(accepted_row, "valid", false), " |")
        println(io, "\nThe raw NLPDiagnostics reports retain structural row and variable evidence. Interpret differences only alongside the independent exact-droop and AC-physical validation in `summary.json`.")
    end
    return direct_row, continuation_rows, reports
end

abspath(PROGRAM_FILE) == (@__FILE__) &&
    s1_nlpdiagnostics_matched_continuation(abspath(ARGS[1]))
