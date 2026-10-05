include("s1_policy_matrix.jl")

"""Continuous scaling of existing reactive shunts; selection is an explicit
benchmark assumption, not a claim that the source equipment is switchable.
Pure conductances and unavailable devices remain fixed. The bank endpoints
encode the continuous envelope only; no discrete switching claim is made.
"""
function s1_existing_shunt_overlay(original, anchor, source)
    overlay, policies, metadata = s1_public_overlay(original, anchor, source; bank_count=0)
    net = overlay.network
    selected = [s for s in net.shunts if s.available && !iszero(s.susceptance)]
    ids = Set(s.id for s in selected)
    banks = [ShuntBank(s.id, s.bus_id; step_conductances=(s.conductance,),
        step_susceptances=(s.susceptance,), legal_states=[(0,), (1,)],
        state=(1,), nominal_state=(1,)) for s in selected]
    case = Case(overlay.id * "-existing-shunts"; base_power=overlay.base_power,
        base_frequency=overlay.base_frequency, network=ACNetwork(net.buses, net.branches;
            shunts=[s for s in net.shunts if !(s.id in ids)], banks),
        loads=overlay.loads, generators=overlay.generators,
        controls=overlay.controls, attachments=overlay.attachments)
    controls = [ShuntControl(s.id; lower=min(0., s.susceptance),
        upper=max(0., s.susceptance), initial=s.susceptance, nominal=s.susceptance)
        for s in selected]
    metadata["kind"] = "existing shunt continuous-envelope assumption"
    metadata["bank_count"] = length(banks)
    metadata["bank_rule"] = "replace all available nonzero-B fixed shunts; G(alpha)=alpha*G0 and B(alpha)=alpha*B0, 0<=alpha<=1, initially alpha=1"
    metadata["unchanged"] = "source network, generator limits, initial total admittance; droop and tap policies match previous overlay"
    metadata["discrete_switching_evaluated"] = false
    metadata["devices"] = [Dict("id"=>s.id, "bus"=>s.bus_id,
        "G0"=>s.conductance, "B0"=>s.susceptance,
        "selection_basis"=>"assumed adjustable for benchmark; hardware capability unverified") for s in selected]
    # Check both nominal admittance and intermediate physical G/B replay.
    nominal_error = maximum(abs.(DroopOPF._admittance_matrix(original.network) -
        DroopOPF._admittance_matrix(case.network)))
    nominal_error <= 1e-12 || error("conversion changed nominal admittance")
    for alpha in (0., .37, 1.)
        replay = with_shunt_settings(case, Dict(s.id=>alpha*s.susceptance for s in selected))
        expected = copy(DroopOPF._admittance_matrix(original.network))
        indices = Dict(b.id=>i for (i,b) in enumerate(net.buses))
        for s in selected
            i = indices[s.bus_id]
            expected[i,i] += (alpha-1)*(s.conductance + im*s.susceptance)
        end
        maximum(abs.(expected-DroopOPF._admittance_matrix(replay.network))) <= 1e-12 ||
            error("continuous admittance replay mismatch")
    end
    check = validate_equilibrium(case, anchor.opf.state)
    check.valid || error("converted nominal anchor does not validate")
    metadata["nominal_admittance_max_error"] = nominal_error
    metadata["nominal_anchor_valid"] = check.valid
    return case, merge(policies, (shunt_controls=controls,)), metadata
end

"""Nominal qualification: fixed versus existing-shunt control for each solver.
All droop settings and transformer ratios remain at their supplied values.
"""
function s1_existing_shunt_pilot(out)
    mkpath(out)
    rows = Dict{String,Any}[]
    for n in (118,300)
        source = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07", "pglib_opf_case$(n)_ieee.m")
        original = load_matpower_case(source; base_frequency=60.)
        anchor = read_joint_design(joinpath(@__DIR__, "..", "artifacts", "s1_public_controls", "public$n-baseline-design.json"))
        case, policies, metadata = s1_existing_shunt_overlay(original, anchor, source)
        write(joinpath(out, "public$n-overlay.json"), JSON.json(metadata; pretty=true))
        write_study(joinpath(out, "public$n-study.json"), Study(case))
        for solver in (:ipopt,:madnlp), family in (:fixed,:shunt)
            name = "public$n-$solver-$family-existing"
            row, _ = s1_run_policy(out,name,case,anchor.opf.state; solver,
                policies=(tap_controls=TapControl[], droop_controls=DroopControl[],
                    shunt_controls=family==:shunt ? policies.shunt_controls : ShuntControl[]),
                tags=Dict("family"=>string(family), "network"=>n,
                    "start"=>"anchor", "load_factor"=>1., "study"=>"existing_shunt_nominal_qualification"))
            push!(rows,row)
            write(joinpath(out,"summary.json"), JSON.json(rows;pretty=true))
        end
    end
    open(joinpath(out,"report.md"),"w") do io
        println(io,"# Existing shunts: continuous nominal qualification\n")
        println(io,"Existing nonzero-B available shunts are replaced by continuous alpha-scaled G/B devices, initially alpha=1 and bounded by 0 and 1. Selection is an explicit benchmark assumption. No new compensation capacity is added. Discrete steps and AVR behavior are outside this study. Nominal admittance, intermediate G/B replay, and the original anchor are verified before solving.\n")
        println(io,"Eight nominal anchor-start cells compare fixed settings with shunt-only freedom; this is qualification, not the full 192-cell matrix. Fixed droop curves remain active in both families.\n")
        println(io,"| Cell | Valid | Final status |\n|---|---:|---|")
        for row in rows
            println(io,"| ",row["name"]," | ",row["valid"]," | ",last(row["attempts"])["status"]," |")
        end
    end
    rows
end

abspath(PROGRAM_FILE)==(@__FILE__) && s1_existing_shunt_pilot(abspath(ARGS[1]))
