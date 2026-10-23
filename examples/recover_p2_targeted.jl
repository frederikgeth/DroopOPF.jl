include("p2_targeted_joint.jl")
function targeted_recover(root;method="monotone")
    x=p2_inputs(joinpath(root,"preflight-long-recovery"));candidate="joint-five"
    parent=read_multi_period_security(joinpath(root,candidate,"result.json"));factors=[.9,1.,1.05,1.,.9]
    out=joinpath(root,method=="monotone" ? "resolutions-long" : "resolutions-lbfgs");mkpath(out);journal=joinpath(out,"summary.json")
    rows=isfile(journal) ? JSON.parsefile(journal)["rows"] : Any[]
    done=Set(Symbol(r["event"]) for r in rows)
    for scan in sort(readdir(root;join=true))
        startswith(basename(scan),"scan-"*candidate)||continue
        isfile(joinpath(scan,"summary.json"))||continue
        for row in JSON.parsefile(joinpath(scan,"summary.json"))["rows"]
            id=Symbol(row["event"]);(row["accepted"] || id in done)&&continue
            prior=read_multi_period_security(joinpath(row["path"],"result.json"))
            studies=[read_study(joinpath(row["path"],"period-$t.json")) for t in 1:5]
            events=[only(e for e in x.events if e.contingency.id==id)]
            starts=[Dict(k=>v for (k,v) in p.states if !isnothing(v)) for p in prior.periods]
            eq=[(;taps=p.tap_settings[id],shunts=p.shunt_settings[id]) for p in prior.periods]
            path=joinpath(out,string(id))
            result=mix_attempt(x,path,factors,events;studies,starts,initial_equipment=eq,
                initial_balancing_power=[p.balancing_power for p in prior.periods],fixed_bases=parent.periods,
                response=:limit_aware,emergency=false,seconds=method=="monotone" ? 90. : 45.,smooth_epsilon=1e-6,
                solver_options=merge(Dict("bound_push"=>1e-10,"bound_frac"=>1e-10,"slack_bound_push"=>1e-10,"slack_bound_frac"=>1e-10),
                    method=="monotone" ? Dict("mu_strategy"=>"monotone","mu_init"=>1e-7) :
                    Dict("hessian_approximation"=>"limited-memory","limited_memory_max_history"=>10,"max_iter"=>3000)))
            push!(rows,Dict("event"=>string(id),"accepted"=>result.summary.accepted,"path"=>path,"status"=>string(result.summary.status)))
            push!(done,id);mix_save(journal,(;candidate,rows));GC.gc()
        end
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && targeted_recover(abspath(ARGS[1]);method=length(ARGS)>1 ? ARGS[2] : "monotone")
