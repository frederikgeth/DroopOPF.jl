using DroopOPF
using MadNLP

function comparison_case()
    network = ACNetwork(
        [Bus(1; reference = true), Bus(2)],
        [Branch(1, 1, 2; resistance = 0.01, reactance = 0.1, thermal_limit = 5.0)],
    )
    generators = [
        Generator(i, 1; p_min = 0.0, p_max = 1.0, q_min = -1.0, q_max = 1.0,
                  initial_p = 0.2, initial_q = 0.0)
        for i in 1:3
    ]
    controls = [
        VoltVarDroop(
            VoltageSchedule(1.0; v_db_low = 0.9, v_db_high = 1.1),
            0.05,
            0.0,
            ReactiveCapability(p_min = 0.0, p_max = 1.0, q_min = -1.0, q_max = 1.0),
        ),
        VoltVarDroop(
            VoltageSchedule(1.0; v_db_low = 0.99, v_db_high = 1.01),
            0.05,
            0.0,
            ReactiveCapability(p_min = 0.0, p_max = 1.0, q_min = -1.0, q_max = 1.0),
        ),
        VoltVarDroop(
            VoltageSchedule(1.0; v_db_low = 0.99, v_db_high = 1.01),
            0.05,
            0.0,
            ReactiveCapability(p_min = 0.0, p_max = 1.0, q_min = -0.1, q_max = 0.1),
        ),
    ]
    return Case(
        "m1-solver-comparison";
        base_power = 100.0,
        base_frequency = 50.0,
        network = network,
        loads = [Load(1, 2; p = 0.5, q = 0.2)],
        generators = generators,
        controls = controls,
        attachments = [GeneratorControlAttachment(i, i, RegulatedLocation(:bus, 1)) for i in 1:3],
    )
end

case = comparison_case()
results = Dict{Symbol,Any}(
    :ipopt => solve_opf(case; smooth_epsilon = 1.0e-3, silent = true),
    :madnlp => solve_opf(
        case;
        smooth_epsilon = 1.0e-3,
        optimizer_factory = MadNLP.Optimizer,
        silent = true,
    ),
    :ccopt => solve_opf_complementarity(case; silent = true),
)

function maximum_residual(case, result)
    residual = equilibrium_residual(case, result.state)
    return maximum(abs, residual.power.vector), maximum(abs, residual.droop)
end

println("# M1 solver comparison")
println()
println("| Solver | Status | Objective | AC residual | Droop residual | CC residual | Valid |")
println("|---|---|---:|---:|---:|---:|---|")
for solver in (:ipopt, :madnlp, :ccopt)
    result = results[solver]
    power_residual, droop_residual_value = maximum_residual(case, result)
    cc_residual = result isa ComplementarityOPFResult ? result.complementarity_residual_max : NaN
    report = equilibrium_report(case, result; droop_tolerance = 5.0e-3)
    println(
        "| $(solver) | $(result.termination_status) | $(result.objective) | ",
        "$(power_residual) | $(droop_residual_value) | $(cc_residual) | $(report.valid) |",
    )
end
println()
println("## Operating points")
println()
println("| Solver | Generator | Regime | V (pu) | Q (pu) | Exact curve Q (pu) | Error |")
println("|---|---:|---|---:|---:|---:|---:|")
for solver in (:ipopt, :madnlp, :ccopt)
    result = results[solver]
    for point in droop_operating_points(case, result.state)
        curve_q = droop_response(
            case.controls[point.control_id],
            point.voltage;
            p = result.state.pg[point.generator_id],
        )
        println(
            "| $(solver) | $(point.generator_id) | $(point.regime) | ",
            "$(point.voltage) | $(point.reactive_power) | $(curve_q) | ",
            "$(point.reactive_power - curve_q) |",
        )
    end
end

output_path = isempty(ARGS) ?
    joinpath(dirname(@__DIR__), "m1_solver_comparison.svg") : ARGS[1]
write_solver_comparison_plot(
    output_path,
    case,
    results;
    title = "M1 Ipopt / MadNLP / CCOpt comparison",
)
println()
println("Comparison plot written to: $output_path")
