include("audit_s1_arpae500.jl")
function a500_audit_supplement()
    previous=JSON.parsefile(joinpath(A500_OUT,"audit_primary.json"));prior=Set(JSON.parsefile(joinpath(A500_OUT,"audit_primary_names.json")))
    _,_,angles,costs,_=a500_inputs();n=0;physical=0;accepted=0
    for path in readdir(joinpath(A500_OUT,"attempts");join=true)
        r=JSON.parsefile(path);r["name"] in prior && continue;haskey(r,"state") || continue
        c=read_study(joinpath(A500_ROOT,r["model_path"])).case;p=a500_read_policy(r["policy"])
        @assert feasibility_fingerprint(FeasibilityProblem(c;p...,angle_limits=angles))==r["contract"]["model"]
        @assert DroopOPF._feasibility_hash(r["contract"])==r["contract_hash"]
        @assert get(r,"operating_bounds",nothing)==get(r["contract"],"operating_bounds",nothing)
        old=deepcopy(r);a500_details(c,r,angles,p,costs)
        @assert r["point_pass"]==old["point_pass"] && r["accepted"]==old["accepted"]
        @assert isapprox(r["loss_mw"],old["loss_mw"];atol=1e-8)
        @assert isapprox(r["economic_cost"],old["economic_cost"];atol=1e-6)
        n+=1;physical+=r["point_pass"];accepted+=r["accepted"]
    end
    for (path,expected) in JSON.parsefile(joinpath(A500_OUT,"protocol.json"))["hashes"]
        startswith(path,"test/data/") || continue
        @assert bytes2hex(sha256(read(joinpath(A500_ROOT,path))))==expected
    end
    a500_save(joinpath(A500_OUT,"audit.json"),merge(previous,Dict("states_replayed"=>previous["states_replayed"]+n,"physical_witnesses"=>previous["physical_witnesses"]+physical,"accepted"=>previous["accepted"]+accepted,"supplement_states"=>n,"all_recorded_source_hashes_unchanged"=>true)))
    println("SUPPLEMENT AUDIT ",n," states; all sources unchanged")
end
abspath(PROGRAM_FILE)==(@__FILE__) && a500_audit_supplement()
