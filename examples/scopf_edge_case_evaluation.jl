using DroopOPF
include("m2_case.jl")
include("scopf_validation_cases.jl")

output = isempty(ARGS) ? mktempdir(prefix="droopopf-scopf-evaluation-") : abspath(ARGS[1])
case = m2_case()
study = Study(case;
    contingencies=[
        Contingency(:line_22; branch_ids=[22]),
        Contingency(:generator_9; generator_ids=[9]),
    ], participation=Dict(7=>1.0, 9=>1.0))
result = solve_scopf(study; smooth_epsilon=1e-5)
report = equilibrium_report(study,result)
report.valid || error(markdown_report(report))

accepted_directory = joinpath(output,"accepted")
mkpath(accepted_directory)
write_study(joinpath(accepted_directory,"study.json"),study)
write_scopf_result(joinpath(accepted_directory,"result.json"),result)
write_scopf_report(joinpath(accepted_directory,"report.json"),report)
write(joinpath(accepted_directory,"report.md"),markdown_report(report)*"\n")
accepted_plots = write_scopf_validation_plots(accepted_directory,study,result)
write_scopf_evaluation_report(joinpath(accepted_directory,"evaluation.md"),study,result;
    plot_paths=accepted_plots)

# Explicit negative-control artifact: an outaged generator is assigned nonzero
# reactive power. Independent replay and the validation matrix must reject it.
corrupted = deepcopy(result)
corrupted.states[:generator_9].qg[2] = 0.1
invalid_report = equilibrium_report(study,corrupted)
invalid_report.valid && error("negative control unexpectedly validated")
invalid_directory = joinpath(output,"invalid-outaged-generator")
mkpath(invalid_directory)
write_scopf_result(joinpath(invalid_directory,"result.json"),corrupted)
write_scopf_report(joinpath(invalid_directory,"report.json"),invalid_report)
write(joinpath(invalid_directory,"report.md"),markdown_report(invalid_report)*"\n")
invalid_plots = write_scopf_validation_plots(invalid_directory,study,corrupted)
write_scopf_evaluation_report(joinpath(invalid_directory,"evaluation.md"),study,corrupted;
    plot_paths=invalid_plots, context="Deliberate negative control: outaged generator Q was corrupted; this is not a solver-produced solution.")

# Missing-state negative control must retain the report without inventing passes.
missing = deepcopy(result)
missing.states[:line_22] = nothing
write_scopf_evaluation_report(joinpath(output, "missing-state", "evaluation.md"), study, missing;
    context="Deliberate negative control: a contingency state was removed to test incomplete-result reporting.")

# Separate negative controls localize voltage and active-power validation failures.
# These are deliberately corrupted outputs, not claimed feasible stressed solves.
for (name, change!) in (
    ("invalid-voltage", state -> (state.vm[3] = 1.2)),
    ("invalid-active-balance", state -> (state.pg[1] += 0.2)),
)
    candidate = deepcopy(result)
    change!(candidate.states[:base])
    equilibrium_report(study, candidate).valid && error("negative control unexpectedly validated")
    write_scopf_evaluation_report(joinpath(output, name, "evaluation.md"), study, candidate;
        context="Deliberate negative control ($name): saved outputs were corrupted; this is not a solver-produced stressed operating point.")
end

# Genuine changed-input solves, retaining rejected outcomes for diagnosis.
for (name, limit, demand) in (("tight-thermal", 0.65, 0.6),
    ("insufficient-post-outage-capacity", 2.0, 1.4))
    stressed = Study(m2_case(thermal_limit=limit, demand=demand);
        contingencies=study.contingencies, participation=study.participation)
    candidate = solve_scopf(stressed; smooth_epsilon=1e-5,
        optimizer_attributes=Dict("max_iter" => 300))
    write_scopf_evaluation_report(joinpath(output, name, "evaluation.md"), stressed, candidate;
        context="Changed-input solve: thermal limit=$limit pu; active demand=$demand pu. Acceptance is determined by the independent report, not assumed. Iteration budget: 300.")
end

println("Accepted, changed-input, and explicitly labelled negative-control SCOPF evaluation bundles: $output")

summary = ["# SCOPF validation evidence", "",
    "All networks here contain two, three or five buses. This evaluates steady-state AC security, not dynamic security or global optimality.", "",
    "## SCOPF solves and negative controls", "",
    "Negative controls deliberately alter saved outputs. Changed-input cases are genuine solves; a local solver rejection is unresolved evidence, not a general infeasibility proof.", ""]
for name in ("accepted", "invalid-outaged-generator", "missing-state", "invalid-voltage",
    "invalid-active-balance", "tight-thermal", "insufficient-post-outage-capacity")
    push!(summary, "- [$name]($name/evaluation.md)")
end
push!(summary, "", "## Screening compared with exhaustive AC evaluation", "",
    "Every available line, transformer and generator outage is evaluated in the reference run. A screened unresolved outcome is a miss, including solver failures. Recall is undefined when there are no unresolved outcomes; budget plots therefore report counts, not a fabricated 100% recall.", "",
    "| Input case | Device family | Total | Screened | Unresolved | Screened unresolved | Screened physical failures |",
    "|---|---|---:|---:|---:|---:|---:|")
expectation_rows = String[]
for kind in (:benign, :thermal, :voltage, :reactive, :transformer, :voltage_guard_disabled)
    small = scopf_parallel_case(kind == :voltage_guard_disabled ? :voltage : kind)
    baseline = scopf_validation_base(small)
    equilibrium_report(small,baseline).valid || error("invalid qualification base: $kind")
    comparison = validate_contingency_filter(small,baseline.state;
        voltage_guard=kind == :voltage_guard_disabled ? 0.0 : 0.02,
        reactive_guard=kind == :voltage_guard_disabled ? 0.0 : 0.1,
        ac_risk_guard=kind != :voltage_guard_disabled,
        optimizer_attributes=Dict("max_iter"=>300))
    ranks = comparison.exact.combined_ranking
    expected, matches = if kind in (:benign,:transformer)
        ("All outages accepted; both branch outages screened",
            comparison.exact.checks.all_outcomes_accepted && sum(r.screened for r in comparison.families) == 2)
    elseif kind in (:thermal,:voltage)
        ("Both branch outages unresolved and escalated",
            all(r.classification != :accepted for r in ranks if r.device_kind != :generator) &&
            all(d.action == :exact for d in comparison.decisions if d.device_kind != :generator))
    elseif kind == :reactive
        ("Both generator outages unresolved",
            all(r.classification != :accepted for r in ranks if r.device_kind == :generator))
    else
        ("Disabled guard causes two detected false screens",
            sum(r.screened_unresolved for r in comparison.families) == 2)
    end
    push!(expectation_rows, "| $kind | $expected | $(matches ? "PASS" : "FAIL") |")
    directory = joinpath(output,"qualification-$kind")
    mkpath(directory)
    DroopOPF._write_scopf_json(joinpath(directory,"comparison.json"),
        "DroopOPF.FilterQualification", comparison)
    write_contingency_pipeline(joinpath(directory,"pipeline.json"), comparison.exact)
    write(joinpath(directory,"pipeline.md"), markdown_report(comparison.exact))
    budget_rows = Vector{Any}[]
    for family in comparison.families
        push!(summary, "| $kind | $(family.device_kind) | $(family.total) | $(family.screened) | $(family.unresolved) | $(family.screened_unresolved) | $(family.screened_physical_failures) |")
        for b in family.ranking_budgets
            push!(budget_rows, Any[string(family.device_kind), b.budget, b.found, b.total,
                b.total == 0 ? "N/A" : string(round(b.found/b.total; digits=3))])
        end
    end
    DroopOPF._scopf_svg_table(joinpath(directory,"ranking-budget.svg"),
        "Evaluation order vs exhaustive AC — $kind",
        "Mandatory routes first, then predicted loading. Recall concerns unresolved outcomes, not proven physical infeasibility.",
        ["Device", "AC budget", "Unresolved found", "Unresolved total", "Recall"],
        budget_rows; cell_widths=[160,150,180,180,400])
    # Save complete fixed-base result evaluations for independent replay.
    for assessment in comparison.exact.assessments
        exact = assessment.exact_assessment
        isnothing(exact) && continue
        declared = Study(small; contingencies=[assessment.entry.contingency],
            participation=Dict(1=>1.0,2=>1.0))
        write_scopf_evaluation_report(joinpath(directory,string(assessment.entry.contingency.id),"evaluation.md"),
            declared, exact.result; context="Fixed-base exhaustive AC reference for $kind; independent outcome: $(assessment.rank.classification). Base chosen with AVR voltage targets (1.009 pu for the voltage fixture, including the disabled-guard run; 1.0 otherwise); post-outage Q is free within declared bounds.")
    end
end
push!(summary, "", "## Expected behavior versus observed outcomes", "",
    "PASS below means the experiment matched its expectation, not that the operating point was secure.", "",
    "| Input | Expected behavior | Experiment check |", "|---|---|---|")
append!(summary, expectation_rows)
push!(summary, "", "## Per-case ranking and validation details", "")
for kind in (:benign, :thermal, :voltage, :reactive, :transformer, :voltage_guard_disabled)
    push!(summary, "- [$kind pipeline](qualification-$kind/pipeline.md); [evaluation-budget plot](qualification-$kind/ranking-budget.svg). Outage-specific input/output bundles are in that directory.")
end
push!(summary, "", "The voltage_guard_disabled run is a deliberate unsafe-policy control: its false screens demonstrate why the guard is required. Zero observed misses in the guarded fixtures is not a general screening certificate.")
islands = scopf_loaded_island_case()
island_base = solve_opf(islands)
island_campaign = run_contingency_campaign(joinpath(output,"islands"),islands,island_base.state)
replay = run_contingency_campaign(joinpath(output,"islands"),islands,island_base.state)
island_rows = Vector{Any}[]
for assessment in island_campaign.result.assessments
    a = assessment.island_assessment
    isnothing(a) && continue
    s = a.selection
    push!(island_rows, Any[string(assessment.entry.contingency.id),
        join(s.retained_bus_ids,","), s.selected_reference_bus_id,
        s.discarded_load_p, string(a.report.valid), string(assessment.rank.classification)])
end
DroopOPF._scopf_svg_table(joinpath(output,"islands","island-validation.svg"),
    "Island policy and retained-component validation",
    "Discarded components are not balanced. Retained island uses free OPF redispatch, not connected preventive participation.",
    ["Outage", "Retained buses", "Reference bus", "Excluded P (pu)", "Retained valid", "Classification"],
    island_rows; cell_widths=[150,170,150,180,180,380])
push!(summary, "", "## Island policy and campaign replay", "",
    "[Island campaign](islands/campaign.md). Reused $(replay.resumed_count) checkpoints; executed $(replay.evaluated_count) routes on replay.", "",
    "![Island validation](islands/island-validation.svg)", "",
    "Largest-component selection, lost-load accounting, and largest-generator reference reassignment are checked separately from retained-component electrical feasibility. See campaign-inputs.json for full inputs, source fingerprint and numerical settings.", "")
write(joinpath(output,"evaluation.md"),join(summary,"\n"))
println("Consolidated validation evidence: $(joinpath(output,"evaluation.md"))")
