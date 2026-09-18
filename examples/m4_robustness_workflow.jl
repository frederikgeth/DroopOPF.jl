using DroopOPF

include("m2_case.jl")

output_directory = isempty(ARGS) ? get(ENV, "DROOPOPF_OUTPUT_DIR",
    joinpath(@__DIR__, "..", "artifacts", "m4_robustness")) : first(ARGS)
mkpath(output_directory)

case = m2_case()
study = Study(case; contingencies=[
    Contingency(:line_22; branch_ids=[22]),
    Contingency(:generator_9; generator_ids=[9]),
], participation=Dict(7=>1.0, 9=>1.0))

# Use one converged point only to construct deliberately different initial
# guesses. Every named start below is solved and validated independently.
reference = solve_scopf(study; smooth_epsilon=1e-5)
function shifted_states(result, voltage_shift)
    return Dict(id => ACState(state.vm .+ voltage_shift, state.va, state.pg, state.qg)
        for (id, state) in result.states)
end

starts = Dict{Symbol,Any}(
    :cold => Dict{Symbol,ACState{Float64}}(),
    :reference => reference.states,
    :voltage_low => shifted_states(reference, -0.005),
    :voltage_high => shifted_states(reference, 0.005),
)
comparison = solve_scopf_multistart(study, starts;
    smooth_epsilon=1e-5, objective_atol=1e-8, objective_rtol=1e-6)

best = only(run.result for run in comparison.runs if run.label == comparison.best_run)
diagnostics = scopf_diagnostics(study, best;
    breakpoint_tolerance=0.005, binding_tolerance=1e-4)

write_scopf_multistart(joinpath(output_directory, "multistart.json"), comparison)
write(joinpath(output_directory, "multistart.md"), markdown_report(comparison) * "\n")
write_scopf_diagnostics(joinpath(output_directory, "diagnostics.json"), diagnostics)
write(joinpath(output_directory, "diagnostics.md"), markdown_report(diagnostics) * "\n")

println("Multi-start classification: ", comparison.classification)
println("Objective spread: ", comparison.objective_spread)
println("Critical scenario: ", diagnostics.critical_scenario)
println("Artifacts: ", abspath(output_directory))
