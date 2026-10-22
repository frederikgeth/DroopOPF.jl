# Fresh continuation campaign. Imports never launch optimization.
include("p2_s2_campaign.jl")
const P2MD=joinpath(P2S2.ROOT,"artifacts/p2_s2_multidemand_20261022")
function md_seed()
    x=P2S2.p2_context(500)
    shared=P2S2.el_read_point(joinpath(x.source,"..","joint-ipopt-3d-cap-priorities-emergency-p1");stage="emergency")
    pilot=P2S2.el_read_point(joinpath(P2CAMPAIGN,"500/progressive/round-2/master/primary");stage="solve")
    states=merge(shared.states,pilot.states)
    # Historical 106.25% witness is a numerical start only, never reused as acceptance.
    high=P2S2.el_read_point(joinpath(P2S2.ROOT,"artifacts/s2_scopf/ieee500_native/finish_105_multidemand/continue-10625-feasibility-retry");stage="feasibility")
    merge!(states,high.states)
    seed=(;study=pilot.study,states)
    (;x...,seed)
end
function md_stage(x,factors,folder;seed=x.seed,max_rounds=4,max_states=84)
    mkpath(joinpath(folder,"500"));P2S2.fd_save(joinpath(folder,"500/catalogue.json"),x.events)
    ranked=p2_rank(x,.9)
    included=Set([:branch_36,:branch_219,:branch_562,:generator_14,:generator_60])
    rounds=Any[];dest=joinpath(folder,"500/progressive")
    for round in 1:max_rounds
        events=[e for e in ranked if e.id in included]
        needed=length(factors)*(length(events)+1)
        if needed>max_states
            result=(;accepted=false,status="resource_bound",required_states=needed,max_states,rounds)
            P2S2.fd_save(joinpath(dest,"summary.json"),result);return (;result,seed)
        end
        a=p2_checked_attempt(x,joinpath(dest,"round-$round/master"),factors,events;seed,seconds=90.)
        if !a.summary.accepted
            result=(;accepted=false,status="master_unresolved",rounds,attempt=a.summary)
            P2S2.fd_save(joinpath(dest,"summary.json"),result);return (;result,seed)
        end
        scan=p2_scan(x,a.point,factors,joinpath(dest,"round-$round/scan");seconds=10.)
        failures=[r.event for r in scan.rows if !r.accepted]
        push!(rounds,(;round,included=[e.id for e in events],master=a.summary,accepted=scan.accepted,failures))
        result=(;accepted=scan.accepted,status=scan.accepted ? "exhaustive_connected_audit_passed" : "continuing",rounds)
        P2S2.fd_save(joinpath(dest,"summary.json"),result)
        seed=scan.warm
        if scan.accepted
            run(`python3 -B $(joinpath(@__DIR__,"audit_p2_s2_campaign.py")) $folder 500`)
            return (;result,seed)
        end
        union!(included,first(failures,min(4,length(failures))))
    end
    result=(;accepted=false,status="round_bound",rounds)
    P2S2.fd_save(joinpath(dest,"summary.json"),result);(;result,seed)
end
function md_run(folder=P2MD)
    ispath(folder)&&error("Use a fresh campaign directory")
    run(`python3 -B $(joinpath(@__DIR__,"p2_s2_500.py"))`)
    ENV["NR_ELIMINATION_MODE"]="independent-degree3"
    mkpath(folder)
    ladder=[(.9,.95,1.,1.05),(.9,.95,1.,1.05,1.0625),(.9,.95,1.,1.05,1.0625,1.075),(.9,.95,1.,1.05,1.0625,1.075,1.1)]
    P2S2.fd_save(joinpath(folder,"protocol.json"),(;date="2026-10-22",ladder,
        shared_controller=true,connected_outages_per_demand=389,zero_shedding=true,
        configuration="Exact S2: 131 corrective taps, 11 continuous banks, no extra movement budget; 102 shared droop parameters; Pmax proportional response; S2 emergency and DR bounds",
        objective="feasibility only; no minimum DR/loss or global-optimality claim",
        max_master_states=84,max_rounds=4,master_seconds=90.,retry_master_seconds=180.,scan_seconds=10.,retry_scan_seconds=20.,
        stop="Stop expansion at first unresolved shared stage; retain last exhaustively accepted shared set",
        s2_reference=(;shared_master=[.9,.95,1.],exhaustive_independent=1.05,nonexhaustive_expanded_master=1.0625),
        source_hashes=Dict(relpath(p,P2S2.ROOT)=>bytes2hex(P2S2.sha256(read(p))) for p in [(@__FILE__),joinpath(@__DIR__,"p2_s2_numerics.jl"),joinpath(@__DIR__,"p2_s2_campaign.jl"),joinpath(@__DIR__,"audit_p2_s2_numerics.py"),joinpath(@__DIR__,"audit_p2_s2_campaign.py")])))
    x=md_seed();seed=x.seed;results=Any[]
    for (i,factors) in enumerate(ladder)
        attempt=md_stage(x,factors,joinpath(folder,"stage-$i");seed)
        push!(results,(;stage=i,factors,result=attempt.result))
        P2S2.fd_save(joinpath(folder,"RESULTS.json"),(;results,s2_resumed=false,p2_closed=false))
        attempt.result.accepted || break
        seed=attempt.seed
    end
    results
end
