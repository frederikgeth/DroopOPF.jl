# Fresh mixed-control campaign. Does not modify/resume S2 evidence.
using DroopOPF,JSON,SHA
const MIX_ROOT=normpath(joinpath(@__DIR__,".."))
mix_data(x)=DroopOPF._json_data(x)
mix_data(x::MultiPeriodSecurityResult)=Dict(string(k)=>mix_data(getfield(x,k)) for k in fieldnames(typeof(x)))
mix_data(x::DroopControl)=(;control_id=x.control_id,bounds=x.bounds,initial=mix_data(x.initial))
function mix_save(p,x)
    mkpath(dirname(p));write(p,JSON.json(mix_data(x);pretty=true)*"\n")
end
mix_state(s)=ACState(Float64.(s["vm"]),Float64.(s["va"]),Float64.(s["pg"]),Float64.(s["qg"]))
function mix_inputs(folder)
    root=joinpath(MIX_ROOT,"artifacts/p2_s2_500");contract=JSON.parsefile(joinpath(root,"contract.json"))
    inputs=Dict();checks=Any[]
    for (role,ref) in contract["inputs"]
        snapshot=joinpath(root,ref["snapshot"]);source=joinpath(MIX_ROOT,ref["source"])
        bytes=read(snapshot);h=bytes2hex(sha256(bytes))
        valid=h==ref["sha256"]&&bytes==read(source);valid||error("S2 input changed: $role")
        inputs[role]=JSON.parse(String(bytes));push!(checks,(;role,valid,sha256=h))
    end
    drift=[(;path=rel,original_hash=h,current_hash=bytes2hex(sha256(read(joinpath(MIX_ROOT,rel)))))
        for (rel,h) in contract["source_hashes"] if bytes2hex(sha256(read(joinpath(MIX_ROOT,rel))))!=h]
    mix_save(joinpath(folder,"input-verification.json"),(;inputs=checks,library_drift=drift,
        interpretation="Input bytes verified; current library intentionally extended; no claim of original S2 source identity"))
    source=deepcopy(inputs["shared_controller"]["data"])
    source["contingencies"]=[];source["reactive_assignments"]=nothing
    source["tap_controls"]=[];source["shunt_controls"]=[]
    # Decode physical data alone; response evidence is never migrated.
    mix_save(joinpath(folder,"decoded-input.json"),(;schema_version=10,kind="DroopOPF.Study",active_response="limit_aware_v1",data=source))
    c=read_study(joinpath(folder,"decoded-input.json")).case
    seed=inputs["shared_point"]["states"]
    nominal=only(s for s in seed if s["factor"]==1.0 &&s["id"]=="base")
    w=mix_state(nominal["state"]);idx=DroopOPF._bus_indices(c.network)
    eligible=sort([g for g in c.generators if g.available&&g.p_max>0];by=g->(-g.p_max,g.id))
    avr=eligible[1:floor(Int,.3length(eligible)+.5)]
    setup=mixed_reactive_controls(c;ratings=Dict(g.id=>g.p_max/.95 for g in eligible),
        voltage_targets=Dict(g.id=>w.vm[idx[g.bus_id]] for g in avr))
    taps=DroopOPF._tap_controls_from_data(contract["tap_controls"])
    shunts=DroopOPF._shunt_controls_from_data(contract["shunt_controls"])
    # Stable references use the original calibrated design envelope.
    controls=[DroopControl(d["control_id"];slope_bounds=d["slope_bounds"],v_ref_bounds=d["v_ref_bounds"])
        for d in contract["droop_design_controls"] if any(a->a.control_id==d["control_id"]&&a.generator_id in setup.droop_ids,c.attachments)]
    angles=Dict(parse(Int,k)=>Tuple(Float64.(v)) for (k,v) in JSON.parsefile(joinpath(MIX_ROOT,"artifacts/s1_free_droop/500/angle_limits.json")))
    catalog=contingency_catalog(setup.case);events=[e for e in catalog.entries if e.disposition==:eligible]
    mix_save(joinpath(folder,"generator-assignment.json"),(;eligible=length(eligible),avr_count=length(avr),droop_count=length(setup.droop_ids),
        rounding="nearest integer, half upward; descending Pmax then ascending generator ID",rows=setup.rows,
        apparent_rating="assumed S_rated=Pmax/0.95 for online units; system-base pu; not manufacturer nameplate",grid_following_model=false))
    mix_save(joinpath(folder,"catalogue.json"),catalog)
    (;setup,controls,taps,shunts,angles,events,seed,nominal,contract)
end
function mix_studies(x,factors,events;case=x.setup.case,assignments=x.setup.assignments)
    [Study(DroopOPF._feasibility_scaled_case(case,f);reactive_assignments=assignments,
        contingencies=[e.contingency for e in events],participation=hasproperty(x,:p2_policy) ? default_participation(case;reactive_assignments=assignments) : Dict(g.id=>g.p_max for g in case.generators if g.available),
        tap_controls=x.taps,shunt_controls=x.shunts,control_policy=hasproperty(x,:p2_policy) ? x.p2_policy : SCOPFControlPolicy(taps=:corrective,shunts=:corrective)) for f in factors]
end
function mix_starts(x,factors,events)
    [Dict(id=>begin
        candidates=[s for s in x.seed if s["id"]==string(id)]
        isempty(candidates) && (candidates=[x.nominal])
        best=candidates[argmin(abs(s["factor"]-f) for s in candidates)]
        mix_state(best["state"])
    end for id in [:base;[e.contingency.id for e in events]]) for f in factors]
end
function mix_attempt(x,folder,factors,events;controls=DroopControl[],starts=mix_starts(x,factors,events),
    studies=mix_studies(x,factors,events),seconds=120.,schedule=false,fixed_bases=nothing,solver_options=Dict(),smooth_epsilon=1e-5,initial_equipment=fill((;taps=Dict(),shunts=Dict()),length(factors)),objective_upper_bound=nothing,emergency=true,response=:s2_proportional,objective_policy=:loss,reserve_generator_outages=Int[],reserve_margin_pu=0.,optimizer_factory=DroopOPF.Ipopt.Optimizer,initial_avr_targets=fill(Dict(),length(factors)),initial_relief=fill(Dict(),length(factors)),initial_balancing_power=fill(Dict(),length(factors)))
    ispath(folder)&&error("fresh attempt folder required");mkpath(folder)
    ramps=Dict(g.id=>(.25*(g.p_max-g.p_min),.25*(g.p_max-g.p_min)) for g in x.setup.case.generators if g.available)
    avr_bounds=schedule ? Dict(a.generator_id=>(max(a.mode.voltage_setpoint-.02,
        only(b for b in x.setup.case.network.buses if b.id==a.location.bus_id).v_min),
        min(a.mode.voltage_setpoint+.02,only(b for b in x.setup.case.network.buses if b.id==a.location.bus_id).v_max))
        for a in x.setup.assignments if a.mode isa AVR) : Dict()
    mix_save(joinpath(folder,"contract.json"),(;factors,events=[e.contingency.id for e in events],
        response=string(response),s2_emergency=emergency,objective_policy,reserve_generator_outages,reserve_margin_pu,ramps,duration_hours=ones(length(factors)),angles=x.angles,
        droop_controls=[mix_data(c) for c in controls],avr_bounds,avr_movement_per_hour=.01,
        seconds,smooth_epsilon,solver_options,optimizer_factory=string(optimizer_factory),objective_upper_bound,initial_states=starts,initial_avr_targets,initial_relief,initial_balancing_power,initial_equipment,
        fixed_base=!isnothing(fixed_bases),fixed_base_reference=isnothing(fixed_bases) ? nothing :
            [(;state=p.states[:base],taps=p.tap_settings[:base],shunts=p.shunt_settings[:base]) for p in fixed_bases],
        manufacturer_ratings=false))
    for (t,s) in enumerate(studies);write_study(joinpath(folder,"period-$t.json"),s);end
    println("START ",folder);flush(stdout)
    kwargs=isnothing(fixed_bases) ? (;) : (;fixed_base_states=[r.states[:base] for r in fixed_bases],
        fixed_base_taps=[r.tap_settings[:base] for r in fixed_bases],fixed_base_shunts=[r.shunt_settings[:base] for r in fixed_bases])
    options=optimizer_factory===DroopOPF.Ipopt.Optimizer ? Dict("tol"=>1e-8,"acceptable_tol"=>1e-7,
        "acceptable_iter"=>5,"max_cpu_time"=>seconds,"max_iter"=>1800,"bound_relax_factor"=>0.,"mu_strategy"=>"adaptive",
        "output_file"=>joinpath(folder,"ipopt.log"),"file_print_level"=>5) :
        Dict("tol"=>1e-8,"acceptable_tol"=>1e-7,"acceptable_iter"=>5,"max_wall_time"=>seconds,
            "max_iter"=>1800,"bound_relax_factor"=>0.,"output_file"=>joinpath(folder,"madnlp.log"))
    timed=@timed optimize_multi_period_security(studies;droop_controls=controls,initial_states=starts,
        ramp_limits=ramps,angle_limits=x.angles,response,s2_emergency=emergency,smooth_epsilon,
        avr_bounds,avr_movement_per_hour=.01,initial_equipment,objective_upper_bound,objective_policy,reserve_generator_outages,reserve_margin_pu,
        optimizer_factory,initial_avr_targets,initial_relief,initial_balancing_power,optimizer_attributes=merge(options,solver_options),kwargs...)
    r=timed.value;a=validate_multi_period_security(studies,r)
    write_multi_period_security(joinpath(folder,"result.json"),r);mix_save(joinpath(folder,"audit.json"),a)
    run(`python3 -B $(joinpath(@__DIR__,"audit_mixed_avr_500.py")) $folder`)
    python_check=JSON.parsefile(joinpath(folder,"python-audit.json"))
    summary=(;accepted=a.valid && python_check["valid"],status=r.termination_status,objective_mwh=r.objective_mwh,
        wall_seconds=timed.time,allocated_bytes=timed.bytes,states=sum(length(p.states) for p in r.periods),
        maximum_balance=hasproperty(a,:rows) ? maximum(row.physical.power_balance_max for row in a.rows) : nothing,
        failed_rows=hasproperty(a,:rows) ? [(;period=row.period,scenario=row.scenario,violations=row.physical.violations) for row in a.rows if !row.valid] : [string(a)])
    mix_save(joinpath(folder,"summary.json"),summary);println("END ",summary);flush(stdout)
    (;result=r,audit=a,summary,studies)
end
mix_run(folder)=mixed_campaign(folder)

# Prepared starts for frozen-base AC assessment; do not reuse old S2 dispatch
# as though it were the preventive dispatch of the new mixed-control candidate.
function mix_response_starts(x,solution,c,events,factors)
    out=Dict[];idx=DroopOPF._bus_indices(c.network)
    for (t,f) in enumerate(factors)
        base=solution.periods[t].states[:base];states=Dict{Symbol,ACState{Float64}}(:base=>base)
        for e in events
            sc=scenario_case(DroopOPF._feasibility_scaled_case(c,f),e.contingency)
            lost=sum(base.pg[i] for (i,g) in enumerate(sc.generators) if c.generators[i].available&&!g.available;init=0.)
            total=sum(g.p_max for g in sc.generators if g.available)
            pg=[g.available ? base.pg[i]+g.p_max/total*lost : 0. for (i,g) in enumerate(sc.generators)]
            if hasproperty(x,:p2_policy)
                study=Study(c;reactive_assignments=solution.periods[t].reactive_assignments)
                alpha=DroopOPF._participation(study,sc)
                bounds=[DroopOPF._response_bounds(study,sc,i,base.pg[i]) for i in eachindex(pg)]
                response(delta)=[g.available ? clamp(base.pg[i]+alpha[i]*delta,bounds[i]...) : 0.
                    for (i,g) in enumerate(sc.generators)]
                target=sum(base.pg);left=0.;right=max(1.,lost)
                while sum(response(right))<target && right<1e6;right*=2;end
                for _ in 1:60
                    mid=(left+right)/2
                    if sum(response(mid))<target;left=mid;else;right=mid;end
                end
                pg=response((left+right)/2)
            end
            qg=copy(base.qg)
            for (i,g) in enumerate(sc.generators)
                if !g.available;qg[i]=0.;continue;end
                lo,hi=reactive_limits(g,pg[i]);qg[i]=clamp(qg[i],lo,hi)
            end
            for a in solution.periods[t].reactive_assignments
                a.mode isa VoltVarDroop || continue
                i=findfirst(g->g.id==a.generator_id,sc.generators);sc.generators[i].available||continue
                lo,hi=reactive_limits(sc.generators[i],pg[i]);lo=max(lo,a.mode.capability.q_min);hi=min(hi,a.mode.capability.q_max)
                qg[i]=clamp(evaluate(droop_curve(a.mode),base.vm[idx[a.location.bus_id]]),lo,hi)
            end
            states[e.contingency.id]=ACState(copy(base.vm),copy(base.va),pg,qg)
        end
        push!(out,states)
    end
    out
end

include("p2_mixed_avr_campaign.jl")
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("provide fresh campaign directory")
    mix_run(abspath(ARGS[1]))
end
