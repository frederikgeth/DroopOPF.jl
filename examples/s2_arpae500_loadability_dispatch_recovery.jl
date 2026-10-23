# Bounded contingency-addition recovery. The controller is fixed; preventive
# dispatch and corrective equipment remain free under the confirmed policy.
include("s2_arpae500_loadability.jl")

function el_dispatch_recovery()
    x=el_context()
    controller=read_study(joinpath(EL_OUT,"decomposition/shared-controller.json"))
    states=Dict()
    for r in JSON.parsefile(joinpath(EL_OUT,"decomposition/shared-states.json"))
        states[(Float64(r["factor"]),Symbol(r["id"]))]=(;state=a500_state(r["state"]),
            taps=a500_settings(r["taps"]),banks=a500_settings(r["banks"]),dr=a500_settings(r["dr"]),shed=a500_settings(r["shed"]))
    end
    ids=(:branch_219,:generator_14,:generator_60,:branch_36,:branch_562)
    events=filter(e->e.id in ids,eligible_contingencies(contingency_catalog(x.study.case)))
    rows=Any[]
    for f in (1.05,1.1)
        # Topology-specific nominal states supply angles and equipment starts.
        for id in (:branch_36,:branch_562)
            nominal=read_scopf_result(joinpath(S2500_QUAL,"expanded-madnlp-reserve/round-1/demand-1.0",string(id),"result.json"))
            s=nominal.states[id]
            states[(f,id)]=(;state=ACState(copy(s.vm),copy(s.va),s.pg.*f,copy(s.qg)),
                taps=nominal.tap_settings[id],banks=nominal.shunt_settings[id],
                dr=Dict(l.id=>0. for l in controller.case.loads),shed=Dict(l.id=>0. for l in controller.case.loads))
        end
        seed=(;study=controller,states)
        lane=el_solve(x,"dispatch-recovery/demand-$f/zero-shedding",(f,),events;
            seed,fixed_controller=true,emergency=true,relief=true,thermal_multiplier=1.1,
            restore=false,zero_shedding=true,feasibility_only=true,solver=:madnlp,seconds=90.)
        selected=el_select_accepted(lane.folder)
        if isnothing(selected)
            # The audited LP supplies only a numerical start, never an AC claim.
            lp=JSON.parsefile(joinpath(EL_OUT,"shared_active_bound/factor-1.1/seed.json"))
            coordinated=copy(states)
            for r in lp["states"]
                id=Symbol(r["id"]);haskey(coordinated,(f,id)) || continue
                old=coordinated[(f,id)];normal=id==:base ? controller.case : scenario_case(controller.case,only(filter(e->e.id==id,events)))
                pg=[g.available ? clamp(r["pg"][i]*f/1.1,g.p_min,g.p_max) : 0. for (i,g) in enumerate(normal.generators)]
                dr=Dict(l.id=>clamp(get(r["dr"],string(l.id),0.)*f/1.1,0.,.01*max(0.,l.p*f)) for l in normal.loads)
                shed=Dict(l.id=>max(0.,get(r["shed"],string(l.id),0.)*f/1.1) for l in normal.loads)
                total=sum(values(shed));total>.1 && (shed=Dict(i=>v*.1/total for(i,v) in shed))
                coordinated[(f,id)]=(;old...,state=ACState(old.state.vm,old.state.va,pg,old.state.qg),dr,shed)
            end
            lane=el_solve(x,"dispatch-recovery/demand-$f/coordinated-last-resort",(f,),events;
                seed=(;study=controller,states=coordinated),fixed_controller=true,emergency=true,relief=true,
                thermal_multiplier=1.1,restore=false,feasibility_only=true,solver=:ipopt,seconds=90.)
            selected=el_select_accepted(lane.folder)
        end
        if !isnothing(selected)
            zero_shedding=all(all(abs(v)<1e-12 for v in values(s.shed)) for s in values(selected.point.states))
            penalty=el_solve(x,"dispatch-recovery/demand-$f/penalty",(f,),events;
                seed=selected.point,fixed_controller=true,emergency=true,relief=true,thermal_multiplier=1.1,
                restore=false,zero_shedding,separator=true,solver=:madnlp,seconds=60.)
            better=el_select_accepted(penalty.folder)
            if !isnothing(better);lane=penalty;selected=better;end
        end
        push!(rows,(;factor=f,path=relpath(lane.folder,EL_OUT),accepted=!isnothing(selected),
            stage=isnothing(selected) ? nothing : selected.stage))
        fd_save(joinpath(EL_OUT,"dispatch-recovery/summary.json"),(;rows,outages=collect(ids),
            fixed_controller=true,preventive_dispatch_free=true,exhaustive_connected_qualified=false))
    end
end

abspath(PROGRAM_FILE)==(@__FILE__) && el_dispatch_recovery()
