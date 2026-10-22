include("s1_free_droop.jl")
# Same mathematical contract and objective; retain every extra numerical trial.
function fd_extra_recover(size,stage,family,f,solver=:ccopt)
    x=fd_inputs(size);out=joinpath(FD_OUT,string(size))
    rows=[JSON.parsefile(p) for p in readdir(joinpath(out,"attempts");join=true)]
    matches(r)=r["tags"]["family"]==family && r["tags"]["factor"]==f && (r["tags"]["stage"]==stage || get(r["tags"],"target_stage","")==stage)
    direct=filter(r->matches(r) && r["tags"]["stage"]==stage,rows);@assert length(direct)==9
    any(r->matches(r) && r["accepted"] && r["solver"]==string(solver),rows) && return true
    if stage=="design"
        base,p=fd_model(x,family)
    else
        base=read_study(joinpath(out,"selected-$family-study.json")).case
        p=(tap_controls=TapControl[],shunt_controls=ShuntControl[],droop_controls=DroopControl[])
    end
    c=DroopOPF._feasibility_scaled_case(base,f);@assert DroopOPF._feasibility_case_hash(c)==direct[1]["contract"]["case"]
    good=sort(filter(r->matches(r) && r["accepted"],rows);by=r->(r["solver"]!="madnlp",r["loss_mw"]))
    @assert !isempty(good) "No verified source for extra recovery"
    seed=good[1];alt=first(sort(good;by=r->(r["solver"]!="ipopt",r["loss_mw"])))
    for (n,(anchor,mu,norm)) in enumerate(((seed,1e-6,:none),(seed,1e-10,:none),(seed,1e-6,:bounds),(alt,1e-6,:none),(alt,1e-4,:bounds)))
        tags=Dict("stage"=>"recovery","target_stage"=>stage,"family"=>family,"factor"=>f,"failed_attempts"=>[r["name"] for r in direct if !r["accepted"] && r["solver"]==string(solver)],"seed"=>anchor["name"],"method"=>"alternate verified start, barrier $(mu), normalization $(norm), expanded budget")
        r=fd_attempt(size,c,a500_state(anchor["state"]),fd_warm_policy(c,p,anchor),x,"extra-$stage-$family-$f-$solver-$n",tags;solver,iterations=3000,seconds=120.,mu=solver==:ccopt ? mu : nothing,normalization=norm)
        r["accepted"] && return true
    end
    false
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    fd_extra_recover(500,"design","droop_tap_shunt",1.05)
end
