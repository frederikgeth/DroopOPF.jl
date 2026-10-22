# Continue qualification from a saved expanded master without repeating it.
# Importing performs no numerical work. All controls retain the confirmed bounds.
include("s2_arpae500_qualification.jl")

function s2500_reserve_start(source_directory,destination)
    folder=joinpath(S2500_OUT,source_directory);out=joinpath(S2500_OUT,destination);mkpath(out)
    study=read_study(joinpath(folder,"optimized-1.0.json"));seed=read_scopf_result(joinpath(folder,"result-1.0.json"))
    ids=[:base;[c.id for c in study.contingencies]]
    cases=[study.case;[scenario_case(study.case,c) for c in study.contingencies]]
    demand=sum(l.p for l in study.case.loads)
    # Same aggregate initial generation in all states: reserve-proportional Pg
    # satisfies the confirmed linear response rule exactly, before AC restoration.
    target=demand+0.25
    states=Dict{Symbol,Union{Nothing,ACState{Float64}}}();taps=Dict{Symbol,Dict{Int,Float64}}();banks=Dict{Symbol,Dict{Int,Float64}}()
    for (id,c) in zip(ids,cases)
        start=get(seed.states,id,nothing);isnothing(start) && (start=seed.states[:base])
        capacity=sum(g.p_max for g in c.generators if g.available)
        target<capacity || error("Reserve-aware initial target exceeds remaining capacity")
        pg=[g.available ? target*g.p_max/capacity : 0. for g in c.generators]
        qg=[g.available ? clamp(start.qg[i],g.q_min,g.q_max) : 0. for (i,g) in enumerate(c.generators)]
        states[id]=ACState(copy(start.vm),copy(start.va),pg,qg)
        oldt=get(seed.tap_settings,id,seed.tap_settings[:base])
        taps[id]=Dict(t.branch_id=>oldt[t.branch_id] for t in DroopOPF._scenario_tap_controls(study,c))
        banks[id]=copy(get(seed.shunt_settings,id,seed.shunt_settings[:base]))
    end
    deltas=Dict(id=>target-sum(states[:base].pg[i] for (i,g) in enumerate(c.generators) if g.available)
        for (id,c) in zip(ids[2:end],cases[2:end]))
    result=SCOPFResult(states,deltas,target-demand,:NOT_RUN,:NO_SOLUTION,study.mode,:smooth,
        1e-6,1e-6,1e-6,"analytical reserve initialization",study.reactive_assignments,taps,banks,
        study.tap_controls,study.shunt_controls,study.control_policy)
    write_study(joinpath(out,"optimized-1.0.json"),study);write_scopf_result(joinpath(out,"result-1.0.json"),result)
    fd_save(joinpath(out,"summary.json"),(;accepted=false,solver="initialization",initialization_only=true,
        source_directory,nominal_target_pu=target,initial_loss_allowance_mw=25.,
        claim="Numerical start only. No AC-feasibility or optimality claim; all variables remain free during the subsequent design solve."))
    destination
end

function s2500_continue(confirmation;solver=:madnlp,seed_directory,
    label="expanded-madnlp",factors=(1.,),frozen=false,load_scale=1.,max_rounds=6)
    isempty(strip(confirmation)) && error("Confirmed scope required")
    1. in factors || error("The nominal objective block is required")
    folder=joinpath(S2500_OUT,seed_directory)
    seedstudy=read_study(joinpath(folder,"optimized-1.0.json"))
    seed=read_scopf_result(joinpath(folder,"result-1.0.json"))
    seedrecord=JSON.parsefile(joinpath(folder,"summary.json"))
    original=DroopOPF._copy_study(seedstudy;case=DroopOPF._feasibility_scaled_case(seedstudy.case,load_scale))
    seedstudy=DroopOPF._copy_study(seedstudy;case=original.case)
    events=eligible_contingencies(contingency_catalog(original.case))
    full=DroopOPF._copy_study(original;contingencies=events)
    controls=frozen ? DroopControl[] : s214_multi_controls(fd_inputs(500).base)
    angles=fd_inputs(500).angles;seeds=Dict(f=>seed for f in factors)
    working=Set(c.id for c in seedstudy.contingencies);rounds=Any[];accepted=false;selected=nothing
    mkpath(S2500_QUAL)
    paths=["examples/s2_arpae500_followup.jl","examples/s2_arpae500_qualification.jl",
        "examples/s2_arpae500_recovery.jl","examples/s2_arpae500_campaign.jl","Project.toml","Manifest.toml"]
    append!(paths,[relpath(joinpath(folder,file),FD_ROOT) for file in ("optimized-1.0.json","result-1.0.json","summary.json")])
    fd_save(joinpath(S2500_QUAL,"protocol-$label.json"),(;confirmation,solver,seed_directory,factors,frozen,load_scale,max_rounds,
        free_shared_droop_parameters=2*length(controls),tap_controls=full.tap_controls,shunt_controls=full.shunt_controls,control_policy=full.control_policy,
        coverage="All 389 connected outages at every declared factor; 255 islanding outages remain separate",
        maximum_failed_events_per_factor_per_round=4,
        run_source_hashes=Dict(p=>bytes2hex(sha256(read(joinpath(FD_ROOT,p)))) for p in paths)))
    for round in 1:max_rounds
        prefix="qualification/$label/round-$round"
        master=DroopOPF._copy_study(full;contingencies=filter(c->c.id in working,events))
        reuse=round==1 && factors==(1.,) && load_scale==1. && seedrecord["accepted"] && seedrecord["solver"]==string(solver)
        lane=if reuse
            (;record=seedrecord,study=seedstudy,results=Dict(1.0=>seed))
        else
            s2500_targeted_attempt(prefix*"/master",master,controls,seedstudy,seeds,angles;
                solver,factors,normalization=solver!=:ccopt,retry=true,mu=1e-6,scheduled=true)
        end
        if !lane.record["accepted"]
            warm=all(haskey(lane.results,f) && !isnothing(lane.results[f].states[:base]) for f in factors) ? lane.results : seeds
            lane=s2500_targeted_attempt(prefix*"/retry-master",master,controls,lane.study,warm,angles;
                solver,factors,normalization=false,retry=true,mu=1e-10,scheduled=false)
        end
        scans=Any[];failed=Symbol[]
        if lane.record["accepted"]
            for f in factors
                st=DroopOPF._copy_study(lane.study;case=DroopOPF._feasibility_scaled_case(lane.study.case,f),contingencies=events)
                scan=s2500_scan(prefix*"/demand-$f",st,lane.results[f],angles;solver)
                append!(failed,scan.failed)
                push!(scans,(;factor=f,accepted=scan.accepted,exhaustive=scan.exhaustive,evaluated=length(scan.rows),failed=scan.failed))
            end
            seedstudy=lane.study;seeds=lane.results
        end
        accepted=lane.record["accepted"] && length(scans)==length(factors) && all(s.accepted for s in scans)
        selected=accepted ? lane.record["name"] : nothing
        push!(rounds,(;round,master=lane.record,working_outages=sort(collect(working);by=string),scans))
        fd_save(joinpath(S2500_QUAL,"summary-$label.json"),(;rounds,accepted,selected,solver,factors,frozen,load_scale,full_n1_accepted=false))
        accepted && break
        lane.record["accepted"] || break
        old=length(working);union!(working,failed)
        length(working)>old || break
    end
    fd_save(joinpath(S2500_QUAL,"STATUS-$label.json"),(;accepted,selected,solver,factors,frozen,load_scale,
        status=accepted ? "qualified_connected_sampled_scope" : "unqualified_after_bounded_rounds",full_n1_accepted=false))
    (;accepted,selected)
end

if abspath(PROGRAM_FILE)==(@__FILE__)
    length(ARGS)==2 || error("Supply confirmation and expanded seed directory")
    s2500_continue(ARGS[1];seed_directory=ARGS[2])
end
