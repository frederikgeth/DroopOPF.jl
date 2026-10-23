# Recover numerical scan leftovers without changing the frozen parent candidate.
include("p2_mixed_limit_aware.jl")
function resolve_p2(root;full=false,only_ids=Set{Symbol}())
    candidate="p2-base";source=joinpath(root,candidate)
    parent=read_multi_period_security(joinpath(source,"result.json"))
    x=p2_inputs(joinpath(root,"preflight-resolutions"));factors=[.9,1.,1.05,1.,.9]
    out=joinpath(root,full ? "resolutions-full-topology" : "resolutions");mkpath(out);journal=joinpath(out,"summary.json")
    rows=isfile(journal) ? JSON.parsefile(journal)["rows"] : Any[]
    done=Set(Symbol(r["event"]) for r in rows)
    prior=JSON.parsefile(joinpath(MIX_ROOT,"artifacts/p2_mixed_avr_500_20261022/aggregate-checks.json"))["scans"]["designed"]["rows"]
    for entry in readdir(root;join=true)
        startswith(basename(entry),"scan-"*candidate)||continue
        file=joinpath(entry,"summary.json");isfile(file)||continue
        for row in JSON.parsefile(file)["rows"]
            row["accepted"] && continue
            id=Symbol(row["event"]);id in done && continue
            !isempty(only_ids) && !(id in only_ids) && continue
            event=only(e for e in x.events if e.contingency.id==id)
            studies=[read_study(joinpath(row["path"],"period-$t.json")) for t in 1:5]
            reference=findfirst(r->r["event"]==string(id)&&r["status"]=="native_and_independent_pass",prior)
            old=isnothing(reference) ? read_multi_period_security(joinpath(row["path"],"result.json")) :
                read_multi_period_security(joinpath(prior[reference]["path"],"result.json"))
            starts=Dict[];equipment=NamedTuple[]
            for t in 1:5
                base=parent.periods[t].states[:base];w=old.periods[t].states[id]
                vm=copy(w.vm);va=copy(w.va);pg=copy(base.pg);qg=copy(w.qg)
                c=scenario_case(studies[t].case,event.contingency);idx=DroopOPF._bus_indices(c.network)
                assignments=studies[t].reactive_assignments
                for a in assignments
                    a.mode isa AVR || continue
                    vm[idx[a.location.bus_id]]=a.mode.voltage_setpoint
                end
                for (i,g) in enumerate(c.generators)
                    if !g.available;pg[i]=0.;qg[i]=0.;continue;end
                    lo,hi=reactive_limits(g,pg[i]);qg[i]=clamp(qg[i],lo,hi)
                end
                for a in assignments
                    a.mode isa VoltVarDroop || continue
                    i=findfirst(g->g.id==a.generator_id,c.generators);c.generators[i].available||continue
                    lo,hi=reactive_limits(c.generators[i],pg[i]);lo=max(lo,a.mode.capability.q_min);hi=min(hi,a.mode.capability.q_max)
                    qg[i]=clamp(evaluate(droop_curve(a.mode),vm[idx[a.location.bus_id]]),lo,hi)
                end
                push!(starts,Dict(:base=>base,id=>(full ? w : ACState(vm,va,pg,qg))))
                push!(equipment,(;taps=old.periods[t].tap_settings[id],shunts=old.periods[t].shunt_settings[id]))
            end
            path=joinpath(out,string(id)*(full ? "-full-topology-start" : "-topology-start"))
            result=mix_attempt(x,path,factors,[event];studies,starts,initial_equipment=equipment,
                fixed_bases=parent.periods,seconds=60.,response=:limit_aware,emergency=false,
                solver_options=Dict("bound_push"=>1e-8,"bound_frac"=>1e-8,"slack_bound_push"=>1e-8,"slack_bound_frac"=>1e-8))
            record=Dict("event"=>string(id),"accepted"=>result.summary.accepted,"path"=>path,
                "status"=>string(result.summary.status),"initialization"=>"previous topology witness; new frozen dispatch, targets and curves")
            push!(rows,record);push!(done,id)
            write(journal,JSON.json((;candidate,rows);pretty=true)*"\n")
        end
    end
end
length(ARGS) in (1,2,3)||error("provide P2 campaign root, optional full flag and optional event")
resolve_p2(abspath(ARGS[1]);full=length(ARGS)>=2&&ARGS[2]=="full",only_ids=length(ARGS)==3 ? Set([Symbol(ARGS[3])]) : Set{Symbol}())
