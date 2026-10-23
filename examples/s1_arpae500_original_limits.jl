isdefined(@__MODULE__, :a500_inputs) || include("s1_arpae500_campaign.jl")
function a500_original_limits()
    source,_,angles,costs,_=a500_inputs();base=read_study(joinpath(A500_OUT,"frozen-study.json")).case
    original=JSON.parsefile(joinpath(A500_ROOT,"test/data/arpae/c1_network01/results/network_model.json"));@assert length(original["bus"])==500
    prior=[JSON.parsefile(p) for p in readdir(joinpath(A500_OUT,"attempts");join=true)]
    for variant in ("original_p","original_q","original_pq")
        axes=variant=="original_p" ? ("p",) : variant=="original_q" ? ("q",) : ("p","q")
        bounds=Dict(string(g.id)=>Dict(axis*side=>Float64(original["gen"][string(g.id)][axis*side]) for axis in axes for side in ("min","max")) for g in source.generators if g.available)
        for f in (1.,.9,1.1,.95,1.05)
            src=JSON.parsefile(joinpath(A500_OUT,"attempts","source-cost-$f-ipopt.json"));c=DroopOPF._feasibility_scaled_case(source,f);p=a500_policy(c,"fixed")
            anchor=a500_attempt(c,a500_state(src["state"]),angles,costs,p,"original-source-$variant-$f";objective="cost",operating_bounds=bounds,tags=Dict("stage"=>"original_source","factor"=>f,"family"=>variant))
            good=filter(r->r["tags"]["stage"]=="frozen" && r["tags"]["factor"]==f && r["accepted"],prior)
            isempty(good) && error("no prior fixed study witness at $f")
            best=first(sort(good;by=r->r["loss_mw"]));c=DroopOPF._feasibility_scaled_case(base,f);p=a500_policy(c,"fixed")
            trials=Any[]
            for (init,r,solver) in (("study_witness",best,:ipopt),("original_cost",anchor,:madnlp))
                r["accepted"] || continue
                result=a500_attempt(c,a500_state(r["state"]),angles,costs,p,"original-$variant-$f-$init-$solver";solver,operating_bounds=bounds,tags=Dict("stage"=>"original_limits","factor"=>f,"family"=>variant,"init"=>init))
                push!(trials,result)
            end
            good=filter(r->r["point_pass"],trials)
            seed=isempty(good) ? anchor : first(sort(good;by=r->r["loss_mw"]))
            if haskey(seed,"state")
                a500_attempt(c,a500_state(seed["state"]),angles,costs,p,"original-$variant-$f-warm-ccopt";solver=:ccopt,operating_bounds=bounds,tags=Dict("stage"=>"original_limits","factor"=>f,"family"=>variant,"init"=>isempty(good) ? "original_cost" : "verified_variant_witness","seed"=>seed["name"]))
            end
        end
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && a500_original_limits()
