using DroopOPF
using Printf
include("m2_case.jl")

case = m2_case()
training = Study(
    case;
    contingencies = [
        Contingency(:line_22; branch_ids = [22]),
        Contingency(:generator_9; generator_ids = [9]),
    ],
    participation = Dict(7 => 1.0, 9 => 1.0),
)
reference = solve_scopf(training; smooth_epsilon = 1e-5)
equilibrium_report(training, reference).valid || error("M2 reference did not validate")

design = optimize_droop_parameters(
    training,
    2;
    slope_bounds = (0.04, 0.10),
    v_ref_bounds = (0.995, 1.005),
    deadband_low_bounds = (0.005, 0.015),
    deadband_high_bounds = (0.005, 0.015),
    smooth_epsilon = 1e-5,
    reference_result = reference,
)
optimized_training = with_droop_settings(training, design)
training_report = validate_droop_design(training, design)
training_report.valid || error("optimized training design did not validate")

held_out = evaluate_held_out_contingencies(
    training,
    design,
    [Contingency(:line_33; branch_ids = [33])],
)
held_out.report.valid || error("optimized design failed held-out validation")

output = isempty(ARGS) ? mktempdir(prefix = "droopopf-m3-") : abspath(ARGS[1])
mkpath(output)
held_out_output = joinpath(output, "held_out")
mkpath(held_out_output)

write_droop_design(joinpath(output, "design.json"), design)
write_study(joinpath(output, "training_study.json"), optimized_training)
write_scopf_result(joinpath(output, "training_result.json"), design.result)
write_scopf_report(joinpath(output, "training_report.json"), training_report)
write_study(joinpath(held_out_output, "study.json"), held_out.study)
write_scopf_result(joinpath(held_out_output, "result.json"), held_out.result)
write_scopf_report(joinpath(held_out_output, "report.json"), held_out.report)
write_droop_design_comparison_plot(
    joinpath(output, "m3_droop_design_comparison.svg"),
    training,
    design;
    held_out_study = held_out.study,
    held_out_result = held_out.result,
)
write_scopf_validation_plots(held_out_output, held_out.study, held_out.result)

improvement = design.reference_objective - design.result.objective
summary = """
# M3 droop-design validation

- Training valid: `$(training_report.valid)`
- Held-out line-33 valid: `$(held_out.report.valid)`
- Reference objective: $(design.reference_objective)
- Optimized objective: $(design.result.objective)
- Objective improvement: $improvement
- G9 slope: $(design.settings.slope)
- G9 voltage reference: $(design.settings.v_ref)
- G9 lower deadband width: $(design.settings.deadband_low)
- G9 upper deadband width: $(design.settings.deadband_high)

The optimized settings are shared across the base case and all training
contingencies. Both training and held-out states are independently replayed
against the reconstructed exact piecewise-linear droop curve.
"""
write(joinpath(output, "summary.md"), summary)

@printf("Reference objective: %.10g\n", design.reference_objective)
@printf("Optimized objective: %.10g\n", design.result.objective)
@printf("Objective improvement: %.10g\n", improvement)
println("Optimized settings: $(design.settings)")
println("Training validation: $(training_report.valid)")
println("Held-out validation: $(held_out.report.valid)")
println("Artifacts: $output")
