# Reconstruct every retained point from serialized cases/states without solving.
include("s1_arpae14_joint_sensitivity.jl")
function audit_joint_sensitivity(out=JS_OUT;expected_cells=1080)
    _,_,angles,_=gated_inputs()
    rows=[JSON.parse(s) for s in readlines(joinpath(out,"rows.jsonl")) if !isempty(s)]
    length(rows)==expected_cells || error("campaign incomplete")
    cases=Dict();mismatches=[];replayed=0;verified=0
    for row in rows
        haskey(row,"state") || continue
        config=row["tags"]["config"]
        if !haskey(cases,config);cases[config]=read_study(joinpath(out,"$config-study.json")).case;end
        c=DroopOPF._feasibility_scaled_case(cases[config],row["tags"]["factor"])
        s=row["state"];state=ACState(Float64.(s["vm"]),Float64.(s["va"]),Float64.(s["pg"]),Float64.(s["qg"]))
        taps=Dict(parse(Int,k)=>Float64(v) for (k,v) in row["taps"])
        bs=Dict(parse(Int,k)=>Float64(v) for (k,v) in row["susceptances"])
        audit=validate_feasibility_witness(FeasibilityProblem(c;angle_limits=angles),FeasibilityWitness(state;taps,susceptances=bs))
        replayed+=1;verified+=audit["valid"]
        audit["valid"]==row["point_pass"] || push!(mismatches,row["name"])
    end
    summary=Dict("cells"=>length(rows),"states_replayed"=>replayed,"verified_states"=>verified,"mismatches"=>mismatches,"serialized_configurations"=>length(cases))
    write(joinpath(out,"serialization_audit.json"),JSON.json(summary;pretty=true))
    isempty(mismatches) || error("serialized replay mismatch")
    println(JSON.json(summary))
end
abspath(PROGRAM_FILE)==(@__FILE__) && audit_joint_sensitivity()
