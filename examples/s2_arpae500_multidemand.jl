# Bounded shared-controller qualification at the five declared S1/S2 demands.
# All equipment remains corrective within the separately confirmed 500-bus bounds.
include("s2_arpae500_linear_recovery.jl")

function s2500_demand_seed(study,seed,f)
    st=DroopOPF._copy_study(study;case=DroopOPF._feasibility_scaled_case(study.case,f))
    ids=[:base;[c.id for c in st.contingencies]]
    cases=[st.case;[scenario_case(st.case,c) for c in st.contingencies]]
    target=sum(l.p for l in st.case.loads)+.25
    states=Dict{Symbol,Union{Nothing,ACState{Float64}}}();taps=Dict{Symbol,Dict{Int,Float64}}();banks=Dict{Symbol,Dict{Int,Float64}}()
    for (id,c) in zip(ids,cases)
        prior=get(seed.states,id,seed.states[:base]);isnothing(prior) && (prior=seed.states[:base])
        cap=sum(g.p_max for g in c.generators if g.available)
        target<cap || error("Demand seed exceeds remaining Pmax")
        pg=[g.available ? target*g.p_max/cap : 0. for g in c.generators]
        qg=[g.available ? clamp(prior.qg[i]*f,g.q_min,g.q_max) : 0. for (i,g) in enumerate(c.generators)]
        states[id]=ACState(copy(prior.vm),copy(prior.va),pg,qg)
        old=get(seed.tap_settings,id,seed.tap_settings[:base])
        taps[id]=Dict(t.branch_id=>old[t.branch_id] for t in DroopOPF._scenario_tap_controls(st,c))
        banks[id]=copy(get(seed.shunt_settings,id,seed.shunt_settings[:base]))
    end
    delta=Dict(id=>target-sum(states[:base].pg[i] for (i,g) in enumerate(c.generators) if g.available)
        for (id,c) in zip(ids[2:end],cases[2:end]))
    SCOPFResult(states,delta,.25,:NOT_RUN,:NO_SOLUTION,st.mode,:smooth,1e-6,1e-6,1e-6,
        "reserve-aware demand initialization",st.reactive_assignments,taps,banks,st.tap_controls,st.shunt_controls,st.control_policy)
end

function s2500_multidemand(confirmation;factors=(.9,.95,1.,1.05,1.1),max_rounds=4,max_master_states=40)
    isempty(strip(confirmation)) && error("Confirmed control scope required")
    nominal=JSON.parsefile(joinpath(S2500_QUAL,"summary-expanded-madnlp-reserve.json"))
    nominal["accepted"] || error("Nominal exhaustive gate must pass first")
    dir=joinpath(S2500_OUT,nominal["selected"])
    seedstudy=read_study(joinpath(dir,"optimized-1.0.json"));seed=read_scopf_result(joinpath(dir,"result-1.0.json"))
    events=eligible_contingencies(contingency_catalog(seedstudy.case))
    full=DroopOPF._copy_study(seedstudy;contingencies=events)
    working=Set([:branch_219,:generator_14,:generator_60])
    initial=DroopOPF._copy_study(full;contingencies=filter(c->c.id in working,events))
    seeds=Dict(f=>s2500_demand_seed(initial,seed,f) for f in factors)
    label="multidemand-madnlp";base=joinpath(S2500_QUAL,label);mkpath(base)
    for f in factors;write_scopf_result(joinpath(base,"initial-result-$f.json"),seeds[f]);end
    controls=s214_multi_controls(fd_inputs(500).base);angles=fd_inputs(500).angles
    files=["examples/s2_arpae500_multidemand.jl","examples/s2_arpae500_linear_recovery.jl",
        "examples/s2_arpae500_followup.jl","examples/s2_arpae500_qualification.jl","examples/s2_arpae500_recovery.jl",
        "examples/s2_arpae500_campaign.jl","Project.toml","Manifest.toml"]
    append!(files,[relpath(joinpath(dir,p),FD_ROOT) for p in ("optimized-1.0.json","result-1.0.json","summary.json")])
    fd_save(joinpath(S2500_QUAL,"protocol-$label.json"),(;confirmation,factors,max_rounds,max_master_states,
        initial_outages=sort(collect(working);by=string),free_shared_droop_parameters=102,
        control_policy=full.control_policy,tap_controls=full.tap_controls,shunt_controls=full.shunt_controls,
        master_recovery="MUMPS normalized primary, one UMFPACK physical-coordinate warm retry; 6000 iterations/300 native seconds each",
        initial_states="Pmax-proportional Pg with a 25 MW loss allowance per demand, exact response coupling; no AC feasibility claim",
        coverage="Every one of the 389 connected outages must pass at every training factor; no screening pass and no islanding acceptance",
        held_out_factors=(.925,.975,1.025,1.075),
        run_source_hashes=Dict(p=>bytes2hex(sha256(read(joinpath(FD_ROOT,p)))) for p in files)))
    rounds=Any[];accepted=false;selected=nothing;stop_reason="round_limit"
    for round in 1:max_rounds
        if length(factors)*(1+length(working))>max_master_states
            stop_reason="bounded_master_state_limit";break
        end
        prefix="qualification/$label/round-$round"
        master=DroopOPF._copy_study(full;contingencies=filter(c->c.id in working,events))
        lane=s2500_linear_attempt(prefix*"/master",master,controls,seedstudy,seeds,angles;
            solver=:madnlp,retry=true,factors,normalization=true,linear_solver=MadNLP.MumpsSolver)
        if !lane.record["accepted"]
            warm=all(haskey(lane.results,f) && !isnothing(lane.results[f].states[:base]) for f in factors) ? lane.results : seeds
            lane=s2500_linear_attempt(prefix*"/retry-master",master,controls,lane.study,warm,angles;
                solver=:madnlp,retry=true,factors,normalization=false,linear_solver=MadNLP.UmfpackSolver)
        end
        scans=Any[];failed=Symbol[]
        if lane.record["accepted"]
            for f in factors
                st=DroopOPF._copy_study(lane.study;case=DroopOPF._feasibility_scaled_case(lane.study.case,f),contingencies=events)
                scan=s2500_scan(prefix*"/demand-$f",st,lane.results[f],angles;solver=:madnlp)
                append!(failed,scan.failed)
                push!(scans,(;factor=f,accepted=scan.accepted,exhaustive=scan.exhaustive,evaluated=length(scan.rows),failed=scan.failed))
            end
            seedstudy=lane.study;seeds=lane.results
        end
        push!(rounds,(;round,master=lane.record,working_outages=sort(collect(working);by=string),scans))
        accepted=lane.record["accepted"] && length(scans)==length(factors) && all(s.accepted for s in scans)
        selected=accepted ? lane.record["name"] : nothing
        fd_save(joinpath(S2500_QUAL,"summary-$label.json"),(;rounds,accepted,selected,solver="madnlp",factors,full_n1_accepted=false))
        if accepted;stop_reason="qualified";break;end
        if !lane.record["accepted"];stop_reason="master_failed_bounded_recovery";break;end
        old=length(working);union!(working,failed)
        if length(working)==old;stop_reason="no_new_contingency";break;end
    end
    fd_save(joinpath(S2500_QUAL,"STATUS-$label.json"),(;accepted,selected,stop_reason,
        master_state_limit=max_master_states,factors,full_n1_accepted=false,held_out_qualified=false))
end

if abspath(PROGRAM_FILE)==(@__FILE__)
    length(ARGS)==1 || error("Supply confirmed control scope")
    s2500_multidemand(only(ARGS))
end
