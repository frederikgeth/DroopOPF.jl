isdefined(@__MODULE__, :a500_inputs) || include("s1_arpae500_campaign.jl")
function a500_continuation()
    _,_,angles,costs,_=a500_inputs();base=read_study(joinpath(A500_OUT,"frozen-study.json")).case;p=a500_policy(base,"fixed")
    ref=JSON.parsefile(joinpath(A500_OUT,"selected_reference.json"));last=ref
    for i in 199:-1:180
        f=i/200;c=DroopOPF._feasibility_scaled_case(base,f)
        r=a500_attempt(c,a500_state(last["state"]),angles,costs,p,"continuation-$f-ipopt";tags=Dict("stage"=>"continuation","factor"=>f,"family"=>"fixed","previous"=>last["name"]),iterations=2000,seconds=90.)
        if r["accepted"]
            last=r
        else
            retry=a500_attempt(c,a500_state(last["state"]),angles,costs,p,"continuation-$f-madnlp";solver=:madnlp,tags=Dict("stage"=>"continuation","factor"=>f,"family"=>"fixed","previous"=>last["name"]),iterations=2000,seconds=90.)
            retry["accepted"] && (last=retry)
        end
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && a500_continuation()
