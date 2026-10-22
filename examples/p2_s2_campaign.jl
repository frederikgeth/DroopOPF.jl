# Resource-bounded P2 orchestration; no work is launched by import.
isdefined(@__MODULE__, :P2S2) || include("p2_s2_numerics.jl")
using .P2S2
const P2CAMPAIGN=joinpath(@__DIR__,"..","artifacts","p2_s2_implementation_20261022")
function p2_rank(x,factor)
    s=x.seed.states[(factor,:base)]
    c=P2S2.with_tap_settings(x.study.case,s.taps)
    flow=P2S2.branch_flows(c.network,s.state)
    scores=Dict{Symbol,Float64}()
    for e in x.events
        if !isempty(e.generator_ids)
            scores[e.id]=sum(s.state.pg[i] for (i,g) in enumerate(c.generators) if g.id in e.generator_ids)
        else
            scores[e.id]=maximum(max(abs(flow.from[i]),abs(flow.to[i]))/b.thermal_limit for (i,b) in enumerate(c.network.branches) if b.id in e.branch_ids)
        end
    end
    sort(x.events;by=e->(-scores[e.id],string(e.id)))
end
function p2_checked_attempt(x,folder,factors,events;seed=x.seed,fixed_controller=false,fixed_base=false,seconds=30.)
    a=P2S2.p2_attempt(x,joinpath(folder,"primary"),factors,events;seed,fixed_controller,fixed_base,seconds)
    a.summary.accepted && return a
    P2S2.p2_attempt(x,joinpath(folder,"retry"),factors,events;seed=isnothing(a.point) ? seed : a.point,
        fixed_controller,fixed_base,seconds=2seconds,retry=true)
end
function p2_scan(x,point,factors,folder;seconds=5.,reuse_master=true)
    mkpath(folder);rows=Any[];warm=point
    for e in p2_rank(x,first(factors))
        if reuse_master && all(haskey(point.states,(f,e.id)) for f in factors)
            push!(rows,(;event=e.id,accepted=true,route="independently audited master witness",path=nothing))
        else
            a=p2_checked_attempt(x,joinpath(folder,string(e.id)),factors,[e];seed=warm,
                fixed_controller=true,fixed_base=true,seconds)
            # Keep the candidate's base/controller; accepted scenario states are starts only.
            if a.summary.accepted
                merge!(warm.states,a.point.states)
            end
            push!(rows,(;event=e.id,accepted=a.summary.accepted,route="fresh exact solve",path=a.summary.folder))
        end
        P2S2.fd_save(joinpath(folder,"scan.json"),(;rows,complete=length(rows)==length(x.events),accepted=length(rows)==length(x.events)&&all(r.accepted for r in rows)))
        length(rows)%20==0 && (println("SCAN ",x.size," ",length(rows),"/",length(x.events));flush(stdout))
    end
    (;rows,accepted=all(r.accepted for r in rows),warm)
end
function p2_progressive(x,factors,folder;max_rounds=8,max_states=150,seconds=30.,scan_seconds=5.)
    mkpath(folder);ranked=p2_rank(x,first(factors));included=Set(e.id for e in ranked[1:2]);seed=x.seed;rounds=Any[]
    for round in 1:max_rounds
        events=[e for e in ranked if e.id in included]
        needed=length(factors)*(1+length(events))
        if needed>max_states
            result=(;accepted=false,status="resource_bound",required_states=needed,max_states,rounds)
            P2S2.fd_save(joinpath(folder,"summary.json"),result);return result
        end
        a=p2_checked_attempt(x,joinpath(folder,"round-$round","master"),factors,events;seed,seconds)
        if !a.summary.accepted
            result=(;accepted=false,status="master_unresolved",rounds,attempt=a.summary)
            P2S2.fd_save(joinpath(folder,"summary.json"),result);return result
        end
        scan=p2_scan(x,a.point,factors,joinpath(folder,"round-$round","scan");seconds=scan_seconds)
        failures=[r.event for r in scan.rows if !r.accepted]
        push!(rounds,(;round,included=[e.id for e in events],master=a.summary,accepted=scan.accepted,failures))
        if scan.accepted
            result=(;accepted=true,status="exhaustive_connected_audit_passed",rounds)
            P2S2.fd_save(joinpath(folder,"summary.json"),result);return result
        end
        for id in first(failures,min(4,length(failures)));push!(included,id);end
        seed=scan.warm
        P2S2.fd_save(joinpath(folder,"summary.json"),(;accepted=false,status="continuing",rounds))
    end
    result=(;accepted=false,status="round_bound",rounds)
    P2S2.fd_save(joinpath(folder,"summary.json"),result);result
end
function p2_prepare(folder=P2CAMPAIGN)
    isfile(joinpath(folder,"protocol.json")) && error("Do not overwrite campaign protocol")
    mkpath(folder)
    P2S2.fd_save(joinpath(folder,"protocol.json"),(;date="2026-10-22",scope="Initial exact-S2 P2 implementation and bounded qualification",
        active_response="S2 stored proportional equality; isolated adapter; library default unchanged",
        equipment="S2 corrective selections and absolute bounds; continuous banks; no extra movement budgets",
        cases=(;small=(;buses=14,factors=[.9,.95,1.,1.05,1.1],connected_outages=24,normal_limits=true),
            large=(;buses=500,factors=[1.05],connected_outages=389,emergency=true,zero_shedding=true)),
        objectives="14 nominal base loss; 500 feasibility pilot before S2 resource/loss priorities",
        initialization="previous S2 accepted witnesses, identical sources for both methods; not unseen-start evidence",
        full_master_state_budget=(;small=150,large=12),progressive_rounds=8,addition_batch=4,
        acceptance="native success plus independent full-network replay; final exhaustive connected audit; island scope not expanded",
        comparison="initial single-pass development timings; no statistical speedup or P2 closure claim",
        source_hashes=Dict(relpath(p,P2S2.ROOT)=>bytes2hex(P2S2.sha256(read(p))) for p in [(@__FILE__),joinpath(@__DIR__,"p2_s2_numerics.jl"),joinpath(@__DIR__,"audit_p2_s2_numerics.py")])))
end

"""Run the declared initial comparison into a fresh directory. S2 stays unchanged."""
function p2_run(folder; sizes=(14,500))
    ispath(folder) && error("Choose a fresh campaign directory")
    all(n in (14,500) for n in sizes) || error("Supported sizes: 14 and 500")
    run(`python3 -B $(joinpath(@__DIR__,"p2_s2_500.py"))`)
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    p2_prepare(folder)
    for n in sizes
        x=P2S2.p2_context(n);factors=n==14 ? (.9,.95,1.,1.05,1.1) : (1.05,)
        mkpath(joinpath(folder,string(n)))
        P2S2.fd_save(joinpath(folder,string(n),"catalogue.json"),x.events)
        if n==14
            P2S2.p2_attempt(x,joinpath(folder,"14","full"),factors,x.events;seconds=60.)
        else
            mkpath(joinpath(folder,"500"))
            P2S2.fd_save(joinpath(folder,"500","full-resource-bound.json"),
                (;status="not_run_resource_bound",required_states=390,max_states=12,
                physical_infeasibility_proven=false))
        end
        result=p2_progressive(x,factors,joinpath(folder,string(n),"progressive");
            max_states=n==14 ? 150 : 12,seconds=30.,scan_seconds=5.)
        if !isempty(result.rounds)
            run(`python3 -B $(joinpath(@__DIR__,"audit_p2_s2_campaign.py")) $folder $n`)
        end
    end
end
