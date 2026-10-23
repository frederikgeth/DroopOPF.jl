# Cold Phase-I preparation only. Artificial power is never accepted as security.
@eval P2S2 begin
function og_elastic_start(x,seed,events,folder;seconds=90.)
    mkpath(folder);base=seed.states[(1.,:base)]
    states=Dict{Tuple{Float64,Symbol},Any}((1.,:base)=>base)
    for e in events
        c=scenario_case(seed.study.case,e)
        pg=[g.available ? base.state.pg[i] : 0. for (i,g) in enumerate(c.generators)]
        qg=[g.available ? base.state.qg[i] : 0. for (i,g) in enumerate(c.generators)]
        states[(1.,e.id)]=(;base...,state=ACState(ones(length(base.state.vm)),zeros(length(base.state.va)),pg,qg),delta=0.)
    end
    fresh=(;study=seed.study,states)
    t=@timed el_build(x,(1.,),events;seed=fresh,solver=:ipopt,emergency=true,relief=true,thermal_multiplier=1.1,
        fixed_controller=true,fixed_base=true,restore=true,zero_shedding=false,zero_dr=false,
        ac_builder=nr_build_ac,penalty_proxies=false,direct_relief=false)
    built=t.value;m=built.m
    starts=[(;id=b.id,vm=[start_value(v) for v in b.v.vm if v isa VariableRef],va=[start_value(v) for v in b.v.va if v isa VariableRef]) for b in built.blocks if b.id!=:base]
    fd_save(joinpath(folder,"initialization.json"),(;policy="flat",states=starts,post_outage_oracle_used=false))
    @objective(m,Min,sum(built.artificial))
    set_optimizer_attribute(m,"max_cpu_time",seconds)
    set_optimizer_attribute(m,"obj_scaling_factor",100.)
    set_optimizer_attribute(m,"acceptable_iter",3)
    set_optimizer_attribute(m,"acceptable_tol",1e-6)
    solved=@timed optimize!(m)
    record=(;stage="preparation",status=string(termination_status(m)),native_success=false,
        native_optimizer_success=termination_status(m) in (JuMP.MOI.LOCALLY_SOLVED,JuMP.MOI.OPTIMAL,JuMP.MOI.ALMOST_LOCALLY_SOLVED),
        build_seconds=t.time,solve_seconds=solved.time,objective=has_values(m) ? objective_value(m) : nothing,
        role="Numerical initializer only: artificial balance injections forbidden in the subsequent physical solve")
    fd_save(joinpath(folder,"record.json"),record)
    point=el_save_point(folder,built,"preparation",record)
    (;point,record)
end
end
function p2_elastic_cold_trial(x,seed,events,folder;rep=1)
    started=time();a=P2S2.og_elastic_start(x,seed,events,joinpath(folder,"preparation"))
    b=P2S2.pq_attempt(x,joinpath(folder,"physical"),(1.,),events;seed=a.point,
        fixed_controller=true,fixed_base=true,zero_shedding=false,seconds=90.)
    paths=[b.summary.folder]
    if !b.summary.accepted
        b=P2S2.pq_attempt(x,joinpath(folder,"physical-retry"),(1.,),events;seed=a.point,
            fixed_controller=true,fixed_base=true,zero_shedding=false,seconds=180.,retry=true)
        push!(paths,b.summary.folder)
    end
    row=(;rep,accepted=b.summary.accepted,events=[e.id for e in events],wall_seconds=time()-started,
        paths,preparation=a.record,post_outage_oracle_used=false)
    P2S2.fd_save(joinpath(folder,"RESULTS.json"),row);row
end
