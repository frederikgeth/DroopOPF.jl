function md_checked(attempt,x,folder,factors,events;seed=x.seed,fixed_controller=false,fixed_base=false,seconds=30.)
    a=attempt(x,joinpath(folder,"primary"),factors,events;seed,fixed_controller,fixed_base,seconds)
    a.summary.accepted && return a
    attempt(x,joinpath(folder,"retry"),factors,events;seed=isnothing(a.point) ? seed : a.point,fixed_controller,fixed_base,seconds=2seconds,retry=true)
end
function md_scan(attempt,x,point,factors,folder;seconds=10.)
    rows=Any[];warm=point
    for e in p2_rank(x,.9)
        if all(haskey(point.states,(f,e.id)) for f in factors)
            push!(rows,(;event=e.id,accepted=true,route="independently audited master witness",path=nothing))
        else
            a=md_checked(attempt,x,joinpath(folder,string(e.id)),factors,[e];seed=warm,fixed_controller=true,fixed_base=true,seconds)
            a.summary.accepted && merge!(warm.states,a.point.states)
            push!(rows,(;event=e.id,accepted=a.summary.accepted,route="fresh exact solve",path=a.summary.folder))
        end
        P2S2.fd_save(joinpath(folder,"scan.json"),(;rows,complete=length(rows)==length(x.events),accepted=length(rows)==length(x.events)&&all(r.accepted for r in rows)))
        length(rows)%50==0 && (println("MD SCAN ",factors," ",length(rows),"/389");flush(stdout))
    end
    (;rows,accepted=all(r.accepted for r in rows),warm)
end
# Recover a common design using independent per-demand masters with curves frozen.
# A timed-out joint point is only a start; every accepted master/scan is solved anew.
function md_frozen_stage(x,factor,folder;seed,seconds=60.,max_rounds=4,attempt=P2S2.p2_attempt)
    mkpath(joinpath(folder,"500"));P2S2.fd_save(joinpath(folder,"500/catalogue.json"),x.events)
    ranked=p2_rank(x,.9);included=Set([:branch_36,:branch_219,:branch_562,:generator_14,:generator_60])
    rounds=Any[];dest=joinpath(folder,"500/progressive")
    curves=seed.study.case.controls
    for round in 1:max_rounds
        events=[e for e in ranked if e.id in included]
        a=md_checked(attempt,x,joinpath(dest,"round-$round/master"),(factor,),events;seed,fixed_controller=true,seconds)
        if !a.summary.accepted
            result=(;accepted=false,status="fixed_controller_master_unresolved",rounds,attempt=a.summary)
            P2S2.fd_save(joinpath(dest,"summary.json"),result);return (;result,seed)
        end
        @assert P2S2.DroopOPF._json_data(a.point.study.case.controls)==P2S2.DroopOPF._json_data(curves)
        scan=md_scan(attempt,x,a.point,(factor,),joinpath(dest,"round-$round/scan");seconds=10.)
        failures=[r.event for r in scan.rows if !r.accepted]
        push!(rounds,(;round,included=[e.id for e in events],master=a.summary,accepted=scan.accepted,failures))
        result=(;accepted=scan.accepted,status=scan.accepted ? "exhaustive_connected_audit_passed" : "continuing",rounds)
        P2S2.fd_save(joinpath(dest,"summary.json"),result)
        if scan.accepted
            run(`python3 -B $(joinpath(@__DIR__,"audit_p2_s2_campaign.py")) $folder 500`)
            return (;result,seed=scan.warm)
        end
        seed=scan.warm;union!(included,first(failures,min(4,length(failures))))
    end
    result=(;accepted=false,status="round_bound",rounds)
    P2S2.fd_save(joinpath(dest,"summary.json"),result);(;result,seed)
end
function md_frozen_run(folder,source;factors=(.9,.95,1.,1.05,1.0625,1.075,1.1),allow_shedding=false,source_stage="solve")
    ispath(folder)&&error("Choose fresh output")
    x=md_seed();seed=P2S2.el_read_point(source;stage=source_stage)
    curves=seed.study.case.controls
    P2S2.fd_save(joinpath(folder,"protocol.json"),(;factors,source,source_stage,shared_controller=true,zero_shedding=!allow_shedding,
        objective="feasibility",method="freeze common candidate curves; independently optimize preventive dispatch per demand, then exhaustive fixed-base scan",
        master_seconds=60.,master_retry_seconds=120.,scan_seconds=10.,scan_retry_seconds=20.,max_rounds=4,
        acceptance="Every master native success and physical audit; 389 connected outages per demand; identical curves across demands"))
    rows=Any[]
    for (i,f) in enumerate(factors)
        a=md_frozen_stage(x,f,joinpath(folder,"stage-$i");seed,attempt=allow_shedding ? P2S2.md_allowance_attempt : P2S2.p2_attempt)
        push!(rows,(;stage=i,factor=f,result=a.result))
        P2S2.fd_save(joinpath(folder,"RESULTS.json"),(;rows,s2_resumed=false,p2_closed=false))
        a.result.accepted || break
        @assert P2S2.DroopOPF._json_data(a.seed.study.case.controls)==P2S2.DroopOPF._json_data(curves)
        # Different demands keep separate preventive bases; share only curves.
        merge!(seed.states,a.seed.states)
    end
    run(`python3 -B $(joinpath(@__DIR__,"audit_p2_s2_multidemand.py")) $folder`)
    rows
end
