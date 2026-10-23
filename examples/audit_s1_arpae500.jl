isdefined(@__MODULE__, :a500_inputs) || include("s1_arpae500_campaign.jl")
function a500_read_policy(d)
    taps=[TapControl(Int(x["branch_id"]);lower=x["lower"],upper=x["upper"],initial=x["initial"],nominal=x["nominal"]) for x in d["tap_controls"]]
    shunts=[ShuntControl(Int(x["bank_id"]);lower=x["lower"],upper=x["upper"],initial=x["initial"],nominal=x["nominal"]) for x in d["shunt_controls"]]
    (tap_controls=taps,shunt_controls=shunts)
end
function a500_audit()
    _,_,angles,costs,_=a500_inputs();total=0;points=0;accepted=0;maxerr=0.
    for path in sort(readdir(joinpath(A500_OUT,"attempts");join=true))
        r=JSON.parsefile(path);haskey(r,"state") || continue
        c=read_study(joinpath(A500_ROOT,r["model_path"])).case;p=a500_read_policy(r["policy"])
        @assert feasibility_fingerprint(FeasibilityProblem(c;p...,angle_limits=angles))==r["contract"]["model"]
        @assert get(r,"operating_bounds",nothing)==get(r["contract"],"operating_bounds",nothing)
        @assert DroopOPF._feasibility_hash(r["contract"])==r["contract_hash"]
        old=deepcopy(r);a500_details(c,r,angles,p,costs)
        @assert r["point_pass"]==old["point_pass"] && r["accepted"]==old["accepted"]
        @assert isapprox(r["loss_mw"],old["loss_mw"];atol=1e-8)
        @assert isapprox(r["economic_cost"],old["economic_cost"];atol=1e-6)
        maxerr=max(maxerr,abs(r["loss_mw"]-old["loss_mw"]))
        total+=1;points+=r["point_pass"];accepted+=r["accepted"]
    end
    hashes=JSON.parsefile(joinpath(A500_OUT,"preflight.json"))["source_hashes"]
    for (path,expected) in hashes;@assert bytes2hex(sha256(read(joinpath(A500_ROOT,path))))==expected;end
    a500_save(joinpath(A500_OUT,"audit.json"),Dict("states_replayed"=>total,"physical_witnesses"=>points,"accepted"=>accepted,"discrepancies"=>0,"max_loss_error_mw"=>maxerr,"source_OPF_SCOPF_unchanged"=>true))
    println("AUDIT ",total," states, zero discrepancies; source unchanged")
end
abspath(PROGRAM_FILE)==(@__FILE__) && a500_audit()
