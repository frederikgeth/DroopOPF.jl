# Reproduce the ARPA-E GOC Challenge 1 Network Model 01 Scenario 02 OPF and
# upstream PowerModelsSecurityConstrained.jl fixed-point AC SCOPF results.
# Requires PowerModelsSecurityConstrained, PowerModels, Ipopt, JuMP, and JSON
# in the active Julia environment; these are intentionally not DroopOPF deps.
using PowerModelsSecurityConstrained, PowerModels, Ipopt, JuMP, JSON

const DATA_DIR = joinpath(@__DIR__, "..", "test", "data", "arpae", "c1_network01")
const RESULTS_DIR = joinpath(DATA_DIR, "results")

function save_json(path, value)
    open(path, "w") do io
        JSON.print(io, value, 2)
    end
    println("wrote ", path)
end

function run_s1_arpae500_reference()
    mkpath(RESULTS_DIR)
    data = parse_c1_case(joinpath(DATA_DIR, "inputfiles.ini"), scenario_id="scenario_02")
    network = build_c1_pm_model(data)
    solver = optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0)

    # Standard PowerModels AC OPF: source cost model, fixed transformer taps and
    # fixed shunts. This is the same AC OPF assertion used by upstream test/opf.jl.
    opf = solve_opf(network, ACPPowerModel, solver)
    opf["termination_status"] == LOCALLY_SOLVED || error("AC OPF status: $(opf[\"termination_status\"])")
    save_json(joinpath(RESULTS_DIR, "opf_ac.json"), opf)

    # Upstream iterative AC contingency-cut SCOPF, with the source .con/.inl
    # contingency and generator response rules. Equipment settings stay fixed.
    scopf = run_c1_scopf_contigency_cuts(network, ACPPowerModel, solver)
    scopf["termination_status"] == LOCALLY_SOLVED || error("AC SCOPF status: $(scopf[\"termination_status\"])")
    save_json(joinpath(RESULTS_DIR, "scopf_ac.json"), scopf)

    # The upstream fixed-point wrapper returns its base operating point only.
    # Re-solve the exact final master to retain the contingency operating states.
    # These are the four contingencies in the converged Scenario 02 fixed point.
    gen_labels = Set(["G_000017SENECA33U1"])
    branch_labels = Set([
        "T_000247BLACKSBURG11-000246BLACKSBURG10C1",
        "L_000162IRMO0-000220UNION30C1",
        "L_000246BLACKSBURG10-000332CONVERSE0C1",
    ])
    network["gen_contingencies"] = [c for c in network["gen_contingencies"] if c.label in gen_labels]
    network["branch_contingencies"] = [c for c in network["branch_contingencies"] if c.label in branch_labels]
    length(network["gen_contingencies"]) == length(gen_labels) || error("upstream generator contingency set changed")
    length(network["branch_contingencies"]) == length(branch_labels) || error("upstream branch contingency set changed")
    final_master = build_c1_scopf_multinetwork(network)
    scopf_states = run_c1_scopf(final_master, ACPPowerModel, solver)
    isapprox(scopf_states["objective"], scopf["objective"]; atol=1e-3) || error("final-master objective does not match fixed-point result")
    save_json(joinpath(RESULTS_DIR, "scopf_ac_all_states.json"), scopf_states)
    save_json(joinpath(RESULTS_DIR, "network_model.json"), build_c1_pm_model(data))
    return (opf=opf, scopf=scopf, scopf_states=scopf_states)
end

abspath(PROGRAM_FILE) == @__FILE__ && run_s1_arpae500_reference()
