using DroopOPF
include("m2_case.jl")

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
    plot_paths=invalid_plots)

println("Accepted and deliberately invalid SCOPF evaluation bundles: $output")
