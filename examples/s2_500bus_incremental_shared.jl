# Confirmed expanded-master and incremental common-droop campaign.
include("s2_500bus_finish_multidemand.jl")
const RX_OUT=joinpath(S2500_OUT,"incremental_shared_recovery")
const RX_SOURCE=read(@__FILE__,String)
const RX_EXTRA=(:generator_32,:generator_89,:generator_37,:generator_42)
rx_events(ids)=filter(e->e.id in ids,eligible_contingencies(contingency_catalog(el_context().study.case)))
function rx_options(solver,profile)
    mu=profile==1 ? 1e-6 : 1e-8
    solver==:ipopt && return Dict{String,Any}("bound_push"=>1e-8,"bound_frac"=>1e-8,
        "slack_bound_push"=>1e-8,"slack_bound_frac"=>1e-8,"mu_init"=>mu)
    Dict{String,Any}("bound_push"=>1e-8,"bound_fac"=>1e-8,
        "barrier"=>MadNLP.MonotoneUpdate{Float64}(mu_init=mu,mu_min=1e-11))
end
function rx_protocol()
    confirmation=strip(get(ENV,"RX_CONTROL_CONFIRMATION",""));isempty(confirmation) && error("Fresh campaign equipment confirmation required")
    ENV["NR_ELIMINATION_MODE"]="independent-degree3";mkpath(RX_OUT)
    path=joinpath(RX_OUT,"PROTOCOL.json")
    if !isfile(path)
        prep=JSON.parsefile(joinpath(RX_OUT,"PREPARATION.json"))
        fd_save(path,(;status="confirmed_in_progress",confirmation,taps=prep["proposed_taps"],shunts=prep["proposed_shunts"],
            timing="Corrective per demand/outage; continuous banks; no extra movement budget",free_shared_slopes=51,free_shared_references=51,
            maximum_master_calls=64,single_stage_seconds=180.,joint_stage_seconds=240.,maximum_profiles_per_stage=2,
            direct_relief=true,physical_policy=prep["physical_policy"],maximum_demand=1.0625,
            plan="Expanded 105% with four failed outages and at most two qualification rounds; native joint feasibility at 90/95/100 then priorities, 105%, 106.25%; CCOpt single 100% gate before joint expansion"))
    end
end
function rx_common_seed()
    point=el_read_point(joinpath(FM_OUT,"witnesses/common-controller");stage="derived")
    point
end
function rx_cc_seed()
    folder=joinpath(SDQ_OUT,"ipopt-10000/round-1/attempt-1-buildretry-1")
    study=read_study(joinpath(folder,"optimized-1.0.json"));result=read_scopf_result(joinpath(folder,"result-1.0.json"))
    for id in FM_EVENTS
        haskey(result.states,id) && continue
        donor_folder=joinpath(SDQ_OUT,"ipopt-10000/round-1/demand-1.0",string(id))
        @assert JSON.parsefile(joinpath(donor_folder,"summary.json"))["accepted"]
        donor=read_scopf_result(joinpath(donor_folder,"result.json"))
        @assert DroopOPF._json_data(donor.states[:base])==DroopOPF._json_data(result.states[:base])
        @assert donor.tap_settings[:base]==result.tap_settings[:base] && donor.shunt_settings[:base]==result.shunt_settings[:base]
        result.states[id]=donor.states[id];result.tap_settings[id]=donor.tap_settings[id]
        result.shunt_settings[id]=donor.shunt_settings[id];result.balancing_power[id]=donor.balancing_power[id]
    end
    zeros=Dict(l.id=>0. for l in study.case.loads)
    states=Dict((1.,id)=>(;state,taps=result.tap_settings[id],banks=result.shunt_settings[id],
        dr=copy(zeros),shed=copy(zeros),delta=get(result.balancing_power,id,nothing)) for(id,state) in result.states if !isnothing(state))
    (;study,states)
end
function rx_preflight(seed,events)
    path=joinpath(RX_OUT,"direct-relief-preflight.json");isfile(path) && return
    records=Any[]
    for direct in (false,true)
        built=el_build(el_context(),(1.05,),events;seed,solver=:ipopt,emergency=true,relief=true,
            thermal_multiplier=1.1,restore=false,zero_shedding=true,penalty_proxies=false,
            droop_normalization=true,direct_relief=direct,ac_builder=nr_build_ac)
        violations=JuMP.primal_feasibility_report(v->something(start_value(v),0.),built.m;atol=1e-6)
        @assert isempty(violations) "Expanded start violates the $(direct ? "direct" : "auxiliary") model"
        push!(records,(;direct_relief=direct,variables=num_variables(built.m),
            constraints=num_constraints(built.m;count_variable_in_set_constraints=true),violations_over_1e6=length(violations)))
    end
    @assert records[2].variables<records[1].variables
    fd_save(path,(;passed=true,optimizer_calls=0,records,meaning="Both exact formulations accept the same original-network validated ten-state zero-shedding start"))
end
function rx_pipeline(label,factors,seed,events;solver=:ipopt,zero_shedding=false,zero_dr=false,stages=nothing,implied_q_bounds=false)
    objectives=isnothing(stages) ? (zero_shedding ? (:feasibility,:dr,:emergency,:loss) : (:feasibility,:shedding,:dr,:emergency,:loss)) : stages
    rows=Any[];budgets=Dict{Symbol,Float64}();selected=nothing;complete=true
    for stage in objectives
        good=nothing;anchor=seed
        for profile in 1:2
            backend=label=="expanded-105-r1" || label=="expanded-105-r2" ? (profile==1 ? :ipopt : :madnlp) : solver
            run=fm_attempt("$label-$stage-p$profile",stage,factors,seed,events;solver=backend,zero_shedding,zero_dr,
                budgets,retry=true,seconds=length(factors)>1 ? 240. : 180.,optimizer_options=rx_options(backend,profile),
                check_start=profile==1,output_root=RX_OUT,direct_relief=true,implied_q_bounds,objective_scale=stage in (:shedding,:dr,:loss) ? 100. : 1.,native_call_limit=64)
            write(joinpath(run.folder,"executed_incremental_driver.jl"),RX_SOURCE)
            push!(rows,run.summary)
            if run.accepted;good=run;break;end
            # Preserve a physically valid anchor rather than an invalid failed iterate.
            a=isfile(joinpath(run.folder,"audit-$stage.json")) ? JSON.parsefile(joinpath(run.folder,"audit-$stage.json")) : nothing
            seed=!isnothing(a) && a["physical_valid"] && !isnothing(run.point) ? run.point : anchor
        end
        if isnothing(good);complete=false;seed=anchor;break;end
        seed=good.point;selected=(;path=relpath(good.folder,S2500_OUT),stage)
        if stage in (:shedding,:dr,:emergency)
            budgets[stage]=Float64(good.summary.record.objective)
            stage==:emergency && (budgets[stage]+=1e-6*abs(budgets[stage]))
        end
        fd_save(joinpath(RX_OUT,"progress-$label.json"),(;label,factors,rows,budgets,selected))
    end
    result=(;label,factors,solver,complete,selected,budgets,rows,
        loss_objective_completed=complete && :loss in objectives,full_n1_accepted=false)
    fd_save(joinpath(RX_OUT,"summary-$label.json"),result)
    (;point=seed,result)
end
function rx_scan(point,selected,factors,label;zero_shedding=false)
    folder=joinpath(S2500_OUT,selected.path);stage=string(selected.stage)
    scan=el_emergency_scan(point,factors;label,reuse_master=false,master_witness=(;folder,stage),
        zero_shedding_only=zero_shedding,max_failures=4,seconds=15.)
    python=get(ENV,"NR_PYTHON","/tmp/s214-plot-env/bin/python")
    script=joinpath(FD_ROOT,"examples/audit_s2_500bus_finish_coverage.py")
    mode=zero_shedding ? "zero" : "allowed";fs=join(string.(factors),",")
    println(read(`$python $script $label $(selected.path) $stage $fs $mode $RX_OUT`,String));flush(stdout)
    scan
end
function rx_105()
    seed=el_read_point(joinpath(RX_OUT,"witnesses/expanded-105");stage="derived")
    ids=[FM_EVENTS...;RX_EXTRA...];events=rx_events(ids);rx_preflight(seed,events)
    rounds=Any[]
    for round in 1:2
        run=rx_pipeline("expanded-105-r$round",(1.05,),seed,events;zero_shedding=true)
        scan=isnothing(run.result.selected) ? nothing : rx_scan(run.point,run.result.selected,(1.05,),"incremental-105-r$round";zero_shedding=true)
        push!(rounds,(;round,master=run.result,coverage=isnothing(scan) ? nothing : (;accepted=scan.accepted,failed=scan.failed)))
        fd_save(joinpath(RX_OUT,"summary-expanded-105.json"),(;rounds,full_n1_accepted=false))
        (isnothing(scan) || scan.accepted || round==2) && break
        seed=run.point;append!(ids,scan.failed);events=rx_events(unique(ids))
    end
end
function rx_joint(solver)
    if solver==:ccopt
        single=JSON.parsefile(joinpath(RX_OUT,"summary-ccopt-single-100.json"))
        if !single["loss_objective_completed"]
            fd_save(joinpath(RX_OUT,"summary-joint-ccopt.json"),(;deferred=true,reason="Single-demand native loss-design gate remains open",rows=Any[]));return
        end
    end
    seed=rx_common_seed();events=rx_events(FM_EVENTS);rows=Any[]
    for factors in ((.9,.95,1.),(.9,.95,1.,1.05),(.9,.95,1.,1.05,1.0625))
        run=rx_pipeline("joint-$solver-$(length(factors))d",factors,seed,events;solver)
        push!(rows,run.result)
        fd_save(joinpath(RX_OUT,"summary-joint-$solver.json"),(;rows,full_n1_accepted=false))
        run.result.loss_objective_completed || break
        # Add any unresolved outages before extending to a higher demand level.
        scan=rx_scan(run.point,run.result.selected,factors,"incremental-$solver-$(length(factors))d")
        scan.accepted || break
        seed=run.point
        # Higher-factor initial states retain their saved values as numerical starts only.
        common=rx_common_seed()
        for(key,value) in common.states;haskey(seed.states,key) || (seed.states[key]=value);end
    end
end
function rx_run(mode)
    rx_protocol()
    mode=="105" && return rx_105()
    if mode=="ccopt"
        run=rx_pipeline("ccopt-single-100",(1.,),rx_cc_seed(),rx_events(FM_EVENTS);
            solver=:ccopt,zero_shedding=true,zero_dr=true,stages=(:feasibility,:loss))
        run.result.loss_objective_completed && rx_scan(run.point,run.result.selected,(1.,),"incremental-ccopt-100";zero_shedding=true)
        return rx_joint(:ccopt)
    end
    @assert mode in ("ipopt","madnlp");rx_joint(Symbol(mode))
end
abspath(PROGRAM_FILE)==(@__FILE__) && rx_run(only(ARGS))
