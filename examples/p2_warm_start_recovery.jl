# Operational recovery is recorded separately; pure-flat qualification stays failed.
function pq_warm_start_recovery()
    saved=P2S2.JSON.parsefile(joinpath(P2Q,"benchmarks/RESULTS.json"));rows=Any[]
    x=P2S2.p2_context(500);seed=pq_source(500)
    for original in saved["rows"]
        (original["size"]==500 && original["initialization"]=="flat" && !original["warmup"])||continue
        events=[e for e in x.events if string(e.id) in original["events"]]
        started=time();dest=joinpath(P2Q,"warm-recovery/rep-$(original["rep"])")
        a=P2S2.pq_attempt(x,joinpath(dest,"primary"),(1.,),events;seed,fixed_controller=true,fixed_base=true,
            initialization="base",zero_shedding=false,seconds=20.)
        paths=[a.summary.folder]
        if !a.summary.accepted
            a=P2S2.pq_attempt(x,joinpath(dest,"retry"),(1.,),events;seed,fixed_controller=true,fixed_base=true,
                initialization="base",zero_shedding=false,seconds=40.,retry=true)
            push!(paths,a.summary.folder)
        end
        added=time()-started
        push!(rows,(;rep=original["rep"],accepted=a.summary.accepted,paths,events=[e.id for e in events],
            pure_flat_accepted=original["accepted"],failed_flat_workflow_seconds=original["wall_seconds"],
            base_fallback_seconds=added,total_active_wall_seconds=original["wall_seconds"]+added))
        P2S2.fd_save(joinpath(P2Q,"warm-recovery/RESULTS.json"),(;rows,
            meaning="Explicit validated-base initialization fallback after failed flat workflow; same fixed base, curves, bounds and physical acceptance; does not qualify pure cold starts"))
    end
end
