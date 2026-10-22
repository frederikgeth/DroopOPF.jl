# Preserve failed batch trials; recover the same flat initialization with exact separable solves.
function pq_flat_singleton_recovery()
    file=joinpath(P2Q,"benchmarks/RESULTS.json");saved=P2S2.JSON.parsefile(file)
    x=P2S2.p2_context(500);seed=pq_source(500)
    for row in saved["rows"]
        (row["size"]==500 && row["initialization"]=="flat" && !row["warmup"] && !row["accepted"])||continue
        started=time();allaccepted=true;completed=String[]
        for id in row["events"]
            event=only(e for e in x.events if string(e.id)==id)
            folder=joinpath(P2Q,"benchmarks/500/rep-$(row["rep"])/flat-singletons/$id")
            a=P2S2.pq_attempt(x,joinpath(folder,"primary"),(1.,),[event];seed,fixed_controller=true,fixed_base=true,
                initialization="flat",zero_shedding=false,seconds=20.)
            push!(row["paths"],a.summary.folder);push!(row["records"],a.summary.record)
            if !a.summary.accepted
                a=P2S2.pq_attempt(x,joinpath(folder,"retry"),(1.,),[event];seed,fixed_controller=true,fixed_base=true,
                    initialization="flat",zero_shedding=false,seconds=40.,retry=true)
                push!(row["paths"],a.summary.folder);push!(row["records"],a.summary.record)
            end
            push!(completed,id);allaccepted &= a.summary.accepted
            a.summary.accepted||break # One unresolved member rejects this initialization workflow.
        end
        elapsed=time()-started
        row["fallback_completed_events"]=completed;row["fallback_unattempted_events"]=[id for id in row["events"] if !(id in completed)]
        row["batch_accepted"]=false;row["initial_wall_seconds"]=row["wall_seconds"]
        row["fallback_wall_seconds"]=elapsed;row["wall_seconds"]+=elapsed;row["flat_singleton_fallback"]=true
        row["accepted"]=allaccepted;row["process_peak_rss_bytes"]=Sys.maxrss()
        P2S2.fd_save(file,saved)
    end
end
