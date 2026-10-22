# Independent initialization repair after original repeated passes; retain all native failures.
function pq_repair_repeated_outage()
    file=joinpath(P2Q,"fullcatalog-repeat/RESULTS.json");saved=P2S2.JSON.parsefile(file)
    x=P2S2.p2_context(500);seed=pq_source(500)
    for row in saved["rows"]
        row["accepted"]&&continue
        accepted=Set{String}();seen=Set{String}()
        for path in row["paths"]
            folder=joinpath(P2S2.ROOT,path);c=P2S2.JSON.parsefile(joinpath(folder,"contract.json"));union!(seen,c["outages"])
            P2S2.JSON.parsefile(joinpath(folder,"summary.json"))["accepted"]&&union!(accepted,c["outages"])
        end
        started=time()
        for id in setdiff(seen,accepted)
            e=only(e for e in x.events if string(e.id)==id)
            for init in ("base","flat")
                folder=joinpath(P2Q,"fullcatalog-repeat/rep-$(row["rep"])/start-repair-$id-$init")
                a=P2S2.pq_attempt(x,folder,(1.,),[e];seed,fixed_controller=true,fixed_base=true,initialization=init,
                    zero_shedding=false,seconds=20.)
                push!(row["paths"],a.summary.folder)
                if a.summary.accepted;push!(accepted,id);break;end
            end
        end
        elapsed=time()-started;row["additional_start_repair_seconds"]=elapsed;row["wall_seconds"]+=elapsed
        row["accepted_outages"]=length(accepted);row["accepted"]=length(accepted)==389
        P2S2.fd_save(file,saved)
    end
end
