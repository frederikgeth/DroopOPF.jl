# Reproduce AC OPF and fixed-equipment AC SCOPF for the Pmin-zero,
# symmetric-Q study variants of ARPA-E Challenge 1 Network Model 01.
# Run only after confirming the SCOPF equipment-control setup.
using PowerModelsSecurityConstrained, PowerModels, Ipopt, JuMP, JSON

const DATA_DIR = joinpath(@__DIR__, "..", "test", "data", "arpae", "c1_network01")
const RESULTS_DIR = joinpath(DATA_DIR, "results")
const SOLVER = optimizer_with_attributes(Ipopt.Optimizer, "tol" => 1e-6, "print_level" => 0)

function save_json(path, value)
    open(path, "w") do io
        JSON.print(io, value, 2)
    end
end

function check_study_limits(network, scenario)
    for (id, gen) in network["gen"]
        gen["pmin"] == 0.0 || error("$scenario generator $id has Pmin=$(gen["pmin"]), expected 0")
        isapprox(gen["qmin"], -gen["qmax"]; atol=1e-9, rtol=1e-9) ||
            error("$scenario generator $id has asymmetric Q limits $(gen["qmin"]), $(gen["qmax"])")
    end
end

function solve_study_case(scenario; full_source_contingencies=false)
    outdir = joinpath(RESULTS_DIR, scenario)
    mkpath(outdir)
    data = parse_c1_case(joinpath(DATA_DIR, "inputfiles.ini"), scenario_id=scenario)
    network = build_c1_pm_model(data)
    check_study_limits(network, scenario)

    opf = solve_opf(deepcopy(network), ACPPowerModel, SOLVER)
    opf["termination_status"] == LOCALLY_SOLVED || error("$scenario OPF: $(opf["termination_status"])")
    save_json(joinpath(outdir, "opf_ac.json"), opf)

    scopf = run_c1_scopf_contigency_cuts(deepcopy(network), ACPPowerModel, SOLVER)
    scopf["termination_status"] == LOCALLY_SOLVED || error("$scenario SCOPF: $(scopf["termination_status"])")
    save_json(joinpath(outdir, "scopf_ac.json"), scopf)

    state_network = deepcopy(network)
    if !full_source_contingencies
        gen_labels = Set(["G_000017SENECA33U1"])
        branch_labels = Set([
            "T_000247BLACKSBURG11-000246BLACKSBURG10C1",
            "L_000162IRMO0-000220UNION30C1",
            "L_000246BLACKSBURG10-000332CONVERSE0C1",
        ])
        state_network["gen_contingencies"] = [c for c in state_network["gen_contingencies"] if c.label in gen_labels]
        state_network["branch_contingencies"] = [c for c in state_network["branch_contingencies"] if c.label in branch_labels]
        length(state_network["gen_contingencies"]) == length(gen_labels) || error("$scenario generator contingency set changed")
        length(state_network["branch_contingencies"]) == length(branch_labels) || error("$scenario branch contingency set changed")
    end
    all_states = run_c1_scopf(build_c1_scopf_multinetwork(state_network), ACPPowerModel, SOLVER)
    all_states["termination_status"] == LOCALLY_SOLVED || error("$scenario all-state SCOPF: $(all_states["termination_status"])")
    isapprox(all_states["objective"], scopf["objective"]; atol=1e-3) ||
        error("$scenario all-state objective differs from fixed-point SCOPF")
    save_json(joinpath(outdir, "scopf_ac_all_states.json"), all_states)
    save_json(joinpath(outdir, "network_model.json"), network)
    println(scenario, ": OPF=", opf["objective"], ", SCOPF=", scopf["objective"],
        ", all-state=", all_states["objective"])
    return (network=network, opf=opf, scopf=scopf, all_states=all_states)
end

function run_s1_s2_arpae_pmin0_qsym()
    ieee14 = solve_study_case("scenario_01_pmin0_qsym"; full_source_contingencies=true)
    ieee500 = solve_study_case("scenario_02_pmin0_qsym")
    return (ieee14=ieee14, ieee500=ieee500)
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && run_s1_s2_arpae_pmin0_qsym()
