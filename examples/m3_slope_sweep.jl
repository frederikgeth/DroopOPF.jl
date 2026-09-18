using DroopOPF
using Printf
include("m2_case.jl")

case = m2_case()
study = Study(
    case;
    contingencies = [
        Contingency(:line_22; branch_ids = [22]),
        Contingency(:generator_9; generator_ids = [9]),
    ],
    participation = Dict(7 => 1.0, 9 => 1.0),
)
slopes = collect(0.04:0.005:0.10)
sweep = sweep_droop_slope(
    study,
    2,
    slopes;
    reference_slope = 0.075,
    smooth_epsilon = 1e-5,
)
best = best_droop_slope(sweep)
output = isempty(ARGS) ? mktempdir(prefix = "droopopf-m3-sweep-") : abspath(ARGS[1])
mkpath(output)
json_path = write_droop_slope_sweep(joinpath(output, "m3_slope_sweep.json"), sweep)
plot_path = write_droop_slope_sweep_plot(joinpath(output, "m3_slope_tradeoff.svg"), sweep)

println("| G9 slope | Valid | Objective | Worst |V-1| | Maximum branch loading (%) |")
println("|---:|---|---:|---:|---:|")
for point in sweep.points
    @printf(
        "| %.3f | %s | %.8g | %.8g | %.8g |\n",
        point.slope,
        point.valid,
        point.objective,
        point.max_voltage_deviation,
        point.max_branch_loading_percent,
    )
end
println("\nBest valid dispatch objective: slope=$(best.slope), objective=$(best.objective)")
println("JSON: $json_path")
println("Plot: $plot_path")
