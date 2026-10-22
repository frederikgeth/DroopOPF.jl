# Full connected catalogue; every post-outage start is reconstructed from flat.
function p2_cold_catalogue(x,seed,folder;droop_correction=false)
    rows=Any[];events=x.events
    P2S2.fd_save(joinpath(folder,"protocol.json"),(;events=[e.id for e in events],factor=1.,batch_size=2,
        droop_correction,primary_cpu_seconds=20.,retry_cpu_seconds=40.,fixed_base=true,fixed_curves=true,
        initialization="Flat voltage plus inverse-droop PV power-flow preparation from preventive PG/Q and equipment; no stored post-outage state used",
        acceptance="Native success plus full independent original-network physical audit"))
    for i in 1:2:length(events)
        batch=events[i:min(i+1,end)]
        row=p2_sparse_cold_trial(x,seed,batch,joinpath(folder,"batch-$i");rep=i,pv_preparation=true,seconds=20.,droop_correction)
        push!(rows,row)
        P2S2.fd_save(joinpath(folder,"RESULTS.json"),(;rows,attempted_outages=sum(length(r.events) for r in rows),
            accepted_outages=sum(length(r.events) for r in rows if r.accepted),complete=i+1>=length(events),post_outage_oracle_used=false))
        isfile(joinpath(folder,"STOP")) && return rows
        println("COLD CATALOGUE ",min(i+1,length(events)),"/",length(events));flush(stdout)
    end
    rows
end
