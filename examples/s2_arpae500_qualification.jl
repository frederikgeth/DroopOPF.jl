# Exhaustive connected-outage qualification by contingency addition.
# All numerical solves are serial and checkpointed; importing performs no solve.
include("s2_arpae500_recovery.jl")
const S2500_QUAL=joinpath(S2500_OUT,"qualification")

function s2500_angle_hook(study,angles)
    function hook(model)
        c=scenario_case(study.case,only(study.contingencies));idx=DroopOPF._bus_indices(c.network)
        for b in c.network.branches
            b.available || continue;lo,hi=angles[b.id]
            from=variable_by_name(model,"scenario_2_va[$(idx[b.from_bus])]")
            to=variable_by_name(model,"scenario_2_va[$(idx[b.to_bus])]")
            @constraint(model,lo<=from-to<=hi)
        end
    end
end

function s2500_assess(name,study,base_result,angles;solver=:ipopt,retry=false,prior=nothing)
    folder=joinpath(S2500_OUT,name);mkpath(folder);event=only(study.contingencies)
    base=base_result.states[:base];taps=base_result.tap_settings[:base];banks=base_result.shunt_settings[:base]
    seed=isnothing(prior) ? base_result : prior
    event_taps=get(seed.tap_settings,event.id,taps);event_banks=get(seed.shunt_settings,event.id,banks)
    tc=[TapControl(t.branch_id;lower=t.lower,upper=t.upper,nominal=t.nominal,initial=clamp(get(event_taps,t.branch_id,taps[t.branch_id]),t.lower,t.upper)) for t in study.tap_controls]
    sc=[ShuntControl(t.bank_id;lower=t.lower,upper=t.upper,nominal=t.nominal,initial=clamp(get(event_banks,t.bank_id,banks[t.bank_id]),t.lower,t.upper)) for t in study.shunt_controls]
    study=Study(study.case;contingencies=study.contingencies,mode=study.mode,participation=study.participation,
        redispatch_limits=study.redispatch_limits,reactive_assignments=study.reactive_assignments,
        tap_controls=tc,shunt_controls=sc,control_policy=study.control_policy)
    write_study(joinpath(folder,"input.json"),study)
    fd_save(joinpath(folder,"fixed_base.json"),(;state=base,taps,susceptances=banks))
    starts=s214_starts(study,base,seed);fd_save(joinpath(folder,"starts.json"),starts)
    record=Dict{String,Any}("name"=>name,"event"=>string(event.id),"solver"=>string(solver),"retry"=>retry,
        "accepted"=>false,"native_success"=>false,"physical_valid"=>false,
        "objective_kind"=>"fixed-base feasibility; native schedule-deviation objective is constant",
        "iterations_budget"=>retry ? 1500 : 300,"seconds_budget"=>retry ? 30. : 5.)
    opts=Dict{String,Any}("tol"=>solver==:ccopt ? 1e-11 : 1e-9,"max_iter"=>record["iterations_budget"],"bound_relax_factor"=>0.)
    if solver==:ipopt
        opts["print_level"]=0;opts["max_cpu_time"]=record["seconds_budget"];opts["mu_strategy"]="adaptive"
    else
        opts["max_wall_time"]=record["seconds_budget"]
    end
    if solver==:ccopt
        opts["acceptable_tol"]=1e-11;opts["relaxation_update"]=CCOpt.ScheduledRelaxationUpdate(sigma_init=1e-6,sigma_min=1e-14,target_accuracy=1e-11)
        barrier=MadNLP.MonotoneUpdate(1e-11,10.);barrier.mu_init=retry ? 1e-8 : 1e-6;opts["barrier"]=barrier
        opts["bound_push"]=1e-8;opts["bound_fac"]=1e-8
    end
    fd_save(joinpath(folder,"contract.json"),record);result=nothing
    try
        kw=solver==:ccopt ? (encoding=:complementarity,) : (optimizer_factory=solver==:ipopt ? Ipopt.Optimizer : MadNLP.Optimizer,)
        timed=@timed evaluate_contingencies(study,base;fixed_base_tap_settings=taps,fixed_base_shunt_settings=banks,
            initial_states=starts,smooth_epsilon=1e-6,smooth_reactive_epsilon=1e-6,
            optimizer_attributes=opts,kw...,_model_hook=s2500_angle_hook(study,angles))
        result=timed.value;record["elapsed_seconds"]=timed.time;record["native_status"]=string(result.termination_status)
        record["native_success"]=result.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
        write_scopf_result(joinpath(folder,"result.json"),result)
        report=equilibrium_report(study,result);write_scopf_report(joinpath(folder,"validation.json"),report)
        c=scenario_case(study.case,event);idx=DroopOPF._bus_indices(c.network);state=result.states[event.id]
        margin=isnothing(state) ? -Inf : minimum(min(state.va[idx[b.from_bus]]-state.va[idx[b.to_bus]]-angles[b.id][1],
            angles[b.id][2]-state.va[idx[b.from_bus]]+state.va[idx[b.to_bus]]) for b in c.network.branches if b.available)
        record["physical_valid"]=report.physical_valid && margin>=-1e-6
        record["angle_min_margin_rad"]=margin;record["accepted"]=report.valid && record["physical_valid"]
    catch error
        error isa InterruptException && rethrow();record["error"]=sprint(showerror,error)
    end
    fd_save(joinpath(folder,"summary.json"),record)
    (;record,result)
end

function s2500_scan(prefix,full,base_result,angles;solver=:ipopt,max_failures=4)
    physical=with_shunt_settings(with_tap_settings(full.case,base_result.tap_settings[:base]),base_result.shunt_settings[:base])
    scores=contingency_screening_scores(physical,base_result.states[:base];catalog=contingency_catalog(full.case))
    byid=Dict(c.id=>c for c in full.contingencies);rows=Any[];failed=Symbol[]
    for score in scores
        haskey(byid,score.contingency_id) || continue
        event=byid[score.contingency_id];single=DroopOPF._copy_study(full;contingencies=[event]);name=prefix*"/"*string(event.id)
        path=joinpath(S2500_OUT,name,"summary.json")
        lane=if isfile(path) && JSON.parsefile(path)["accepted"]
            (;record=JSON.parsefile(path),result=read_scopf_result(joinpath(S2500_OUT,name,"result.json")))
        else
            s2500_assess(name,single,base_result,angles;solver)
        end
        primary=lane.record
        if !lane.record["accepted"]
            lane=s2500_assess(name*"-retry",single,base_result,angles;solver,retry=true,prior=lane.result)
        end
        push!(rows,(;event=event.id,primary,final=lane.record));lane.record["accepted"] || push!(failed,event.id)
        fd_save(joinpath(S2500_OUT,prefix,"scan.json"),(;attempts=rows,failed,exhaustive=length(rows)==length(full.contingencies),
            common_base_sha256=bytes2hex(sha256(JSON.json(a500_json(base_result.states[:base]))))))
        if length(rows)%25==0 || !lane.record["accepted"]
            println("SCAN ",prefix," ",length(rows),"/",length(full.contingencies)," failed=",length(failed)," event=",event.id);flush(stdout)
        end
        length(failed)>=max_failures && break
    end
    (;rows,failed,accepted=isempty(failed) && length(rows)==length(full.contingencies),exhaustive=length(rows)==length(full.contingencies))
end

function s2500_qualify(confirmation;solver=:ipopt,factors=(1.,),seed_directory="pilot-ipopt",label="nominal-ipopt",max_rounds=6)
    isempty(strip(confirmation)) && error("User-confirmed equipment scope required")
    mkpath(S2500_QUAL)
    original=read_study(joinpath(S2500_OUT,"pilot_study.json"));events=eligible_contingencies(contingency_catalog(original.case))
    full=DroopOPF._copy_study(original;contingencies=events);controls=s214_multi_controls(fd_inputs(500).base);angles=fd_inputs(500).angles
    directory=joinpath(S2500_OUT,seed_directory);seedstudy=read_study(joinpath(directory,"optimized-1.0.json"))
    seed=read_scopf_result(joinpath(directory,"result-1.0.json"));seeds=Dict(f=>seed for f in factors)
    working=Set(c.id for c in seedstudy.contingencies);rounds=Any[];accepted=false;selected=nothing
    fd_save(joinpath(S2500_QUAL,"protocol-$label.json"),(;confirmation,solver,factors,max_rounds,max_new_outages_per_round=4,
        scope="All 389 connected outages; screening scores order evaluation only; no screened event is declared safe",
        island_scope="255 islanding branch events retained separately, no silent load shedding or generator trips",
        run_source_hashes=Dict(p=>bytes2hex(sha256(read(joinpath(FD_ROOT,p)))) for p in ("examples/s2_arpae500_qualification.jl","examples/s2_arpae500_recovery.jl","examples/s2_arpae500_campaign.jl","Project.toml","Manifest.toml")),
        free_shared_droop_parameters=102,control_policy=full.control_policy,tap_controls=full.tap_controls,shunt_controls=full.shunt_controls,
        nominal_objective="100-percent base loss; all remaining design states impose feasibility",
        separator_budget=(primary_iterations=300,primary_seconds=5,retry_iterations=1500,retry_seconds=30,max_retries=1)))
    for round in 1:max_rounds
        prefix="qualification/$label/round-$round"
        master=DroopOPF._copy_study(full;contingencies=filter(c->c.id in working,events))
        lane=if round==1 && factors==(1.,) && solver==:ipopt && seed_directory=="pilot-ipopt"
            (;record=JSON.parsefile(joinpath(directory,"summary.json")),study=seedstudy,results=Dict(1.0=>seed))
        else
            s2500_targeted_attempt(prefix*"/master",master,controls,seedstudy,seeds,angles;solver,factors,
                normalization=solver!=:ccopt,scheduled=true,mu=1e-6)
        end
        if !lane.record["accepted"]
            warm=all(haskey(lane.results,f) && !isnothing(lane.results[f].states[:base]) for f in factors) ? lane.results : seeds
            lane=s2500_targeted_attempt(prefix*"/retry-master",master,controls,lane.study,warm,angles;solver,factors,retry=true,
                normalization=false,scheduled=true,mu=1e-6)
        end
        scans=Any[];failures=Symbol[]
        if lane.record["accepted"]
            for f in factors
                study=DroopOPF._copy_study(lane.study;case=DroopOPF._feasibility_scaled_case(lane.study.case,f),contingencies=events)
                scan=s2500_scan(prefix*"/demand-$f",study,lane.results[f],angles;solver)
                append!(failures,scan.failed);push!(scans,(;factor=f,accepted=scan.accepted,exhaustive=scan.exhaustive,evaluated=length(scan.rows),failed=scan.failed))
            end
            seedstudy=lane.study;seeds=lane.results
        end
        push!(rounds,(;round,master=lane.record,working_outages=sort(collect(working);by=string),scans))
        accepted=lane.record["accepted"] && length(scans)==length(factors) && all(s.accepted for s in scans)
        selected=accepted ? lane.record["name"] : nothing
        fd_save(joinpath(S2500_QUAL,"summary-$label.json"),(;rounds,accepted,selected,solver,factors,full_n1_accepted=false))
        accepted && break
        lane.record["accepted"] || break
        old=length(working);union!(working,failures)
        length(working)>old || break
    end
    fd_save(joinpath(S2500_QUAL,"STATUS-$label.json"),(;status=accepted ? "qualified_connected_sampled_scope" : "unqualified_after_bounded_rounds",accepted,
        rounds=length(rounds),working_outages=length(working),eligible_outages=389,factors,solver,full_n1_accepted=false))
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    length(ARGS)==1 || error("Supply the confirmed equipment scope")
    s2500_qualify(only(ARGS))
end
