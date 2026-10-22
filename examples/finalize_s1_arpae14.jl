# Package the accepted S1 closeout without performing any optimization.
include("s1_arpae14_joint_reference.jl")
function finalize_s1_arpae14()
    out=joinpath(GATED_ROOT,"artifacts/s1_arpae14_closeout");mkpath(out)
    source,_,angles,_=gated_inputs()
    rows=JSON.parse.(readlines(joinpath(JR_OUT,"rows.jsonl")))
    append!(rows,JSON.parse.(readlines(joinpath(JR_OUT,"joint_anchor_rows.jsonl"))))
    selected=JSON.parsefile(joinpath(JR_OUT,"selected.json"))["relative5"]
    ref=only(filter(r->r["name"]==selected,rows));base=read_study(joinpath(JR_OUT,"relative5-study.json")).case
    taps=eq_settings(ref["taps"]);bs=eq_settings(ref["susceptances"])
    frozen=with_shunt_settings(with_tap_settings(base,taps),bs)
    path=joinpath(out,"frozen-study.json");write_study(path,Study(frozen))
    # Reload exactly what a future consumer will read; bank B is now a fixed admittance.
    frozen=read_study(path).case
    calibration=validate_feasibility_witness(FeasibilityProblem(frozen;angle_limits=angles),FeasibilityWitness(eq_state(ref["state"])))
    @assert calibration["valid"]
    checks=[];selected_rows=[]
    fr=filter(r->get(r["tags"],"arm","")=="joint_frozen" && r["tags"]["range"]=="relative5",rows)
    @assert length(fr)==45
    for r in fr
        c=DroopOPF._feasibility_scaled_case(frozen,r["tags"]["factor"])
        a=validate_feasibility_witness(FeasibilityProblem(c;angle_limits=angles),FeasibilityWitness(eq_state(r["state"])))
        @assert a["valid"]==r["point_pass"]
        push!(checks,Dict("name"=>r["name"],"factor"=>r["tags"]["factor"],"solver"=>r["solver"],"accepted"=>r["accepted"],"physical_valid"=>a["valid"],"termination"=>r["solver_status"]))
    end
    for f in (.9,.95,1.,1.05,1.1)
        good=filter(r->r["tags"]["factor"]==f && r["accepted"],fr);@assert !isempty(good)
        chosen=first(sort(good;by=r->(r["loss_mw"],r["name"])));push!(selected_rows,chosen)
    end
    write(joinpath(out,"demand_witnesses.json"),JSON.json(selected_rows;pretty=true))
    write(joinpath(out,"calibration_reference.json"),JSON.json(ref;pretty=true))
    write(joinpath(out,"replay_checks.json"),JSON.json(Dict("calibration"=>DroopOPF._json_data(calibration),"attempts"=>checks,"mismatches"=>0,"serialized_frozen_case_reloaded"=>true);pretty=true))
    angles_path=joinpath(out,"angle_limits.json");write(angles_path,JSON.json(DroopOPF._json_data(angles);pretty=true))
    # Angle limits live outside Study in the current experiment API and are required on replay.
    files=[path,angles_path,joinpath(out,"demand_witnesses.json"),joinpath(out,"calibration_reference.json"),joinpath(out,"replay_checks.json"),
        joinpath(JR_OUT,"rows.jsonl"),joinpath(JR_OUT,"joint_anchor_rows.jsonl"),joinpath(JR_OUT,"protocol.json"),joinpath(JR_OUT,"audit.json"),
        joinpath(GATED_ROOT,"test/data/arpae/c1_network01/results/scenario_01_pmin0_qsym/network_model.json"),
        joinpath(GATED_ROOT,"test/data/arpae/c1_network01/results/scenario_01/network_model.json"),
        joinpath(GATED_ROOT,"Project.toml"),joinpath(GATED_ROOT,"Manifest.toml")]
    append!(files,[joinpath(GATED_ROOT,"examples",f) for f in ("finalize_s1_arpae14.jl","s1_arpae14_joint_reference.jl","s1_arpae14_joint_reference_anchor_check.jl","s1_arpae14_objective_comparison.jl","s1_arpae14_joint_sensitivity.jl","s1_arpae14_gated.jl")])
    append!(files,[joinpath(GATED_ROOT,"src",f) for f in ("joint_design.jl","physics.jl","feasibility.jl","tap_optimization.jl","shunt_optimization.jl")])
    hashes=Dict(relpath(f,GATED_ROOT)=>bytes2hex(sha256(read(f))) for f in files)
    manifest=Dict("status"=>"14-bus S1 case study closed; larger-case S1 qualification pending", "case"=>"ARPA-E C1 Network Model 01 Scenario 01",
        "selected_reference"=>selected,"scope"=>"sampled base-case steady-state AC feasibility, not dynamics/N-1/global optimality",
        "study_limits"=>"Pmin=0; Qmin/Qmax symmetric at larger absolute original bound; originals preserved",
        "reference"=>"100% demand joint loss OPF; all three online taps +/-5% of source operating ratios; available bank3 continuous B=0..0.4",
        "final_controls"=>"five fixed shifted-zero-Q droops, uniform8% full Q span, no deadband; all taps and shunts fixed at joint reference",
        "required_replay_inputs"=>["frozen-study.json","angle_limits.json"],"deadband_width_pu"=>0.,"droop_full_span_percent"=>8.,
        "demands"=>[.9,.95,1.,1.05,1.1],"accepted_attempts"=>count(r->r["accepted"],fr),"total_attempts"=>length(fr),"verified_demand_points"=>5,
        "secondary_comparator"=>"same curves, taps/shunt free within original +/-5% envelope; 45/45 accepted",
        "limits_of_evidence"=>["finite sampled demands only; no continuum robust-feasibility proof","three retained CCOpt iteration-limit failures at 90% demand","voltage and thermal binding limits remain","final joint-reference design not rerun under original generator limits; earlier original-limit results concern other designs"],
        "hashes"=>hashes)
    write(joinpath(out,"manifest.json"),JSON.json(manifest;pretty=true))
    println("CLOSEOUT: nominal calibration and 45 serialized-case replays verified; ",count(r->r["accepted"],fr)," accepted; five demand witnesses saved")
end
abspath(PROGRAM_FILE)==(@__FILE__) && finalize_s1_arpae14()
