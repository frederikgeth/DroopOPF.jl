# Lower-bound route: a validated normal-limit, no-relief witness attains the
# nonnegative lower bounds of shedding, DR and emergency departure together.
# Only then is base loss optimized. Every omitted outage still needs native AC.
function p2_zero_resource_progressive(x,seed,folder;factors=(1.,),maxrounds=5,normalized_controls=false,reduced_network=true)
    included=Set((:generator_14,:generator_60,:branch_36,:branch_219,:branch_562));rounds=Any[]
    P2S2.fd_save(joinpath(folder,"protocol.json"),(;factors,all_events=[e.id for e in x.events],initial_events=collect(included),
        shared_curves_free=true,preventive_dispatch_free=true,selected_equipment="Unchanged S2 corrective equipment and absolute bounds",
        target="Zero shedding, zero DR, zero normal-limit departure, then minimum summed base loss",
        justification="All first-three costs are nonnegative. A full zero-cost witness attains their lower bounds; remaining base-loss objective depends only on the master bases.",
        limitation="Subset local optimization is not accepted until every omitted outage passes with the same preventive bases and common curves. Numerical failure is not physical infeasibility.",maxrounds))
    for round in 1:maxrounds
        events=[e for e in x.events if e.id in included];dest=joinpath(folder,"round-$round")
        a=P2S2.og_attempt(x,joinpath(dest,"master"),factors,events;seed,
            fixed_controller=false,normal_outages=true,zero_shedding=true,objective_kind="loss",
            retry=true,partitioned=true,normalized_controls,reduced_network,seconds=120.)
        if !a.summary.accepted
            push!(rounds,(;round,master=a.summary,accepted=false,reason="master_unresolved"))
            P2S2.fd_save(joinpath(folder,"RESULTS.json"),(;accepted=false,rounds));return rounds
        end
        point=a.point;rows=Any[];remaining=[e for e in x.events if !(e.id in included)]
        for i in 1:2:length(remaining)
            batch=remaining[i:min(i+1,end)]
            states=Dict{Tuple{Float64,Symbol},Any}((f,:base)=>point.states[(f,:base)] for f in factors)
            for f in factors,e in batch
                base=point.states[(f,:base)]
                pv=p2_sparse_start(point.study,base,e;factor=f,pv_preparation=true)
                exact=p2_sparse_start(point.study,base,e;factor=f,flat=false,initial_guess=pv.entry)
                states[(f,e.id)]=exact.diagnostic.converged ? exact.entry : pv.entry
            end
            start=(;study=point.study,states)
            b=P2S2.og_attempt(x,joinpath(dest,"scan/batch-$i/primary"),factors,batch;seed=start,
                fixed_controller=true,fixed_base=true,normal_outages=true,zero_shedding=true,
                retry=true,partitioned=true,normalized_controls,reduced_network,seconds=30.)
            paths=[b.summary.folder]
            if !b.summary.accepted
                b=P2S2.og_attempt(x,joinpath(dest,"scan/batch-$i/retry"),factors,batch;seed=start,
                    fixed_controller=true,fixed_base=true,normal_outages=true,zero_shedding=true,
                    retry=true,partitioned=true,normalized_controls,reduced_network,seconds=60.)
                push!(paths,b.summary.folder)
            end
            for e in batch;push!(rows,(;event=e.id,accepted=b.summary.accepted,paths));end
            P2S2.fd_save(joinpath(dest,"scan/RESULTS.json"),(;rows,included=collect(included),complete=length(rows)+length(included)==length(x.events)))
        end
        failures=[r.event for r in rows if !r.accepted]
        push!(rounds,(;round,master=a.summary,accepted=isempty(failures),failures,included=collect(included)))
        P2S2.fd_save(joinpath(folder,"RESULTS.json"),(;accepted=isempty(failures),rounds,
            zero_resource_lower_bound_attained=isempty(failures),objective="Summed base loss conditional on zero resource costs",global_loss_optimum_claimed=false))
        isempty(failures)&&return rounds
        union!(included,first(failures,min(4,length(failures))));seed=point
    end
    rounds
end
