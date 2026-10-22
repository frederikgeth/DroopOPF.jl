# Constraint-addition recovery: change the preventive dispatch and corrective
# settings, retaining the exact same droop controller across all demands.
include("s2_arpae500_loadability.jl")
using LinearAlgebra,SparseArrays

function el_active_angle_start(c,state,taps,dr,shed)
    physical=with_tap_settings(c,taps);Y=DroopOPF._admittance_matrix(physical.network)
    idx=DroopOPF._bus_indices(c.network);n=length(c.network.buses)
    target=zeros(n)
    for (i,g) in enumerate(c.generators);target[idx[g.bus_id]]+=state.pg[i];end
    for l in c.loads;target[idx[l.bus_id]]-=l.p-get(dr,l.id,0.)-get(shed,l.id,0.);end
    candidates=filter(g->g.available,c.generators)
    headroom=Dict(g.id=>g.p_max-state.pg[findfirst(h->h.id==g.id,c.generators)] for g in candidates)
    slack=idx[candidates[argmax([headroom[g.id] for g in candidates])].bus_id]
    free=setdiff(collect(1:n),[slack]);theta=copy(state.va);vm=state.vm
    initial=0.;final=0.
    for iteration in 1:8
        v=vm.*cis.(theta);p=real.(v.*conj.(Y*v));residual=target-p
        iteration==1 && (initial=maximum(abs,residual[free]))
        final=maximum(abs,residual[free]);final<1e-8 && break
        h=zeros(n,n)
        for i in 1:n,j in 1:n
            i==j && continue;iszero(Y[i,j]) && continue
            a=theta[i]-theta[j]
            h[i,j]=vm[i]*vm[j]*(real(Y[i,j])*sin(a)-imag(Y[i,j])*cos(a))
            h[i,i]-=h[i,j]
        end
        step=sparse(h[free,free])\residual[free]
        scale=min(1.,.15/max(maximum(abs,step),1e-12))
        theta[free].+=scale.*step
    end
    reference=findfirst(b->b.reference,c.network.buses);theta.-=theta[reference]
    result=ACState(copy(vm),theta,copy(state.pg),copy(state.qg))
    (;state=result,diagnostic=(;computational_slack_bus=c.network.buses[slack].id,
        original_reference_bus=c.network.buses[reference].id,initial_non_slack_p_error_pu=initial,
        final_non_slack_p_error_pu=final,claim="Angle initialization only; not an AC equilibrium witness"))
end

function el_dispatch_seed(x,controller,f,events;use_lp=false)
    lpfile=joinpath(EL_OUT,"shared_active_bound/factor-1.1/seed.json")
    lp=use_lp ? JSON.parsefile(lpfile) : nothing
    !isnothing(lp) && (lp["status"]=="OPTIMAL" || error("No relaxed dispatch seed"))
    states=Dict();diagnostics=Any[];source_paths=String[]
    study=DroopOPF._copy_study(controller;case=DroopOPF._feasibility_scaled_case(controller.case,f),contingencies=events)
    for (id,c) in zip([:base;[e.id for e in events]],[study.case;[scenario_case(study.case,e) for e in events]])
        r=x.result
        if !haskey(r.states,id)
            source=joinpath(S2500_OUT,"qualification/expanded-madnlp-reserve/round-1/demand-1.0/$(id)/result.json")
            r=read_scopf_result(source);push!(source_paths,source)
        end
        prior=r.states[id];taps=r.tap_settings[id];banks=r.shunt_settings[id]
        dr=Dict(l.id=>0. for l in c.loads);shed=copy(dr)
        pg=[g.available ? clamp(prior.pg[i]*f,g.p_min,g.p_max) : 0. for(i,g) in enumerate(c.generators)]
        if use_lp
            key=string(id) in [s["id"] for s in lp["states"]] ? string(id) : "branch_36"
            row=only(filter(s->s["id"]==key,lp["states"]));ratio=f/lp["factor"]
            pg=[g.available ? clamp(row["pg"][i]*ratio,g.p_min,g.p_max) : 0. for(i,g) in enumerate(c.generators)]
            for l in c.loads
                dr[l.id]=clamp(row["dr"][string(l.id)]*ratio,0.,.01*l.p)
                shed[l.id]=clamp(row["shed"][string(l.id)]*ratio,0.,.1*l.p-dr[l.id])
            end
            total=sum(values(shed));total>10/c.base_power && foreach(i->shed[i]*=(10/c.base_power)/total,keys(shed))
        end
        qg=[g.available ? clamp(prior.qg[i]*f,g.q_min,g.q_max) : 0. for(i,g) in enumerate(c.generators)]
        raw=ACState(copy(prior.vm),prior.va.*f,pg,qg)
        angle=el_active_angle_start(c,raw,taps,dr,shed)
        states[(f,id)]=(;state=angle.state,taps,banks,dr,shed)
        push!(diagnostics,(;id,angle.diagnostic...))
    end
    (;study=controller,states,diagnostics,source_paths)
end

function el_dispatch_recovery()
    x=el_context();controller=read_study(joinpath(EL_OUT,"decomposition/shared-controller.json"))
    events=filter(e->e.id in (:generator_14,:generator_60,:branch_219,:branch_36,:branch_562),eligible_contingencies(contingency_catalog(x.study.case)))
    rows=Any[]
    for f in (1.05,1.1)
        nominal=el_dispatch_seed(x,controller,f,events)
        folder=joinpath(EL_OUT,"dispatch-recovery/demand-$f");mkpath(folder)
        fd_save(joinpath(folder,"nominal-topology-start.json"),nominal)
        lane=el_solve(x,"dispatch-recovery/demand-$f/zero-shedding",(f,),events;seed=nominal,
            fixed_controller=true,emergency=true,relief=true,thermal_multiplier=1.1,zero_shedding=true,
            restore=false,feasibility_only=true,solver=:madnlp,seconds=120.)
        selected=el_select_accepted(lane.folder)
        if isnothing(selected)
            coordinated=el_dispatch_seed(x,controller,f,events;use_lp=true)
            fd_save(joinpath(folder,"coupled-lp-angle-start.json"),coordinated)
            lane=el_solve(x,"dispatch-recovery/demand-$f/coordinated-start",(f,),events;seed=coordinated,
                fixed_controller=true,emergency=true,relief=true,thermal_multiplier=1.1,
                restore=false,feasibility_only=true,solver=:madnlp,seconds=180.)
            selected=el_select_accepted(lane.folder)
        end
        if !isnothing(selected)
            penalty=el_solve(x,"dispatch-recovery/demand-$f/penalties",(f,),events;seed=selected.point,
                fixed_controller=true,emergency=true,relief=true,thermal_multiplier=1.1,
                restore=false,separator=true,solver=:madnlp,seconds=120.)
            improved=el_select_accepted(penalty.folder)
            if !isnothing(improved);selected=improved;lane=penalty;end
        end
        push!(rows,(;factor=f,accepted=!isnothing(selected),path=relpath(lane.folder,EL_OUT),
            stage=isnothing(selected) ? nothing : selected.stage))
        fd_save(joinpath(EL_OUT,"dispatch-recovery/summary.json"),(;rows,controller_fixed=true,
            added_outages=[:branch_36,:branch_562],physical_remedies_investigated=false))
        if !isnothing(selected)
            write_study(joinpath(folder,"selected-controller.json"),selected.point.study)
            fd_save(joinpath(folder,"selected-states.json"),[(;factor=ff,id,state=s.state,taps=s.taps,banks=s.banks,dr=s.dr,shed=s.shed) for((ff,id),s) in selected.point.states])
        end
    end
end

abspath(PROGRAM_FILE)==(@__FILE__) && el_dispatch_recovery()
