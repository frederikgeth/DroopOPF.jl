# S1 only: no SCOPF or contingency optimization is started by this example.
using DroopOPF, JSON, SHA

function run_arpae14_feasibility_gate(out=joinpath(@__DIR__,"..","artifacts","s1_arpae14_feasibility_gate"))
    root=normpath(joinpath(@__DIR__,"..")); mkpath(out)
    source=read_study(joinpath(root,"artifacts","s1_arpae14_stress","source-study.json")).case
    data=joinpath(root,"test","data","arpae","c1_network01","results","scenario_01_pmin0_qsym")
    raw=JSON.parsefile(joinpath(data,"network_model.json"))
    sol=JSON.parsefile(joinpath(data,"opf_ac.json"))["solution"]
    anchor=ACState([Float64(sol["bus"][string(b.id)]["vm"]) for b in source.network.buses],
        [Float64(sol["bus"][string(b.id)]["va"]) for b in source.network.buses],
        [Float64(get(sol["gen"],string(g.id),Dict("pg"=>0.))["pg"]) for g in source.generators],
        [Float64(get(sol["gen"],string(g.id),Dict("qg"=>0.))["qg"]) for g in source.generators])
    s=JSON.parsefile(joinpath(root,"artifacts","s1_arpae14_source_opf_90","ac_replay_input.json"))["opf"]["state"]
    source90=ACState(Float64.(s["vm"]),Float64.(s["va"]),Float64.(s["pg"]),Float64.(s["qg"]))
    angles=Dict(b.id=>(Float64(raw["branch"][string(b.id)]["angmin"]),
        Float64(raw["branch"][string(b.id)]["angmax"])) for b in source.network.branches)
    inputs=[joinpath(data,"network_model.json"),joinpath(data,"opf_ac.json"),
        joinpath(root,"artifacts","s1_arpae14_stress","source-study.json"),
        joinpath(root,"artifacts","s1_arpae14_source_opf_90","ac_replay_input.json")]
    for variant in ("with_deadband","no_deadband")
        push!(inputs,joinpath(root,"artifacts","s1_arpae14_corrected_comparison","verified",variant*"-study.json"))
        push!(inputs,joinpath(root,"artifacts","s1_arpae14_objectives_free_equipment",variant*"-feasibility-design.json"))
    end
    hashes=Dict(relpath(file,root)=>bytes2hex(sha256(read(file))) for file in inputs)
    open(joinpath(out,"provenance.json"),"w") do io
        JSON.json(io,Dict("julia_version"=>string(VERSION),"scope"=>"S1 base-case only",
            "gate_source_sha256"=>bytes2hex(sha256(read(joinpath(root,"src","feasibility.jl")))),
            "example_sha256"=>bytes2hex(sha256(read(@__FILE__))),"input_sha256"=>hashes,
            "source_limits"=>"study Pmin=0 and symmetric Q bounds; source angle limits included",
            "acceptance_controls"=>"source taps and shunts fixed; all candidate droops fixed",
            "free_equipment"=>"saved witness replay only; continuous shunt bank" );pretty=true)
    end
    rows=Dict{String,Any}[]
    for variant in ("with_deadband","no_deadband")
        candidate=read_study(joinpath(root,"artifacts","s1_arpae14_corrected_comparison","verified",variant*"-study.json")).case
        println("Qualifying ",variant," with fixed source equipment");flush(stdout)
        qualification=qualify_droop_replacement(source,candidate;calibration_state=anchor,
            load_factors=(1.,.9),initial_states=[anchor,source90],
            witnesses=Dict("source/0.9"=>[FeasibilityWitness(source90;label="saved source OPF at 90%")]),
            problem_options=(angle_limits=angles,),
            search_options=(optimizer_attributes=Dict("tol"=>1e-9,"max_iter"=>1000,"max_cpu_time"=>30.),))
        write_droop_qualification(joinpath(out,variant*"-qualification.json"),qualification)
        for (label,p,r) in zip(qualification.labels,qualification.problems,qualification.results)
            push!(rows,Dict("variant"=>variant,"condition"=>label,"equipment"=>"fixed source settings",
                "status"=>string(r.status),"fingerprint"=>r.fingerprint,
                "evidence_revalidated"=>verify_feasibility_result(p,r),
                "local_attempts"=>count(a->a["stage"]=="local_search",r.attempts)))
            println(label," => ",r.status);flush(stdout)
        end
        blocked=false
        try
            require_qualified_replacement(qualification)
        catch e
            e isa ArgumentError || rethrow()
            blocked=true
        end
        # Replay the previously saved free-equipment witness under both scopes.
        # This runs no additional equipment optimization.
        saved=read_joint_design(joinpath(root,"artifacts","s1_arpae14_objectives_free_equipment",variant*"-feasibility-design.json"))
        w=FeasibilityWitness(saved;label="saved free-equipment solution")
        fixed=qualification.problems[end]
        fixed_check=validate_feasibility_witness(fixed,w)
        free=FeasibilityProblem(fixed.case;tap_controls=saved.tap_controls,
            shunt_controls=saved.shunt_controls,angle_limits=angles)
        free_result=check_feasibility(free;witnesses=[w],solve_missing=false)
        write_feasibility_result(joinpath(out,variant*"-free-equipment-replay.json"),free,free_result)
        push!(rows,Dict("variant"=>variant,"condition"=>"candidate/0.9","equipment"=>"free taps and continuous bank",
            "status"=>string(free_result.status),"fingerprint"=>free_result.fingerprint,
            "evidence_revalidated"=>verify_feasibility_result(free,free_result),"local_attempts"=>0,
            "rejected_under_fixed_scope"=>!fixed_check["valid"],"fixed_replacement_blocked"=>blocked))
        open(joinpath(out,"summary.json"),"w") do io
            JSON.json(io,rows;pretty=true)
        end
    end
    all(bytes2hex(sha256(read(joinpath(root,file))))==digest for (file,digest) in hashes) ||
        error("a saved input changed during qualification")
    rows
end

if abspath(PROGRAM_FILE)==@__FILE__
    run_arpae14_feasibility_gate()
end
