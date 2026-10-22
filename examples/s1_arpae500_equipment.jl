isdefined(@__MODULE__, :a500_inputs) || include("s1_arpae500_campaign.jl")
function a500_equipment_stage()
    _,_,angles,costs,_=a500_inputs();base=read_study(joinpath(A500_OUT,"calibrated-study.json")).case;ref=JSON.parsefile(joinpath(A500_OUT,"selected_reference.json"))
    for family in ("tap_shunt","tap","shunt")
        c0=family=="tap" ? with_shunt_settings(base,a500_settings(ref["susceptances"])) : family=="shunt" ? with_tap_settings(base,a500_settings(ref["taps"])) : base
        p=a500_policy(c0,family;reference=ref)
        for f in (1.,.9,1.1,.95,1.05),init in ("joint","loss","cost"),solver in (:ipopt,:madnlp,:ccopt)
            r=init=="joint" ? ref : JSON.parsefile(joinpath(A500_OUT,"attempts","source-$init-$f-ipopt.json"));@assert r["accepted"]
            c=DroopOPF._feasibility_scaled_case(c0,f)
            a500_attempt(c,a500_state(r["state"]),angles,costs,p,"equipment-$family-$f-$init-$solver";solver,tags=Dict("stage"=>"equipment","factor"=>f,"init"=>init,"family"=>family))
        end
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && a500_equipment_stage()
