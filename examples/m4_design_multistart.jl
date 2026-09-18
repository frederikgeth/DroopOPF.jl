using DroopOPF

include("m2_case.jl")

output_directory = isempty(ARGS) ? mktempdir(prefix="droopopf-m4-design-") : abspath(first(ARGS))
mkpath(output_directory)

case = m2_case()
study = Study(case; contingencies=[
    Contingency(:line_22; branch_ids=[22]),
    Contingency(:generator_9; generator_ids=[9]),
], participation=Dict(7=>1.0, 9=>1.0))
reference = solve_scopf(study; smooth_epsilon=1e-5)
equilibrium_report(study, reference).valid || error("M2 reference did not validate")

starts = Dict(
    :lower_corner => DroopSettings(0.045, 0.996, 0.006, 0.006),
    :reference => DroopSettings(case.controls[2]),
    :upper_corner => DroopSettings(0.095, 1.004, 0.014, 0.014),
)
comparison = optimize_droop_multistart(study, 2, starts;
    slope_bounds=(0.04, 0.10),
    v_ref_bounds=(0.995, 1.005),
    deadband_low_bounds=(0.005, 0.015),
    deadband_high_bounds=(0.005, 0.015),
    smooth_epsilon=1e-5,
    reference_result=reference)

write_droop_design_multistart(
    joinpath(output_directory, "design_multistart.json"), comparison)
write(joinpath(output_directory, "design_multistart.md"), markdown_report(comparison) * "\n")

println("Design multi-start classification: ", comparison.classification)
println("Objective spread: ", comparison.objective_spread)
println("Parameter spread: ", comparison.parameter_spread)
println("Artifacts: ", output_directory)
