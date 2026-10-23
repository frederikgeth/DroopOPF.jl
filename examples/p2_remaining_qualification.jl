# Fresh qualification campaign. Import does not launch optimization.
include("p2_s2_multidemand.jl")
include("p2_s2_multidemand_frozen.jl")
include("p2_s2_multidemand_polish.jl")
include("p2_s2_multidemand_batched.jl")
const P2Q=get(ENV,"P2_QUALIFICATION_OUTPUT",joinpath(P2S2.ROOT,"artifacts/p2_remaining_qualification_20261022"))
function pq_prepare()
    ispath(P2Q)&&error("Fresh campaign required")
    run(`python3 -B $(joinpath(@__DIR__,"p2_s2_500.py"))`)
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    P2S2.fd_save(joinpath(P2Q,"protocol.json"),(;date="2026-10-22",scope="Remaining bounded P2 qualification attempts",
        heldout_500=(.925,.975,1.025,1.05625),heldout_14=(.925,.975,1.025,1.075),
        equipment="Exact S2 corrective equipment, absolute bounds, no extra movement budget; continuous banks",
        response="Exact S2 proportional compatibility adapter; production limit-aware default unchanged",
        controller_policy="Previously accepted curves frozen during held-out and fixed-base comparisons",
        performance="One warm-up then three rotated paired repetitions; complete phase/wall cost; bounded subset reference distinguished from full network catalogue",
        initialization="flat voltage, validated base, and validated scenario starts; same constraints and fixed preventive base",
        filtering="No skip acceptance under changed corrective/S2 proportional policy; advisory routing compared with exhaustive outcomes",
        objective_scope="Feasibility qualification; resource/loss optimization remains separate unless explicitly completed",
        acceptance="Native success and unchanged independent physical replay; numerical failures unresolved; no global infeasibility inference"))
end
function pq_heldout500()
    source=joinpath(P2MD,"s2-allowance/stage-1/500/progressive/round-1/master/primary")
    md_batch_run(joinpath(P2Q,"heldout-500");source,factors=(.925,.975,1.025,1.05625),allow_shedding=true)
end
include("p2_qualification_attempt.jl")
function pq_source(size)
    if size==14
        P2S2.el_read_point(joinpath(P2CAMPAIGN,"14/full");stage="solve")
    else
        # Merge separately audited scenario starts with identical controller and base per demand.
        lane=joinpath(P2MD,"s2-allowance"); rows=P2S2.JSON.parsefile(joinpath(lane,"RESULTS.json"))["rows"]
        selected=only(r for r in rows if r["factor"]==1.)
        round=last(selected["result"]["rounds"])
        seed=P2S2.el_read_point(joinpath(P2S2.ROOT,round["master"]["folder"]);stage="solve")
        scan=P2S2.JSON.parsefile(joinpath(lane,"stage-$(selected["stage"])/500/progressive/round-$(round["round"])/scan/scan.json"))
        for path in unique(r["path"] for r in scan["rows"] if r["accepted"]&&!isnothing(r["path"]))
            p=P2S2.el_read_point(joinpath(P2S2.ROOT,path);stage="solve");merge!(seed.states,p.states)
        end
        seed
    end
end
function pq_heldout14()
    folder=joinpath(P2Q,"heldout-14");mkpath(folder)
    x=P2S2.p2_context(14);seed=pq_source(14);rows=Any[]
    for f in (.925,.975,1.025,1.075)
        # All 24 outages in one fixed-curve model at each new demand.
        a=P2S2.pq_attempt(x,joinpath(folder,string(f)),(f,),x.events;seed,fixed_controller=true,seconds=60.)
        push!(rows,(;factor=f,accepted=a.summary.accepted,path=a.summary.folder))
        P2S2.fd_save(joinpath(folder,"RESULTS.json"),(;rows,source=joinpath(P2CAMPAIGN,"14/full"),controller_frozen=true))
    end
    rows
end
function pq_benchmarks()
    pq_repair_fullcatalog()
    P2S2.fd_save(joinpath(P2Q,"benchmarks/protocol.json"),(;policies=["scenario","base","neighbor","flat"],
        repetitions=3,warmups=1,primary_seconds=20.,retry_seconds=40.,retry="limited-memory, same initialization and original seed",retry_cost_included=true,
        initialization_source="Previously independently accepted states; neighboring means deterministic previous stored outage at the same demand",
        source_sha256=bytes2hex(P2S2.sha256(read(joinpath(P2S2.ROOT,"examples/p2_qualification_attempt.jl"))))))
    rows=Any[]
    for size in (14,500)
        x=P2S2.p2_context(size);seed=pq_source(size)
        ranked=p2_rank(x,size==14 ? 1. : 1.05)
        # Deterministic mixed sample: highest loading/output and evenly spread catalogue entries.
        ids=unique([e.id for e in ranked[1:4]] ∪ [e.id for e in ranked[1:cld(length(ranked),8):end]])
        events=[e for e in x.events if e.id in ids][1:min(12,length(ids))]
        P2S2.fd_save(joinpath(P2Q,"benchmarks/$size/catalogue.json"),events)
        for rep in 0:3
            policies=circshift(["scenario","base","neighbor","flat"],rep)
            for init in policies
                dest=joinpath(P2Q,"benchmarks/$size/rep-$rep/$init")
                started=time();paths=String[];records=Any[]
                a=P2S2.pq_attempt(x,dest,(1.,),events;seed,fixed_controller=true,fixed_base=true,
                    initialization=init,zero_shedding=size==14,seconds=20.)
                primary_accepted=a.summary.accepted
                push!(paths,a.summary.folder);push!(records,a.summary.record)
                if !primary_accepted
                    # Same declared initialization, independent limited-memory retry; no oracle fallback.
                    a=P2S2.pq_attempt(x,dest*"-retry",(1.,),events;seed,fixed_controller=true,fixed_base=true,
                        initialization=init,zero_shedding=size==14,seconds=40.,retry=true)
                    push!(paths,a.summary.folder);push!(records,a.summary.record)
                end
                push!(rows,(;size,rep,initialization=init,warmup=rep==0,events=[e.id for e in events],
                    wall_seconds=time()-started,process_peak_rss_bytes=Sys.maxrss(),accepted=a.summary.accepted,
                    primary_accepted,paths,records,record=a.summary.record))
                P2S2.fd_save(joinpath(P2Q,"benchmarks/RESULTS.json"),(;rows,repetitions=3,warmup_excluded=true,performance_scope="up-to-12-outage deterministic mixed subset (actual IDs in catalogue), full-size physical network, fixed preventive base/curves; no full-catalogue speedup claim"))
            end
        end
    end
    rows
end
function pq_subset_comparison()
    rows=Any[]
    for size in (14,500)
        x=P2S2.p2_context(size);seed=pq_source(size)
        events=size==14 ? x.events : p2_rank((;x...,seed),1.)[1:12]
        for rep in 0:3
            for method in (iseven(rep) ? ("full","batched") : ("batched","full"))
                started=time();attempts=Any[];paths=String[];accepted=true
                batches=method=="full" ? [events] : [events[i:min(i+1,end)] for i in 1:2:length(events)]
                for (i,batch) in enumerate(batches)
                    dest=joinpath(P2Q,"comparison/$size/rep-$rep/$method/batch-$i")
                    a=P2S2.pq_attempt(x,dest,(1.,),batch;seed,fixed_controller=true,fixed_base=true,
                        zero_shedding=size==14,seconds=30.)
                    push!(attempts,a.summary.record);push!(paths,a.summary.folder);accepted &= a.summary.accepted
                end
                push!(rows,(;size,rep,warmup=rep==0,method,accepted,events=[e.id for e in events],paths,
                    wall_seconds=time()-started,process_peak_rss_bytes=Sys.maxrss(),build_seconds=sum(r.build_seconds for r in attempts),
                    solve_seconds=sum(r.solve_seconds for r in attempts),allocated_bytes=sum(r.allocated_bytes for r in attempts)))
                P2S2.fd_save(joinpath(P2Q,"comparison/RESULTS.json"),(;rows,
                    meaning="Matched full-enumeration versus batched fixed-base feasibility on stated catalogue; 14 full catalogue, 500 12-outage subset. This is not a free-controller progressive/full-master optimization equivalence claim."))
            end
        end
    end
    rows
end
function pq_priorities()
    x=P2S2.p2_context(500);seed=pq_source(500);events=p2_rank((;x...,seed),1.)[1:5]
    caps=Dict{String,Float64}();rows=Any[]
    for kind in ("shedding","dr","emergency","loss")
        a=P2S2.pq_attempt(x,joinpath(P2Q,"priorities/$kind/primary"),(1.,),events;seed,fixed_controller=true,
            zero_shedding=false,seconds=60.,objective_kind=kind,resource_caps=caps)
        paths=[a.summary.folder];primary_accepted=a.summary.accepted
        if !primary_accepted
            warm=!isnothing(a.audit)&&a.audit["physical_valid"] ? a.point : seed
            a=P2S2.pq_attempt(x,joinpath(P2Q,"priorities/$kind/retry"),(1.,),events;seed=warm,fixed_controller=true,
                zero_shedding=false,seconds=120.,retry=true,objective_kind=kind,resource_caps=caps)
            push!(paths,a.summary.folder)
        end
        push!(rows,(;kind,accepted=a.summary.accepted,primary_accepted,paths,path=a.summary.folder,objective=a.summary.record.objective))
        P2S2.fd_save(joinpath(P2Q,"priorities/RESULTS.json"),(;rows,scope="5-outage fixed-curve shedding/DR/emergency-departure/loss priority pilot; not exhaustive or a multi-demand priority optimum"))
        a.summary.accepted||break
        seed=a.point
        kind in ("shedding","dr","emergency")&&(caps[kind]=Float64(a.summary.record.objective)+1e-7)
    end
    rows
end
function pq_filter_diagnostics()
    rows=Any[]
    for size in (14,500)
        x=P2S2.p2_context(size);seed=pq_source(size);state=seed.states[(1.,:base)]
        c=P2S2.with_shunt_settings(P2S2.with_tap_settings(seed.study.case,state.taps),state.banks)
        try
            t=@elapsed ds=P2S2.filter_contingencies(c,state.state;participation=seed.study.participation)
            eligible=Set(e.id for e in x.events)
            decisions=[d for d in ds if d.contingency_id in eligible]
            push!(rows,(;size,diagnostic_completed=true,seconds=t,decisions,
                ranking_order=[e.id for e in p2_rank((;x...,seed),1.)],
                eligible_outages=length(eligible),advisory_screened=count(d->d.action==:screened,decisions),
                operational_screened=0,operational_exact=length(eligible),
                unsupported_reason="Corrective equipment/S2 proportional response is outside the response-guard qualification contract; retain all exact solves",
                empirical_failure_recall=nothing,reason="All reference outcomes accepted; no failure examples to establish discriminatory recall"))
        catch err
            push!(rows,(;size,diagnostic_completed=false,error=sprint(showerror,err),operational_screened=0,operational_exact=length(x.events)))
        end
    end
    P2S2.fd_save(joinpath(P2Q,"filtering/RESULTS.json"),(;rows,default_enabled=false,
        meaning="Advisory routing diagnostics only; conservative exact fallback under unsupported policy; no general guard qualification"));rows
end
function pq_progressive_reference()
    x=P2S2.p2_context(500);seed=pq_source(500);ranked=p2_rank((;x...,seed),1.);events=ranked[1:12]
    P2S2.fd_save(joinpath(P2Q,"progressive-reference/catalogue.json"),events)
    rows=Any[]
    for rep in 0:3
        for method in (iseven(rep) ? ("full","progressive") : ("progressive","full"))
            anchor=(;study=seed.study,states=copy(seed.states));started=time();paths=String[];accepted=false;rounds=Any[]
            if method=="full"
                a=P2S2.pq_attempt(x,joinpath(P2Q,"progressive-reference/rep-$rep/full"),(1.,),events;
                    seed=anchor,fixed_controller=true,zero_shedding=false,seconds=45.)
                push!(paths,a.summary.folder);accepted=a.summary.accepted
            else
                included=Set(e.id for e in events[1:2])
                for round in 1:3
                    subset=[e for e in events if e.id in included]
                    a=P2S2.pq_attempt(x,joinpath(P2Q,"progressive-reference/rep-$rep/progressive/round-$round/master"),(1.,),subset;
                        seed=anchor,fixed_controller=true,zero_shedding=false,seconds=45.)
                    push!(paths,a.summary.folder);a.summary.accepted||break
                    bad=Symbol[]
                    for (i,e) in enumerate(events)
                        e.id in included&&continue
                        b=P2S2.pq_attempt(x,joinpath(P2Q,"progressive-reference/rep-$rep/progressive/round-$round/scan-$i"),(1.,),[e];
                            seed=a.point,fixed_controller=true,fixed_base=true,zero_shedding=false,seconds=10.)
                        push!(paths,b.summary.folder);b.summary.accepted||push!(bad,e.id)
                    end
                    push!(rounds,(;round,included=collect(included),unresolved=bad))
                    if isempty(bad);accepted=true;break;end
                    anchor=a.point;union!(included,bad)
                end
            end
            push!(rows,(;rep,warmup=rep==0,method,accepted,wall_seconds=time()-started,paths,rounds))
            P2S2.fd_save(joinpath(P2Q,"progressive-reference/RESULTS.json"),(;rows,case_size=500,events=[e.id for e in events],
                fixed_controller=true,fixed_base=false,objective="feasibility",scope="12-outage optimization reference on full-size network; 389-outage coverage supplied separately, not claimed here"))
        end
    end
    rows
end
function pq_design14()
    x=P2S2.p2_context(14);x=(;x...,seed=pq_source(14));factors=(.9,.95,1.,1.05,1.1);rows=Any[]
    for rep in 0:3
        for method in (iseven(rep) ? ("full","progressive") : ("progressive","full"))
            folder=joinpath(P2Q,"design-14/rep-$rep/$method");mkpath(joinpath(folder,"14"))
            P2S2.fd_save(joinpath(folder,"14/catalogue.json"),x.events)
            started=time()
            if method=="full"
                a=p2_checked_attempt(x,joinpath(folder,"14/full"),factors,x.events;seconds=60.)
                accepted=a.summary.accepted;objective=a.summary.record.objective
            else
                r=p2_progressive(x,factors,joinpath(folder,"14/progressive");max_states=150,seconds=30.,scan_seconds=5.)
                accepted=r.accepted;objective=isempty(r.rounds) ? nothing : last(r.rounds).master.record.objective
                if !isempty(r.rounds)
                    run(`python3 -B $(joinpath(P2S2.ROOT,"examples/audit_p2_s2_campaign.py")) $folder 14`)
                end
            end
            push!(rows,(;rep,warmup=rep==0,method,accepted,objective,wall_seconds=time()-started,path=relpath(folder,P2S2.ROOT)))
            P2S2.fd_save(joinpath(P2Q,"design-14/RESULTS.json"),(;rows,factors,case_size=14,scope="Shared free-curve loss design: 125-state full reference versus progressive addition with exhaustive final scans; local solutions, not equal-global-optimum proof"))
        end
    end
    rows
end
function pq_fullcatalog_repeats()
    x=P2S2.p2_context(500);seed=pq_source(500);events=p2_rank((;x...,seed),1.);rows=Any[]
    P2S2.fd_save(joinpath(P2Q,"fullcatalog-repeat/protocol.json"),(;repetitions=3,batch_size=2,factor=1.,
        controls_frozen=true,base_frozen=true,base_reference=seed.states[(1.,:base)],controller_reference=seed.study.case.controls,catalogue=[e.id for e in events],initialization="Matching independently validated scenario starts",
        warmup="Prior initialization/comparison calls; no new cold-start claim",fresh_native_solves=true,
        primary_seconds=10.,retry_seconds=20.,all_389_required=true))
    for rep in 1:3
        started=time();attempts=Any[];accepted_ids=Symbol[];paths=String[]
        for (i,j) in enumerate(1:2:length(events))
            batch=events[j:min(j+1,end)]
            attempt(args...;kwargs...)=P2S2.pq_attempt(args...;zero_shedding=false,kwargs...)
            a=md_checked(attempt,x,joinpath(P2Q,"fullcatalog-repeat/rep-$rep/batch-$i"),(1.,),batch;
                seed,fixed_controller=true,fixed_base=true,seconds=10.)
            push!(paths,a.summary.folder);push!(attempts,a.summary.record)
            a.summary.accepted&&append!(accepted_ids,[e.id for e in batch])
            P2S2.fd_save(joinpath(P2Q,"fullcatalog-repeat/rep-$rep/checkpoint.json"),(;rep,completed_outages=min(j+1,length(events)),
                accepted_ids,paths,wall_seconds=time()-started))
        end
        push!(rows,(;rep,accepted=length(accepted_ids)==389,accepted_outages=length(accepted_ids),
            wall_seconds=time()-started,process_peak_rss_bytes=Sys.maxrss(),paths,
            final_attempt_build_seconds=sum(r.build_seconds for r in attempts),final_attempt_solve_seconds=sum(r.solve_seconds for r in attempts),
            meaning="Wall cost includes failed primary calls/retries; phase sums above are final attempts only; all raw calls retained"))
        P2S2.fd_save(joinpath(P2Q,"fullcatalog-repeat/RESULTS.json"),(;rows,factor=1.,outages=389,states_per_pass=390,
            scope="Fresh complete connected-catalogue fixed-base/controller warm feasibility evaluations; not monolithic free-curve optimization"))
    end
    rows
end
function pq_repair_fullcatalog()
    file=joinpath(P2Q,"fullcatalog-repeat/RESULTS.json");isfile(file)||return
    saved=P2S2.JSON.parsefile(file);x=P2S2.p2_context(500);seed=pq_source(500)
    for row in saved["rows"]
        row["accepted"]&&continue
        started=time();unresolved=Symbol[]
        for path in row["paths"]
            folder=joinpath(P2S2.ROOT,path)
            P2S2.JSON.parsefile(joinpath(folder,"summary.json"))["accepted"]&&continue
            append!(unresolved,Symbol.(P2S2.JSON.parsefile(joinpath(folder,"contract.json"))["outages"]))
        end
        for id in unique(unresolved)
            e=only(e for e in x.events if e.id==id)
            attempt(args...;kwargs...)=P2S2.pq_attempt(args...;zero_shedding=false,kwargs...)
            dest=joinpath(P2Q,"fullcatalog-repeat/rep-$(row["rep"])/singleton-$id")
            a=md_checked(attempt,x,dest,(1.,),[e];seed,fixed_controller=true,fixed_base=true,seconds=10.)
            push!(row["paths"],a.summary.folder)
        end
        accepted=Set{String}()
        for path in row["paths"]
            folder=joinpath(P2S2.ROOT,path)
            P2S2.JSON.parsefile(joinpath(folder,"summary.json"))["accepted"]||continue
            union!(accepted,P2S2.JSON.parsefile(joinpath(folder,"contract.json"))["outages"])
        end
        row["initial_wall_seconds"]=row["wall_seconds"];row["fallback_wall_seconds"]=time()-started
        row["wall_seconds"]+=row["fallback_wall_seconds"];row["accepted_outages"]=length(accepted);row["accepted"]=length(accepted)==389
        row["deferred_singleton_fallback"]=true
        P2S2.fd_save(file,saved)
    end
end

include(joinpath(P2S2.ROOT,"examples/p2_repair_repeated_outage.jl"))
include(joinpath(P2S2.ROOT,"examples/p2_flat_singleton_recovery.jl"))
include(joinpath(P2S2.ROOT,"examples/p2_warm_start_recovery.jl"))

"""Run all declared bounded qualification stages into a fresh output directory.
Set ENV["P2_QUALIFICATION_OUTPUT"] before import to choose a different directory.
"""
function pq_remaining_run()
    pq_prepare();pq_heldout500();pq_heldout14();pq_filter_diagnostics()
    pq_fullcatalog_repeats();pq_repair_fullcatalog();pq_repair_repeated_outage();pq_benchmarks()
    pq_subset_comparison();pq_progressive_reference();pq_priorities();pq_design14();pq_flat_singleton_recovery();pq_warm_start_recovery()
    # Numerical outputs are separate from local CI/documentation checks.
    P2S2.fd_save(joinpath(P2Q,"numerical-stages-complete.json"),(;complete=true,p2_closed=false))
end
