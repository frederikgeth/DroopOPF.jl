using DroopOPF

network = ACNetwork(
    [Bus(1; reference = true), Bus(2)],
    [Branch(1, 1, 2; resistance = 0.01, reactance = 0.1, thermal_limit = 5.0)],
)
generators = [
    Generator(i, 1; p_min = 0.0, p_max = 1.0, q_min = -1.0, q_max = 1.0,
              initial_p = 0.2, initial_q = 0.0)
    for i in 1:3
]
load = Load(1, 2; p = 0.5, q = 0.2)
controls = [
    # Wide deadband: the solved point remains inside the deadband.
    VoltVarDroop(
        VoltageSchedule(1.0; v_db_low = 0.9, v_db_high = 1.1),
        0.05,
        0.0,
        ReactiveCapability(p_min = 0.0, p_max = 1.0, q_min = -1.0, q_max = 1.0),
    ),
    # Tight deadband: the solved point lies on the proportional segment.
    VoltVarDroop(
        VoltageSchedule(1.0; v_db_low = 0.99, v_db_high = 1.01),
        0.05,
        0.0,
        ReactiveCapability(p_min = 0.0, p_max = 1.0, q_min = -1.0, q_max = 1.0),
    ),
    # Small Q range: the same voltage reaches the capacitive saturation limit.
    VoltVarDroop(
        VoltageSchedule(1.0; v_db_low = 0.99, v_db_high = 1.01),
        0.05,
        0.0,
        ReactiveCapability(p_min = 0.0, p_max = 1.0, q_min = -0.1, q_max = 0.1),
    ),
]
attachments = [
    GeneratorControlAttachment(i, i, RegulatedLocation(:bus, 1))
    for i in 1:3
]
case = Case(
    "m1-regime-case-study";
    base_power = 100.0,
    base_frequency = 50.0,
    network = network,
    loads = [load],
    generators = generators,
    controls = controls,
    attachments = attachments,
)

result = solve_opf(case; smooth_epsilon = 1.0e-3, silent = true)
result.state === nothing && error("case study did not produce a state")
report = equilibrium_report(case, result; droop_tolerance = 5.0e-3)
points = droop_operating_points(case, result.state)
output_path = isempty(ARGS) ?
    joinpath(dirname(@__DIR__), "m1_regime_case_study.svg") : ARGS[1]
write_droop_plot(output_path, case, result.state; title = "M1 volt-var regime case study")

println(markdown_report(report))
println()
println("Operating points:")
for point in points
    generator = case.generators[point.generator_id]
    control = case.controls[point.control_id]
    curve_q = clamp(
        droop_response(control, point.voltage; p = result.state.pg[point.generator_id]),
        generator.q_min,
        generator.q_max,
    )
    println(
        "  generator=$(point.generator_id) control=$(point.control_id) ",
        "V=$(point.voltage) Q=$(point.reactive_power) ",
        "Q_curve=$(curve_q) Q_error=$(point.reactive_power - curve_q) ",
        "regime=$(point.regime)",
    )
end
println("Plot written to: $output_path")
