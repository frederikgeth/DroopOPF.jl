isdefined(@__MODULE__, :a500_read_policy) || include("audit_s1_arpae500.jl")
function a500_original_diagnostic()
    _,_,angles,costs,_=a500_inputs();base=read_study(joinpath(A500_OUT,"calibrated-study.json")).case
    ref=JSON.parsefile(joinpath(A500_OUT,"selected_reference.json"));rows=[JSON.parsefile(p) for p in readdir(joinpath(A500_OUT,"attempts");join=true)]
    # Equipment freedom is a different contract, explicitly labelled as a potential fix.
    for variant in ("original_q","original_pq"),f in (1.,.9,1.1,.95,1.05)
        rs=filter(r->r["tags"]["stage"]=="original_limits" && r["tags"]["family"]==variant && r["tags"]["factor"]==f,rows)
        any(r->r["point_pass"],rs) && continue
        isempty(rs) && continue
        bounds=first(rs)["operating_bounds"];c=DroopOPF._feasibility_scaled_case(base,f);p=a500_policy(c,"tap_shunt";reference=ref)
        seeds=filter(r->r["tags"]["stage"]=="equipment" && r["tags"]["family"]=="tap_shunt" && r["tags"]["factor"]==f && r["accepted"],rows)
        seed=first(sort(seeds;by=r->r["loss_mw"]))
        for (label,solver,start) in (("study_equipment",:ipopt,seed),("original_cost",:madnlp,JSON.parsefile(joinpath(A500_OUT,"attempts","original-source-$variant-$f.json"))))
            r=a500_attempt(c,a500_state(start["state"]),angles,costs,p,"original-equipment-$variant-$f-$solver";solver,operating_bounds=bounds,iterations=2000,seconds=90.,tags=Dict("stage"=>"original_equipment_fix","factor"=>f,"family"=>variant,"init"=>label,"equipment"=>"tap_shunt"))
            r["accepted"] && break
        end
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && a500_original_diagnostic()
