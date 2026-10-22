# Resume validated scan rows, and amortize model/IO overhead over small outage batches.
# Every batch freezes the same controller/base; failed batches split into singletons.
function md_batch_scan(attempt,x,point,factors,folder;batch_size=2)
    file=joinpath(folder,"scan.json")
    rows=isfile(file) ? Any[P2S2.JSON.parsefile(file)["rows"]...] : Any[]
    getrow(r,k)=r isa AbstractDict ? r[string(k)] : getproperty(r,k)
    seen=Set(Symbol(getrow(r,:event)) for r in rows)
    warm=point
    for r in rows
        getrow(r,:accepted) || continue
        path=getrow(r,:path);isnothing(path)&&continue
        previous=P2S2.el_read_point(joinpath(P2S2.ROOT,path);stage="solve")
        merge!(warm.states,previous.states)
    end
    pending=[e for e in p2_rank(x,.9) if !(e.id in seen)]
    checkpoint()=P2S2.fd_save(file,(;rows,complete=length(rows)==length(x.events),accepted=length(rows)==length(x.events)&&all(getrow(r,:accepted) for r in rows)))
    fresh=eltype(x.events)[]
    for e in pending
        if all(haskey(point.states,(f,e.id)) for f in factors)
            push!(rows,(;event=e.id,accepted=true,route="independently audited master witness",path=nothing))
        else
            push!(fresh,e)
        end
    end
    checkpoint()
    serial=length(filter(n->startswith(n,"batch-"),isdir(folder) ? readdir(folder) : String[]))
    for i in 1:batch_size:length(fresh)
        serial+=1;batch=fresh[i:min(i+batch_size-1,length(fresh))]
        a=md_checked(attempt,x,joinpath(folder,"batch-$serial"),factors,batch;seed=warm,fixed_controller=true,fixed_base=true,seconds=20.)
        if a.summary.accepted
            merge!(warm.states,a.point.states)
            for e in batch;push!(rows,(;event=e.id,accepted=true,route="fresh independently audited batch",path=a.summary.folder));end
        else
            for e in batch
                b=md_checked(attempt,x,joinpath(folder,"split-$serial-$(e.id)"),factors,[e];seed=warm,fixed_controller=true,fixed_base=true,seconds=10.)
                b.summary.accepted && merge!(warm.states,b.point.states)
                push!(rows,(;event=e.id,accepted=b.summary.accepted,route="singleton after unresolved batch",path=b.summary.folder))
                checkpoint()
            end
        end
        checkpoint();println("BATCH SCAN ",factors," ",length(rows),"/389");flush(stdout)
    end
    (;rows,accepted=all(getrow(r,:accepted) for r in rows),warm)
end
function md_saved_master(folder)
    for name in ("primary","retry")
        p=joinpath(folder,name,"summary.json")
        isfile(p) && P2S2.JSON.parsefile(p)["accepted"] && return p
    end
    nothing
end
function md_batch_stage(x,factor,folder;seed,attempt=P2S2.p2_attempt)
    mkpath(joinpath(folder,"500"));P2S2.fd_save(joinpath(folder,"500/catalogue.json"),x.events)
    ranked=p2_rank(x,.9);included=Set([:branch_36,:branch_219,:branch_562,:generator_14,:generator_60])
    rounds=Any[];dest=joinpath(folder,"500/progressive")
    curves=seed.study.case.controls
    for round in 1:4
        events=[e for e in ranked if e.id in included];mf=joinpath(dest,"round-$round/master")
        old=md_saved_master(mf)
        if !isnothing(old)
            d=P2S2.JSON.parsefile(old);a=(;summary=(;accepted=true,folder=d["folder"],record=d["record"]),point=P2S2.el_read_point(dirname(old);stage="solve"))
        else
            ispath(mf)&&(mf*= "-resumed")
            a=md_checked(attempt,x,mf,(factor,),events;seed,fixed_controller=true,seconds=60.)
        end
        if !a.summary.accepted
            result=(;accepted=false,status="fixed_controller_master_unresolved",rounds,attempt=a.summary)
            P2S2.fd_save(joinpath(dest,"summary.json"),result);return (;result,seed)
        end
        @assert P2S2.DroopOPF._json_data(a.point.study.case.controls)==P2S2.DroopOPF._json_data(curves)
        scan=md_batch_scan(attempt,x,a.point,(factor,),joinpath(dest,"round-$round/scan"))
        value(r,k)=r isa AbstractDict ? r[string(k)] : getproperty(r,k)
        failures=[Symbol(value(r,:event)) for r in scan.rows if !value(r,:accepted)]
        push!(rounds,(;round,included=[e.id for e in events],master=a.summary,accepted=scan.accepted,failures))
        result=(;accepted=scan.accepted,status=scan.accepted ? "exhaustive_connected_audit_passed" : "continuing",rounds)
        P2S2.fd_save(joinpath(dest,"summary.json"),result)
        if scan.accepted
            run(`python3 -B $(joinpath(@__DIR__,"audit_p2_s2_batched.py")) $folder 500`)
            return (;result,seed=scan.warm)
        end
        seed=scan.warm;union!(included,first(failures,min(4,length(failures))))
    end
    result=(;accepted=false,status="round_bound",rounds)
    P2S2.fd_save(joinpath(dest,"summary.json"),result);(;result,seed)
end
function md_batch_run(folder;source=nothing,source_stage="solve",factors=(.9,.95,1.,1.05,1.0625,1.075,1.1),allow_shedding=false)
    protocol=joinpath(folder,"protocol.json")
    if isfile(protocol)
        raw=P2S2.JSON.parsefile(protocol);source=raw["source"];source_stage=get(raw,"source_stage","solve")
        factors=Tuple(Float64.(raw["factors"]));allow_shedding=!raw["zero_shedding"]
    else
        isnothing(source)&&error("Specify a shared controller source")
        P2S2.fd_save(protocol,(;source,source_stage,factors,zero_shedding=!allow_shedding,shared_controller=true,
            method="fixed shared curves, demand-specific preventive dispatch, batched exhaustive outage audit"))
    end
    P2S2.fd_save(joinpath(folder,"batch-protocol.json"),(;batch_size=2,batch_seconds=20.,retry_seconds=40.,singleton_fallback=true,
        physical_policy_changed=false,completed_rows_reused_only_after_independent_audit=true))
    x=md_seed();seed=P2S2.el_read_point(source;stage=source_stage);curves=seed.study.case.controls;rows=Any[]
    for (i,f) in enumerate(factors)
        a=md_batch_stage(x,f,joinpath(folder,"stage-$i");seed,attempt=allow_shedding ? md_shed_attempt : md_zero_attempt)
        push!(rows,(;stage=i,factor=f,result=a.result))
        P2S2.fd_save(joinpath(folder,"RESULTS.json"),(;rows,s2_resumed=false,p2_closed=false))
        run(`python3 -B $(joinpath(@__DIR__,"audit_p2_s2_multidemand.py")) $folder`)
        a.result.accepted || break
        @assert P2S2.DroopOPF._json_data(a.seed.study.case.controls)==P2S2.DroopOPF._json_data(curves);merge!(seed.states,a.seed.states)
    end
    rows
end
