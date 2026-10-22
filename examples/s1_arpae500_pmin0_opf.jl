# S1 AC OPF for the derived 500-bus case with all generator Pmin values set to zero.
# Requires PowerModelsSecurityConstrained, PowerModels, Ipopt, JuMP, and JSON in
# the active Julia environment; these remain separate from DroopOPF's deps.
using PowerModelsSecurityConstrained, PowerModels, Ipopt, JuMP, JSON

const CASE_DIR = joinpath(@__DIR__, "..", "test", "data", "arpae", "c1_network01")
const OUT_DIR = joinpath(CASE_DIR, "results", "scenario_02_pmin0")

function run_s1_arpae500_pmin0_opf()
    mkpath(OUT_DIR)
    data = parse_c1_case(joinpath(CASE_DIR, "inputfiles.ini"), scenario_id="scenario_02_pmin0")
    network = build_c1_pm_model(data)
    all(gen["pmin"] == 0.0 for gen in values(network["gen"])) ||
        error("expected Pmin=0 for all generator records")
    solver = optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0)
    result = solve_opf(network, ACPPowerModel, solver)
    result["termination_status"] == LOCALLY_SOLVED ||
        error("AC OPF status: $(result[\"termination_status\"])")
    open(joinpath(OUT_DIR, "network_model.json"), "w") do io
        JSON.print(io, network, 2)
    end
    open(joinpath(OUT_DIR, "opf_ac.json"), "w") do io
        JSON.print(io, result, 2)
    end
    println("Pmin-zero AC OPF: ", result["termination_status"],
        ", objective = ", result["objective"])
    return result
end

abspath(PROGRAM_FILE) == @__FILE__ && run_s1_arpae500_pmin0_opf()
