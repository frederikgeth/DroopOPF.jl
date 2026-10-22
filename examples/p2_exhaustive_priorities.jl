# Full-catalogue lexicographic objectives. No optimization on import.
function p2_priority_seed500()
    seed=pq_source(500)
    for root in (joinpath(P2MD,"s2-allowance"),joinpath(P2S2.ROOT,"artifacts/p2_remaining_qualification_20261022/heldout-500"))
        for (dir,_,files) in walkdir(root)
            "summary.json" in files && "point-solve.json" in files || continue
            d=P2S2.JSON.parsefile(joinpath(dir,"summary.json"));get(d,"accepted",false)||continue
            p=P2S2.el_read_point(dir;stage="solve")
            P2S2.DroopOPF._json_data(p.study.case.controls)==P2S2.DroopOPF._json_data(seed.study.case.controls)||error("Shared curve drift")
            merge!(seed.states,p.states)
        end
    end
    seed
end
function p2_exhaustive_priorities(folder;seconds=180.,limited_memory=true,partitioned=true)
    x=P2S2.p2_context(500);seed=p2_priority_seed500();rows=Any[]
    factors=(1.,.9,.925,.95,.975,1.025,1.05,1.05625,1.0625)
    P2S2.fd_save(joinpath(folder,"protocol.json"),(;factors,events=[e.id for e in x.events],
        objective_order=("shedding","dr","emergency","loss"),shared_curves_frozen=true,preventive_base_free=true,
        method="Exact demand decomposition with fixed common curves; every connected outage is present in every objective stage",
        objective_scope="All-demand optimization conditional on previously qualified shared curves; not a free-curve optimum",
        equipment="Unchanged S2 corrective continuous controls, absolute bounds, no movement cap",seconds,
        hardware_memory_bytes=Sys.total_memory(),limited_memory,partitioned,failure_policy="Checkpoint and stop at unresolved full objective stage; no subset substituted for this gate"))
    for f in factors
        caps=Dict{String,Float64}();warm=seed
        for kind in ("shedding","dr","emergency","loss")
            dest=joinpath(folder,"factor-$f/$kind")
            GC.gc()
            a=P2S2.og_attempt(x,dest,(f,),x.events;seed=warm,fixed_controller=true,zero_shedding=false,seconds,retry=limited_memory,partitioned,objective_kind=kind,resource_caps=caps)
            push!(rows,(;factor=f,kind,accepted=a.summary.accepted,path=a.summary.folder,record=a.summary.record))
            P2S2.fd_save(joinpath(folder,"RESULTS.json"),(;rows,complete=length(rows)==length(factors)*4&&all(r.accepted for r in rows),
                free_curves_optimized=false,full_connected_catalogue=true))
            if !a.summary.accepted;return rows;end
            if kind!="loss";caps[kind]=a.summary.record.objective+1e-7;end
            warm=a.point
        end
        merge!(seed.states,warm.states)
    end
    rows
end
