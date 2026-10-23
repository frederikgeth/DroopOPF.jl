# Matched multi-demand P2 configuration study. Importing this file does not solve.
using DroopOPF, JuMP, Ipopt, JSON, SHA, LinearAlgebra
include(joinpath(@__DIR__,"m2_case.jl"))
const MOI = JuMP.MOI
const PR_ROOT = normpath(joinpath(@__DIR__,".."))
const PR_TRAIN = [0.9,0.95,1.0,1.05,1.1]
const PR_HOLD = [0.925,0.975,1.025,1.075]
const PR_EPS = 1e-6
prsave(path,x) = open(io -> JSON.print(io,DroopOPF._json_data(x),2),path,"w")
prhash(path) = bytes2hex(sha256(read(path)))

function pr_fixture()
    c=m2_case()
    bank=ShuntBank(201,30;step_susceptances=(0.02,),step_conductances=(0.0,),
        legal_states=((0,),(1,),(2,),(3,)),state=(1,),nominal_state=(1,))
    branches=[Branch(b.id,b.from_bus,b.to_bus;resistance=b.resistance,
        reactance=b.reactance,charging=b.charging,thermal_limit=b.thermal_limit,
        kind=b.id==11 ? :transformer : b.kind,tap_ratio=b.tap_ratio) for b in c.network.branches]
    Case("p2-bank-fixture";base_power=c.base_power,base_frequency=c.base_frequency,
        network=ACNetwork(c.network.buses,branches;banks=[bank]),loads=c.loads,
        generators=c.generators,controls=c.controls,attachments=c.attachments)
end

function pr_inputs(name)
    if name=="bank_fixture"
        case=pr_fixture()
        start=ACState([.98,.98,.95],[0.,-.01,-.04],
            [g.initial_p for g in case.generators],
            [droop_response(case.controls[i],.98;p=g.initial_p) for (i,g) in enumerate(case.generators)])
        seed=solve_opf(case;smooth_epsilon=PR_EPS,initial_state=start)
        validate_equilibrium(case,seed).valid || error("fixture anchor rejected: $(seed.termination_status)")
        return (;case,base=seed.state,angles=Dict{Int,Tuple{Float64,Float64}}(),sources=String[])
    end
    d=joinpath(PR_ROOT,"artifacts/p2_completion/public_run",name)
    input=joinpath(d,"study.json");basepath=joinpath(d,"base.json")
    # These historical files have no coupled scenarios. Import only the case;
    # discard the obsolete participation map and create a fresh policy below.
    case=read_study(input).case
    raw=JSON.parsefile(basepath)
    base=ACState((Float64.(raw[k]) for k in ("vm","va","pg","qg"))...)
    validate_equilibrium(case,base).valid || error("saved base rejected")
    source=joinpath(PR_ROOT,"artifacts/p2_completion/public_sources",name*".m")
    rows=DroopOPF._matpower_array(read(source,String),"branch")
    angles=Dict(i=>(deg2rad(rows[i,12]),deg2rad(rows[i,13])) for i in axes(rows,1))
    (;case,base,angles,sources=[input,basepath,source])
end

prcost(c,s)=sum((s.pg[i]-g.initial_p)^2+1e-3*(s.qg[i]-g.initial_q)^2 for (i,g) in enumerate(c.generators))
function pr_angles!(model,case,va,angles)
    idx=DroopOPF._bus_indices(case.network)
    for b in case.network.branches
        b.available && haskey(angles,b.id) || continue
        lo,hi=angles[b.id]
        @constraint(model,lo<=va[idx[b.from_bus]]-va[idx[b.to_bus]]<=hi)
    end
end
function pr_angle_margin(study,result,angles)
    margin=Inf
    for (id,c) in zip([:base;[x.id for x in study.contingencies]],
        [study.case;[scenario_case(study.case,x) for x in study.contingencies]])
        state=get(result.states,id,nothing);isnothing(state) && return -Inf
        idx=DroopOPF._bus_indices(c.network)
        for b in c.network.branches
            b.available && haskey(angles,b.id) || continue
            lo,hi=angles[b.id];a=state.va[idx[b.from_bus]]-state.va[idx[b.to_bus]]
            margin=min(margin,a-lo,hi-a)
        end
    end
    margin
end

function pr_design(input,lane,out;prior=nothing,retry=false)
    case=input.case;catalog=contingency_catalog(case)
    events=case.id=="p2-bank-fixture" ? eligible_contingencies(catalog) :
        [e.contingency for e in catalog.entries if e.disposition==:eligible && e.device_kind in (:line,:transformer)]
    free=lane!=:fixed; equipment=lane==:preventive
    taps=equipment ? [TapControl(b.id;lower=.95b.tap_ratio,upper=1.05b.tap_ratio,
        initial=b.tap_ratio,nominal=b.tap_ratio) for b in case.network.branches
        if b.available && b.kind==:transformer] : TapControl[]
    shunts=equipment ? [ShuntControl(b.id) for b in case.network.banks if b.available] : ShuntControl[]
    controls=[DroopControl(i;slope_bounds=free ? (.5d.slope,2d.slope) : (d.slope,d.slope),
        v_ref_bounds=free ? (d.schedule.v_ref-.02,d.schedule.v_ref+.02) :
            (d.schedule.v_ref,d.schedule.v_ref)) for (i,d) in enumerate(case.controls)]
    attempt=retry ? "retry" : "primary";dir=joinpath(out,attempt);mkpath(dir)
    model=Model(Ipopt.Optimizer);set_silent(model)
    params=Dict{Int,NamedTuple}()
    for c in controls
        policy=DroopOPF._joint_droop_policy(case,c);names=keys(policy.ranges)
        initial=isnothing(prior) || !haskey(prior.settings,c.control_id) ? policy.initial : prior.settings[c.control_id]
        params[c.control_id]=NamedTuple{names}(Tuple(DroopOPF._droop_design_variable(model,
            "shared_$(c.control_id)_$k",getfield(policy.ranges,k),clamp(getfield(initial,k),getfield(policy.ranges,k)...)) for k in names))
    end
    blocks=Dict{Float64,Any}();base_objectives=Any[]
    for (j,f) in enumerate(PR_TRAIN)
        scaled=DroopOPF._feasibility_scaled_case(case,f)
        study=Study(scaled;contingencies=events,tap_controls=taps,shunt_controls=shunts,
            control_policy=SCOPFControlPolicy(taps=:preventive,shunts=:preventive))
        ids=[:base;[e.id for e in events]];cases=[scaled;[scenario_case(scaled,e) for e in events]]
        vars=Any[];deltas=Dict{Symbol,VariableRef}()
        for (k,(id,c)) in enumerate(zip(ids,cases))
            seed=isnothing(prior) ? input.base : get(get(prior.states,f,Dict()),id,input.base)
            isnothing(seed) && (seed=input.base)
            prefix="demand_$(j)_scenario_$(k)_"
            _,v=DroopOPF._build_acopf_model(c;voltage_epsilon=PR_EPS,
                reactive_relative_epsilon=PR_EPS,reactive_epsilon=nothing,silent=true,
                shared_model=model,scenario_prefix=prefix,set_objective=false,initial_state=seed,
                tap_controls=DroopOPF._scenario_tap_controls(study,c),
                shunt_controls=shunts,droop_parameter_variables=params,sparse_balance=true)
            push!(vars,v);pr_angles!(model,c,v.va,input.angles)
            if k>1
                delta=DroopOPF._add_response_constraints!(model,study,c,vars[1],v,prefix,:smooth)
                deltas[id]=delta
                DroopOPF._couple_equipment!(model,study.control_policy,vars[1].taps,vars[1].shunts,v)
            end
        end
        if !isempty(blocks)
            firstbase=blocks[first(PR_TRAIN)].vars[1]
            for (a,b) in ((firstbase.taps,vars[1].taps),(firstbase.shunts,vars[1].shunts))
                for id in keys(a);@constraint(model,a[id]==b[id]);end
            end
        end
        push!(base_objectives,sum((vars[1].pg[i]-g.initial_p)^2+
            1e-3*(vars[1].qg[i]-g.initial_q)^2 for (i,g) in enumerate(scaled.generators)))
        blocks[f]=(;study,ids,vars,deltas)
    end
    @objective(model,Min,sum(base_objectives)/length(PR_TRAIN))
    opts=Dict("tol"=>1e-8,"max_iter"=>retry ? 3000 : 1500,
        "max_cpu_time"=>retry ? 120. : 60.,"bound_relax_factor"=>0.,"mu_strategy"=>"adaptive")
    for (k,v) in opts;set_optimizer_attribute(model,k,v);end
    prsave(joinpath(dir,"protocol.json"),(;lane,attempt,options=opts,controls,taps,shunts,
        training=PR_TRAIN,held_out=PR_HOLD,objective="equal-weight mean base schedule deviation",
        equipment_shared_across="all demands and contingencies",post_outage_movement=0,
        active_response="limit_aware_v1",screening=false,angle_bounds=input.angles))
    println("START ",case.id," ",lane," ",attempt," variables=",num_variables(model));flush(stdout)
    timed=@timed optimize!(model)
    settings=Dict{Int,DroopSettings{Float64}}();states=Dict{Float64,Any}()
    record=Dict{String,Any}("lane"=>string(lane),"attempt"=>attempt,"status"=>string(termination_status(model)),
        "native_success"=>termination_status(model) in (MOI.LOCALLY_SOLVED,MOI.ALMOST_LOCALLY_SOLVED,MOI.OPTIMAL),
        "seconds"=>timed.time,"accepted"=>false,"training"=>Any[],"settings"=>settings)
    reports=Any[];equipment_settings=Any[];losses=Float64[];costs=Float64[]
    if has_values(model)
        record["raw_parameters"]=Dict(id=>Dict(string(k)=>Float64(DroopOPF._droop_design_value(getfield(p,k))) for k in keys(p)) for (id,p) in params)
        for (id,p) in params
            try
                settings[id]=DroopSettings((Float64(DroopOPF._droop_design_value(getfield(p,k))) for k in keys(p))...)
            catch err
                err isa ArgumentError || rethrow()
            end
        end
        for f in PR_TRAIN
            b=blocks[f];st=b.study
            if length(settings)==length(params)
                for id in sort(collect(keys(settings)));st=with_droop_settings(st,id,settings[id]);end
            end
            ss=Dict{Symbol,Union{Nothing,ACState{Float64}}}(id=>nothing for id in b.ids)
            ts=Dict{Symbol,Dict{Int,Float64}}();bs=Dict{Symbol,Dict{Int,Float64}}()
            for (id,v) in zip(b.ids,b.vars)
                vals=[Float64.(value.(getproperty(v,k))) for k in (:vm,:va,:pg,:qg)]
                all(x->all(isfinite,x),vals) && all(>(0),vals[1]) && (ss[id]=ACState(vals...))
                ts[id]=Dict(i=>Float64(value(x)) for (i,x) in v.taps)
                bs[id]=Dict(i=>Float64(value(x)) for (i,x) in v.shunts)
            end
            states[f]=ss;cost=isnothing(ss[:base]) ? NaN : prcost(st.case,ss[:base]);push!(costs,cost)
            result=SCOPFResult(ss,Dict(id=>Float64(value(x)) for (id,x) in b.deltas),cost,
                Symbol(string(termination_status(model))),Symbol(string(primal_status(model))),:preventive,:smooth,
                PR_EPS,PR_EPS,nothing,solver_name(model),nothing,ts,bs,taps,shunts,st.control_policy)
            validation=try
                design=SCOPFDroopDesignResult(controls,Dict(i=>DroopSettings(d) for (i,d) in enumerate(case.controls)),settings,result)
                validate_droop_design(b.study,design)
            catch err
                (;valid=false,error=sprint(showerror,err))
            end
            angle=pr_angle_margin(st,result,input.angles)
            row=(;factor=f,valid=validation.valid && angle>=-1e-6,angle_margin=angle,
                loss_mw=isnothing(ss[:base]) ? NaN : (sum(ss[:base].pg)-sum(l.p for l in st.case.loads))*case.base_power)
            push!(record["training"],row);push!(equipment_settings,(;taps=ts[:base],shunts=bs[:base]))
            push!(losses,row.loss_mw)
            tag=string(f);write_study(joinpath(dir,"study-$tag.json"),st)
            write_scopf_result(joinpath(dir,"result-$tag.json"),result)
            prsave(joinpath(dir,"validation-$tag.json"),validation)
        end
        spread=maximum([0.;[abs(getproperty(x,k)[id]-getproperty(first(equipment_settings),k)[id])
            for x in equipment_settings for k in (:taps,:shunts) for id in keys(getproperty(x,k))]])
        record["equipment_cross_demand_error"]=spread
        record["objective"]=objective_value(model);record["objective_replay_error"]=abs(objective_value(model)-sum(costs)/length(costs))
        record["accepted"]=record["native_success"] && length(settings)==length(params) &&
            all(x.valid for x in record["training"]) && spread<=1e-6 && record["objective_replay_error"]<=1e-7
        record["equipment"]=equipment_settings
    end
    prsave(joinpath(dir,"summary.json"),record)
    println("END ",case.id," ",lane," ",attempt," ",record["status"]," accepted=",record["accepted"]);flush(stdout)
    (;record,settings,states,dir,blocks)
end

function pr_heldout(input,design,out)
    rows=Any[];f0=1.0
    selected=read_study(joinpath(design.dir,"study-$f0.json"))
    witness=read_scopf_result(joinpath(design.dir,"result-$f0.json"))
    fixed=with_shunt_settings(with_tap_settings(selected.case,witness.tap_settings[:base]),witness.shunt_settings[:base])
    for factor in PR_HOLD
        case=DroopOPF._feasibility_scaled_case(fixed,factor)
        study=Study(case;contingencies=selected.contingencies)
        nearest=PR_TRAIN[argmin(abs.(PR_TRAIN.-factor))]
        starts=design.states[nearest]
        function angles_hook(model)
            cases=[case;[scenario_case(case,e) for e in study.contingencies]]
            for (k,c) in enumerate(cases)
                va=[variable_by_name(model,"scenario_$(k)_va[$i]") for i in eachindex(c.network.buses)]
                pr_angles!(model,c,va,input.angles)
            end
        end
        attempts=Any[];result=nothing;report=nothing
        for retry in (false,true)
            options=Dict("tol"=>1e-8,"max_iter"=>retry ? 3000 : 1500,
                "max_cpu_time"=>retry ? 60. : 30.,"bound_relax_factor"=>0.,"mu_strategy"=>"adaptive")
            result=solve_scopf(study;smooth_epsilon=PR_EPS,sparse_balance=true,
                initial_states=starts,optimizer_attributes=options,_model_hook=angles_hook)
            report=equilibrium_report(study,result);angle=pr_angle_margin(study,result,input.angles)
            push!(attempts,(;retry,status=result.termination_status,valid=report.valid && angle>=-1e-6))
            dir=joinpath(out,string(factor),retry ? "retry" : "primary");mkpath(dir)
            write_study(joinpath(dir,"study.json"),study);write_scopf_result(joinpath(dir,"result.json"),result)
            prsave(joinpath(dir,"validation.json"),report)
            last(attempts).valid && break
            starts=result.states
        end
        push!(rows,(;factor,accepted=last(attempts).valid,attempts))
    end
    prsave(joinpath(out,"summary.json"),rows);rows
end

function pr_main(output,names)
    ispath(output) && error("Use a fresh output directory")
    mkpath(output);BLAS.set_num_threads(1)
    prsave(joinpath(output,"protocol.json"),(;date="2026-10-21",names,training=PR_TRAIN,held_out=PR_HOLD,
        lanes=["fixed","droop","preventive"],source_hashes=Dict(relpath(p,PR_ROOT)=>prhash(p)
            for p in [@__FILE__;filter(x->endswith(x,".jl"),readdir(joinpath(PR_ROOT,"src");join=true))]),
        caveats=["tap +/-5% is an assumed sensitivity envelope, not manufacturer data",
        "only existing simple banks selected; fixed public shunts remain fixed",
        "continuous settings; zero corrective movement; islands excluded; no full-network security claim",
        "development comparison, not fresh held-out network qualification or performance benchmark"]))
    rows=Any[]
    for name in names
        input=pr_inputs(name);dir=joinpath(output,name);mkpath(dir)
        prsave(joinpath(dir,"reference_base.json"),input.base)
        catalog=contingency_catalog(input.case);write_contingency_catalog(joinpath(dir,"catalog.json"),catalog)
        write_study(joinpath(dir,"source.json"),Study(input.case))
        branch_events=[e.contingency for e in catalog.entries if e.disposition==:eligible && e.device_kind in (:line,:transformer)]
        supply=[(;factor=f,outage=e.contingency.id,
            demand_pu=f*sum(l.p for l in input.case.loads),
            surviving_pmax_pu=sum(g.p_max for g in input.case.generators if g.available && !(g.id in e.contingency.generator_ids)))
            for f in PR_TRAIN for e in catalog.entries if e.disposition==:eligible && e.device_kind==:generator]
        prsave(joinpath(dir,"supply_check.json"),supply)
        prsave(joinpath(dir,"inputs.json"),(;source_hashes=Dict(p=>prhash(p) for p in input.sources),angles=input.angles,
            eligible=length(eligible_contingencies(catalog)),design_events=input.case.id=="p2-bank-fixture" ? eligible_contingencies(catalog) : branch_events,
            public_scope="connected branch outages only; full-catalog generator supply obstructions retained separately",
            excluded=excluded_contingencies(catalog)))
        prior=nothing
        for lane in (:fixed,:droop,:preventive)
            path=joinpath(dir,string(lane));run=pr_design(input,lane,path;prior)
            if !run.record["accepted"]
                run=pr_design(input,lane,path;prior=run,retry=true)
            end
            held=run.record["accepted"] ? pr_heldout(input,run,joinpath(path,"heldout")) : nothing
            push!(rows,(;name,lane,training_accepted=run.record["accepted"],heldout=held,
                selected_attempt=run.record["attempt"],training=run.record["training"],
                objective=get(run.record,"objective",nothing)))
            prsave(joinpath(output,"summary.json"),rows)
            # Rejected states are numerical starts only, never accepted witnesses.
            !isempty(run.states) && (prior=run)
        end
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && pr_main(abspath(ARGS[1]),isempty(ARGS[2:end]) ?
    ["bank_fixture","pglib_opf_case14_ieee","pglib_opf_case39_epri"] : ARGS[2:end])
