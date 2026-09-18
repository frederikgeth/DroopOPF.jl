using DroopOPF
include("m2_case.jl")

case = m2_case()
study = Study(case;
    contingencies=[Contingency(:line_22; branch_ids=[22]),
                   Contingency(:generator_9; generator_ids=[9])],
    participation=Dict(7=>1.0,9=>1.0))
result = solve(study; smooth_epsilon=1e-5)
report = equilibrium_report(study,result)
report.valid || error(markdown_report(report))
output = isempty(ARGS) ? mktempdir(prefix="droopopf-m2-") : abspath(ARGS[1])
mkpath(output)
write_study(joinpath(output,"study.json"),study)
write_scopf_result(joinpath(output,"result.json"),result)
write_scopf_report(joinpath(output,"report.json"),report)
write(joinpath(output,"report.md"),markdown_report(report) * "\n")
plots = write_scopf_validation_plots(output, study, result)
restored = read_study(joinpath(output,"study.json"))
restored_result = read_scopf_result(joinpath(output,"result.json"))
@assert equilibrium_report(restored,restored_result).valid
corrupted = deepcopy(restored_result)
corrupted.states[:generator_9].qg[2] = 0.1
invalid = equilibrium_report(restored,corrupted)
@assert !invalid.valid
@assert :unavailable_generator in invalid.violations[:generator_9]
println(markdown_report(report))
println("\nJSON round-trip validated; deliberate outage corruption rejected.")
println("Visual validation:")
for path in plots
    println("  $path")
end
println("Artifacts: $output")
