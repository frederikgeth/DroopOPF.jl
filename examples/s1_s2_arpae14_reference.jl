# Reproduce the upstream ARPA-E GOC Challenge 1 Network Model 01 Scenario 01
# AC OPF and AC contingency-cut SCOPF reference, plus the S1 Pmin=0 variant.
# Equipment controls remain fixed at source-case values, matching the upstream
# PMSC benchmark assumptions used for the 500-bus reference.
# Requires PowerModelsSecurityConstrained, PowerModels, Ipopt, JuMP, and JSON.
using PowerModelsSecurityConstrained, PowerModels, Ipopt, JuMP, JSON

const DATA_DIR = joinpath(@__DIR__, "..", "test", "data", "arpae", "c1_network01")
const RESULTS_DIR = joinpath(DATA_DIR, "results")

function save_json(path, value)
    open(path, "w") do io
        JSON.print(io, value, 2)
    end
    println("wrote ", path)
end

function run_scenario(scenario_id)
    outdir = joinpath(RESULTS_DIR, scenario_id)
    mkpath(outdir)
    data = parse_c1_case(joinpath(DATA_DIR, "inputfiles.ini"), scenario_id=scenario_id)
    network = build_c1_pm_model(data)
    solver = optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0)

    opf = solve_opf(deepcopy(network), ACPPowerModel, solver)
    opf["termination_status"] == LOCALLY_SOLVED ||
        error("$scenario_id AC OPF status: $(opf["termination_status"])")
    save_json(joinpath(outdir, "opf_ac.json"), opf)

    # Upstream iterative AC contingency-cut SCOPF. Transformer taps and shunt
    # settings are not optimization controls in this reference solve.
    scopf = run_c1_scopf_contigency_cuts(deepcopy(network), ACPPowerModel, solver)
    scopf["termination_status"] == LOCALLY_SOLVED ||
        error("$scenario_id AC SCOPF status: $(scopf["termination_status"])")
    save_json(joinpath(outdir, "scopf_ac.json"), scopf)

    # Retain the full operating states for the two declared contingencies as
    # an audit artifact. The fixed-point reference above remains authoritative;
    # this all-contingency master should reproduce its objective when secure.
    all_states = run_c1_scopf(build_c1_scopf_multinetwork(deepcopy(network)), ACPPowerModel, solver)
    all_states["termination_status"] == LOCALLY_SOLVED ||
        error("$scenario_id all-contingency SCOPF status: $(all_states["termination_status"])")
    save_json(joinpath(outdir, "scopf_ac_all_states.json"), all_states)
    save_json(joinpath(outdir, "network_model.json"), network)
    println(scenario_id, ": OPF objective = ", opf["objective"],
        "; SCOPF objective = ", scopf["objective"],
        "; SCOPF iterations = ", scopf["iterations"],
        "; all-contingency objective = ", all_states["objective"])
    return (network=network, opf=opf, scopf=scopf, all_states=all_states)
end

function run_s1_s2_arpae14_reference()
    mkpath(RESULTS_DIR)
    source = run_scenario("scenario_01")
    s1_pmin0 = run_scenario("scenario_01_pmin0")
    return (source=source, s1_pmin0=s1_pmin0)
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    run_s1_s2_arpae14_reference()
end
