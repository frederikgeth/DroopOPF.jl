using DroopOPF
case = load_matpower_case(joinpath(@__DIR__, "..", "test", "data", "droop2.m"))
result = solve_opf(case)
check = validate_equilibrium(case, result)
check.valid || error("independent equilibrium validation failed")
println("Synthetic two-bus OPF and independent validation passed")
