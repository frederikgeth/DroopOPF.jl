using DroopOPF

case_path = joinpath(dirname(@__DIR__), "test", "data", "droop2.m")
case = load_matpower_case(case_path)

control = VoltVarDroop(
    VoltageSchedule(1.0; v_db_low = 0.99, v_db_high = 1.01),
    0.05,
    0.0,
    ReactiveCapability(p_min = 0.0, p_max = 2.0, q_min = -1.0, q_max = 1.0),
)
case = attach_controls(
    case,
    [control],
    [GeneratorControlAttachment(1, 1, RegulatedLocation(:bus, 1))],
)

continuation = solve_opf_continuation(case; silent = true)
result = last(continuation.results)
report = equilibrium_report(case, result; droop_tolerance = 5.0e-3)
println(markdown_report(report))
