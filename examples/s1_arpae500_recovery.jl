isdefined(@__MODULE__, :a500_read_policy) || include("audit_s1_arpae500.jl")
function a500_warm_policy(p,r)
    (tap_controls=[TapControl(x.branch_id;lower=x.lower,upper=x.upper,nominal=x.nominal,initial=clamp(r["taps"][string(x.branch_id)],x.lower,x.upper)) for x in p.tap_controls],
    shunt_controls=[ShuntControl(x.bank_id;lower=x.lower,upper=x.upper,nominal=x.nominal,initial=clamp(r["susceptances"][string(x.bank_id)],isnothing(x.lower) ? -Inf : x.lower,isnothing(x.upper) ? Inf : x.upper)) for x in p.shunt_controls])
end
a500_recovery_model(r)=r["contract"]["model"]*DroopOPF._feasibility_hash(get(r,"operating_bounds",Dict()))
function a500_recovery()
    _,_,angles,costs,_=a500_inputs();rows=[JSON.parsefile(p) for p in readdir(joinpath(A500_OUT,"attempts");join=true)]
    direct=filter(r->r["tags"]["stage"] in ("frozen","equipment","holdout","original_limits","original_source"),rows);ledger=[]
    keys=unique((a500_recovery_model(r),r["solver"],r["objective_kind"]) for r in direct if !r["accepted"])
    for (fp,solver,objective) in keys
        bad=filter(r->a500_recovery_model(r)==fp && r["solver"]==solver && r["objective_kind"]==objective && !r["accepted"],direct)
        allpoints=filter(r->a500_recovery_model(r)==fp && r["point_pass"],direct)
        example=first(bad);c=read_study(joinpath(A500_ROOT,example["model_path"])).case;p=a500_read_policy(example["policy"])
        bounds=get(example,"operating_bounds",nothing)
        prefix="recovery-"*bytes2hex(sha256(fp))[1:12]*"-$solver-$objective";outcomes=[]
        if !isempty(allpoints)
            best=first(sort(allpoints;by=r->r["loss_mw"]));pp=a500_warm_policy(p,best);start=a500_state(best["state"])
            a=validate_feasibility_witness(FeasibilityProblem(c;pp...,angle_limits=angles),FeasibilityWitness(start;taps=a500_settings(best["taps"]),susceptances=a500_settings(best["susceptances"])));@assert a["valid"]
            tags=Dict("stage"=>"recovery","factor"=>example["tags"]["factor"],"family"=>get(example["tags"],"family","fixed"),"failed_attempts"=>[r["name"] for r in bad],"witness"=>best["name"],"method"=>"verified physical warm start")
            r=a500_attempt(c,start,angles,costs,pp,prefix*"-warm";operating_bounds=bounds,solver=Symbol(solver),objective,tags);push!(outcomes,r["name"])
            if !r["accepted"] && solver=="ccopt" && !isnothing(bounds)
                r=a500_attempt(c,start,angles,costs,pp,prefix*"-small-barrier";operating_bounds=bounds,solver=:ccopt,objective,tags=merge(tags,Dict("method"=>"verified warm start, small initial barrier and bound push")),iterations=3000,seconds=120.,ccopt_mu_init=1e-8,extra=Dict{String,Any}("bound_push"=>1e-8,"bound_fac"=>1e-8));push!(outcomes,r["name"])
            end
            if !r["accepted"]
                r=a500_attempt(c,start,angles,costs,pp,prefix*"-long";operating_bounds=bounds,solver=Symbol(solver),objective,tags=merge(tags,Dict("method"=>"verified warm start, expanded budget")),iterations=3000,seconds=120.);push!(outcomes,r["name"])
            end
            if !r["accepted"]
                if solver in ("ipopt","madnlp")
                    r=a500_attempt(c,start,angles,costs,pp,prefix*"-formulation";operating_bounds=bounds,solver=Symbol(solver),objective,tags=merge(tags,Dict("method"=>isnothing(bounds) ? "reduced Q formulation, verified warm start" : "smaller smoothing, original bounds retained")),iterations=3000,seconds=120.,qform=isnothing(bounds) ? :reduced : :explicit,epsilon=isnothing(bounds) ? 1e-6 : 1e-7);push!(outcomes,r["name"])
                else
                    r=a500_attempt(c,start,angles,costs,pp,prefix*"-feasibility";operating_bounds=bounds,solver=:ccopt,objective="feasibility",tags=merge(tags,Dict("method"=>"constant objective on same verified feasible constraints")),iterations=3000,seconds=120.);push!(outcomes,r["name"])
                end
            end
            push!(ledger,Dict("failed_attempts"=>[r["name"] for r in bad],"scope"=>example["tags"],"solver"=>solver,"model_gate"=>"feasible","witness"=>best["name"],"retry_attempts"=>outcomes,"recovered"=>r["accepted"],"recovery_objective"=>r["objective_kind"],"conclusion"=>r["accepted"] ? "recovered; original failures remain recorded" : "solver-specific numerical failure on independently verified feasible model; use verified solver witness, do not label infeasible"))
        else
            result=check_feasibility(FeasibilityProblem(c;p...,angle_limits=angles);solve_missing=false)
            push!(ledger,Dict("failed_attempts"=>[r["name"] for r in bad],"scope"=>example["tags"],"solver"=>solver,"model_gate"=>string(result.status),"recovered"=>false,"conclusion"=>"no witness yet: requires continuation/restoration or physical certificate"))
        end
        a500_save(joinpath(A500_OUT,"recovery_ledger.json"),ledger)
    end
    println("RECOVERY GROUPS ",length(ledger));flush(stdout)
end
abspath(PROGRAM_FILE)==(@__FILE__) && a500_recovery()
