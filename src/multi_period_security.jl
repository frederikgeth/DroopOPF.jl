"""Multi-period AC security result. Contingency states are settled responses;
there is no transient trajectory or inter-period ramp on outage states.
"""
struct MultiPeriodSecurityResult
    periods::Vector{SCOPFResult}
    droops::Dict{Int,DroopSettings{Float64}}
    droop_controls::Vector{DroopControl}
    relief::Vector{Dict{Symbol,NamedTuple}}
    objective_mwh::Float64
    termination_status::Symbol
    primal_status::Symbol
    duration_hours::Vector{Float64}
    ramp_limits::Dict{Int,Tuple{Float64,Float64}}
    angle_limits::Dict{Int,Tuple{Float64,Float64}}
    response::Symbol
    emergency::Bool
    avr_targets::Vector{Dict{Int,Float64}}
    avr_bounds::Dict{Int,Tuple{Float64,Float64}}
    avr_movement_per_hour::Float64
    stages::Vector{NamedTuple}
end

function _security_emergency_case(c)
    net=c.network
    buses=[Bus(b.id;v_min=b.v_min-.05,v_max=b.v_max+.05,reference=b.reference) for b in net.buses]
    branches=[Branch(b.id,b.from_bus,b.to_bus;resistance=b.resistance,reactance=b.reactance,
        charging=b.charging,thermal_limit=1.1b.thermal_limit,available=b.available,
        tap_ratio=b.tap_ratio,phase_shift=b.phase_shift,kind=b.kind) for b in net.branches]
    Case(c.id;base_power=c.base_power,base_frequency=c.base_frequency,
        network=ACNetwork(buses,branches;shunts=net.shunts,banks=net.banks),
        loads=c.loads,generators=c.generators,controls=c.controls,attachments=c.attachments)
end
function _security_relief_case(c,dr,shed)
    loads=[Load(l.id,l.bus_id;p=l.p-dr[i]-shed[i],
        q=l.q-(l.p>0 ? (dr[i]+shed[i])*l.q/l.p : 0.)) for (i,l) in enumerate(c.loads)]
    Case(c.id;base_power=c.base_power,base_frequency=c.base_frequency,network=c.network,
        loads,generators=c.generators,controls=c.controls,attachments=c.attachments)
end
function _security_assignments(case,assignments,settings,targets)
    a=_settings_assignments(case,assignments,settings)
    isnothing(a) && return nothing
    ReactiveControlAssignment[x.mode isa AVR && haskey(targets,x.generator_id) ?
        ReactiveControlAssignment(x.generator_id,AVR(targets[x.generator_id]),x.location) : x for x in a]
end

"""Optimize shared droop across ordered periods and listed contingencies.

`response=:s2_proportional` preserves supplied weights without saturation;
`:limit_aware` uses the production response model. `s2_emergency=true` explicitly
selects S2's ±0.05 pu voltage extension, 1.1 thermal ratings, 1% per-load DR,
10 MW shedding per outage, 10% combined relief, proportional reactive relief.
Base cases always use original bounds/full load. Objectives are sequential:
minimum total shedding, minimum total DR, then duration-weighted base loss. `objective_policy=:reserve_loss` inserts
maximization of the minimum participating-generator upward-headroom fraction
before loss; `:reserve` stops after the reserve stage. This is a dispatch preference, not an outage-security certificate.
Equipment follows each Study policy; ramps link preventive dispatch only.
Optional `avr_bounds` schedules preventive targets with movement in pu/hour;
otherwise all supplied targets remain fixed. Optional `reserve_generator_outages`
requires surviving participation to have upward room for each named generator's
entire base output plus `reserve_margin_pu`, before any load relief. This explicit
reserve target does not account for changed losses or replace exact outage AC.
Retain this extra policy externally with the input studies for independent audit.
`objective_policy=:feasibility` seeks a constrained witness without resource or
loss optimization. Each initial-equipment entry may carry a `scenarios` dictionary of per-scenario
`taps`/`shunts` starting values, falling back to its period entry. These starts
do not change equipment bounds, timing, movement budgets or shared constraints.
`initial_avr_targets`, `initial_relief` and `initial_balancing_power` retain the
remaining primal variables across retries; each supplies one dictionary per period.
Unknown scenario/target IDs, nonfinite values and inconsistent shared targets are
rejected. AVR and individual relief starts are clipped to variable bounds.
No manufacturer timing is inferred.
"""
function optimize_multi_period_security(studies;duration_hours=ones(length(studies)),
    ramp_limits=Dict(),angle_limits=Dict(),droop_controls=DroopControl[],
    initial_states=fill(Dict(),length(studies)),response=:limit_aware,
    initial_avr_targets=fill(Dict(),length(studies)),initial_relief=fill(Dict(),length(studies)),
    initial_balancing_power=fill(Dict(),length(studies)),
    s2_emergency=false,smooth_epsilon=1e-6,optimizer_factory=Ipopt.Optimizer,
    optimizer_attributes=Dict(),silent=true,avr_bounds=Dict(),avr_movement_per_hour=.01,
    fixed_base_states=nothing,fixed_base_taps=nothing,fixed_base_shunts=nothing,
    initial_equipment=fill((;taps=Dict(),shunts=Dict()),length(studies)),objective_upper_bound=nothing,objective_policy=:loss,reserve_generator_outages=Int[],reserve_margin_pu=0.)
    ss=Study[studies...];n=length(ss)
    n>0 || throw(ArgumentError("at least one study required"))
    temporal=MultiPeriodStudy([s.case for s in ss];duration_hours,ramp_limits,angle_limits)
    response in (:limit_aware,:s2_proportional) || throw(ArgumentError("unknown response"))
    length(initial_equipment)==n || throw(ArgumentError("one equipment start per period"))
    length(initial_states)==n || throw(ArgumentError("one start dictionary per period"))
    length(initial_avr_targets)==n && length(initial_relief)==n && length(initial_balancing_power)==n ||
        throw(ArgumentError("one warm-start dictionary per period"))
    !s2_emergency && any(!isempty(d) for d in initial_relief) && throw(ArgumentError("relief starts require emergency relief variables"))
    for t in 1:n
        events=Set(c.id for c in ss[t].contingencies)
        all(id->id in events,keys(initial_relief[t])) && all(id->id in events,keys(initial_balancing_power[t])) ||
            throw(ArgumentError("unknown relief or balancing-power start scenario"))
        all(isfinite,values(initial_balancing_power[t])) || throw(ArgumentError("nonfinite balancing-power start"))
        for r in values(initial_relief[t])
            hasproperty(r,:dr) && hasproperty(r,:shed) && length(r.dr)==length(r.shed)==length(ss[t].case.loads) ||
                throw(ArgumentError("relief starts need one DR and shedding value per original load"))
            all(isfinite,r.dr) && all(isfinite,r.shed) || throw(ArgumentError("nonfinite relief start"))
        end
    end
    for (t,equipment) in enumerate(initial_equipment)
        if hasproperty(equipment,:scenarios)
            allowed=Set([:base;[c.id for c in ss[t].contingencies]])
            all(id->id in allowed,keys(equipment.scenarios)) || throw(ArgumentError("unknown equipment-start scenario"))
        end
    end
    all(s->s.mode==:preventive,ss) || throw(ArgumentError("preventive active response required"))
    # Frozen evaluation may supply a previously qualified preventive AVR schedule.
    # Only the declared AVR target may differ; all other mode/location data match.
    reference_assignments=ss[1].reactive_assignments
    reference_targets=isnothing(reference_assignments) ? Dict() :
        Dict(a.generator_id=>a.mode.voltage_setpoint for a in reference_assignments if a.mode isa AVR)
    all(s->_json_data(s.reactive_assignments)==_json_data(reference_assignments) ||
        (!isnothing(fixed_base_states) &&
         _json_data(_security_assignments(s.case,s.reactive_assignments,Dict(),reference_targets))==_json_data(reference_assignments)),ss) ||
        throw(ArgumentError("periods require common input assignments except frozen AVR targets"))
    all(s->_json_data(s.tap_controls)==_json_data(ss[1].tap_controls) &&
        _json_data(s.shunt_controls)==_json_data(ss[1].shunt_controls) &&
        _json_data(s.control_policy)==_json_data(ss[1].control_policy) &&
        s.participation==ss[1].participation && s.redispatch_limits==ss[1].redispatch_limits,ss) ||
        throw(ArgumentError("periods require common equipment/response policy"))
    length(unique(c.control_id for c in droop_controls))==length(droop_controls) || throw(ArgumentError("duplicate droop IDs"))
    _check_mixed_design(ss[1].case,ss[1].reactive_assignments,droop_controls)
    isfinite(smooth_epsilon)&&smooth_epsilon>0 || throw(ArgumentError("invalid smoothing"))
    isfinite(avr_movement_per_hour)&&avr_movement_per_hour>=0 || throw(ArgumentError("invalid AVR movement"))
    objective_policy in (:loss,:reserve,:reserve_loss,:feasibility) || throw(ArgumentError("unknown objective policy"))
    fixed=!isnothing(fixed_base_states)
    fixed && (!isempty(droop_controls)||!isempty(avr_bounds)) && throw(ArgumentError("fixed-base evaluation requires frozen controls"))
    fixed && (length(fixed_base_states)!=n || isnothing(fixed_base_taps) || isnothing(fixed_base_shunts)) &&
        throw(ArgumentError("fixed bases require states, taps and shunts for every period"))
    reserve_ids=Int[reserve_generator_outages...]
    length(unique(reserve_ids))==length(reserve_ids) || throw(ArgumentError("duplicate reserve outage IDs"))
    fixed && !isempty(reserve_ids) && throw(ArgumentError("reserve targets belong to preventive optimization"))
    isfinite(reserve_margin_pu) && reserve_margin_pu>=0 || throw(ArgumentError("invalid reserve margin"))
    model=Model(optimizer_factory);silent && set_silent(model)
    pars=Dict{Int,NamedTuple}()
    for c in droop_controls
        p=_joint_droop_policy(ss[1].case,c)
        pars[c.control_id]=NamedTuple{keys(p.ranges)}(Tuple(_droop_design_variable(model,
            "shared_$(c.control_id)_$k",getfield(p.ranges,k),getfield(p.initial,k);normalize=true) for k in keys(p.ranges)))
    end
    targets=[Dict{Int,Any}() for _ in ss];bounds=Dict{Int,Tuple{Float64,Float64}}()
    assignments=ss[1].reactive_assignments
    for (id,b) in avr_bounds
        !isnothing(assignments) || throw(ArgumentError("AVR scheduling requires explicit assignments"))
        a=only(x for x in assignments if x.generator_id==id)
        a.mode isa AVR || throw(ArgumentError("scheduled generator must have AVR"))
        only(g for g in ss[1].case.generators if g.id==id).available ||
            throw(ArgumentError("cannot schedule an offline AVR"))
        bus=only(x for x in ss[1].case.network.buses if x.id==a.location.bus_id)
        length(b)==2 && all(isfinite,b) && bus.v_min<=b[1]<=b[2]<=bus.v_max || throw(ArgumentError("invalid AVR bounds"))
        bounds[id]=(Float64(b[1]),Float64(b[2]))
    end
    for d in initial_avr_targets
        all(id->haskey(bounds,id),keys(d)) && all(isfinite,values(d)) || throw(ArgumentError("invalid AVR target start"))
    end
    # One physical target per regulated location. Sharing the same scalar also
    # avoids tiny solver-equality differences becoming contradictory setpoints.
    if !isnothing(assignments)
        for group in _active_avr_groups(ss[1].case,assignments)
            selected=[a.generator_id for a in group if haskey(bounds,a.generator_id)]
            isempty(selected) && continue
            lo=maximum(bounds[id][1] for id in selected);hi=minimum(bounds[id][2] for id in selected)
            reference=Float64(first(group).mode.voltage_setpoint)
            lo<=hi || throw(ArgumentError("common-location AVR target bounds do not intersect"))
            if length(selected)<length(group)
                lo<=reference<=hi || throw(ArgumentError("an unscheduled AVR fixes the common target outside the selected bounds"))
                lo=hi=reference
            end
            previous=nothing
            for t in 1:n
                supplied=[initial_avr_targets[t][id] for id in selected if haskey(initial_avr_targets[t],id)]
                isempty(supplied) || maximum(supplied)-minimum(supplied)<=1e-10 ||
                    throw(ArgumentError("common-location AVR starting targets disagree"))
                target_start=isempty(supplied) ? reference : first(supplied)
                target=lo==hi ? lo : @variable(model,lower_bound=lo,upper_bound=hi,
                    start=clamp(target_start,lo,hi),base_name="avr_$(first(selected))_$t")
                for id in selected;targets[t][id]=target;end
                if t>1 && target isa VariableRef
                    cap=avr_movement_per_hour*duration_hours[t-1]
                    @constraint(model,-cap<=target-previous<=cap)
                end
                previous=target
            end
        end
    end
    blocks=[Dict{Symbol,Any}() for _ in ss];rels=[Dict{Symbol,Any}() for _ in ss]
    deltas=[Dict{Symbol,Any}() for _ in ss]
    all_dr=Any[];all_shed=Any[]
    for (t,s) in enumerate(ss)
        events=[:base;[c.id for c in s.contingencies]]
        cases=[s.case;[scenario_case(s.case,c) for c in s.contingencies]]
        for (k,(id,raw)) in enumerate(zip(events,cases))
            if fixed && id==:base
                blocks[t][id]=fixed_base_states[t];continue
            end
            c=s2_emergency && k>1 ? _security_emergency_case(raw) : raw
            prefix="p$(t)_$(k)_";relief=nothing
            if s2_emergency && k>1
                dr=Any[];shed=Any[];rp=Any[0. for _ in c.network.buses];rq=copy(rp);idx=_bus_indices(c.network)
                relief_start=get(initial_relief[t],id,nothing)
                for (i,l) in enumerate(c.loads)
                    d0=isnothing(relief_start) ? 0. : clamp(relief_start.dr[i],0.,.01max(l.p,0.))
                    h0=isnothing(relief_start) ? 0. : clamp(relief_start.shed[i],0.,.1max(l.p,0.))
                    d=@variable(model,lower_bound=0,upper_bound=.01max(l.p,0.),start=d0,base_name=prefix*"dr_$i")
                    h=@variable(model,lower_bound=0,upper_bound=.1max(l.p,0.),start=h0,base_name=prefix*"shed_$i")
                    @constraint(model,d+h<=.1max(l.p,0.))
                    push!(dr,d);push!(shed,h)
                end
                @constraint(model,sum(shed)<=10/c.base_power)
                append!(all_dr,dr);append!(all_shed,shed)
                relief=(;p=[dr[i]+shed[i] for i in eachindex(dr)],
                    q=[l.p>0 ? (dr[i]+shed[i])*l.q/l.p : 0. for (i,l) in enumerate(c.loads)])
                rels[t][id]=(;dr,shed)
            end
            equipment_start=hasproperty(initial_equipment[t],:scenarios) ?
                get(initial_equipment[t].scenarios,id,initial_equipment[t]) : initial_equipment[t]
            tc=[TapControl(x.branch_id;lower=x.lower,upper=x.upper,
                initial=get(equipment_start.taps,x.branch_id,isnothing(x.initial) ? only(b for b in c.network.branches if b.id==x.branch_id).tap_ratio : x.initial),
                nominal=x.nominal) for x in _scenario_tap_controls(s,c)]
            sc=[ShuntControl(x.bank_id;lower=x.lower,upper=x.upper,
                initial=get(equipment_start.shunts,x.bank_id,x.initial),nominal=x.nominal) for x in s.shunt_controls]
            _,v=_build_acopf_model(c;voltage_epsilon=smooth_epsilon,
                reactive_relative_epsilon=smooth_epsilon,reactive_epsilon=nothing,
                silent,shared_model=model,scenario_prefix=prefix,set_objective=false,
                initial_state=get(initial_states[t],id,get(initial_states[t],:base,nothing)),
                droop_parameter_variables=pars,reactive_assignments=s.reactive_assignments,
                tap_controls=isempty(s.tap_controls) ? nothing : tc,
                shunt_controls=isempty(s.shunt_controls) ? nothing : sc,
                normalize_controls=true,sparse_balance=true,load_relief=relief,avr_target_variables=targets[t])
            idx=_bus_indices(c.network)
            for b in c.network.branches
                b.available && haskey(angle_limits,b.id) || continue
                lo,hi=angle_limits[b.id];@constraint(model,lo<=v.va[idx[b.from_bus]]-v.va[idx[b.to_bus]]<=hi)
            end
            blocks[t][id]=v
            if k>1
                base=blocks[t][:base]
                if response==:s2_proportional
                    alpha=_participation(s,c)
                    base_pg=base isa ACState ? base.pg : start_value.(base.pg)
                    delta_start=sum(start_value(v.pg[i])-base_pg[i] for (i,g) in enumerate(c.generators) if g.available;init=0.)
                    delta=@variable(model,start=delta_start,base_name=prefix*"s2_delta")
                    for (i,g) in enumerate(c.generators)
                        g.available || continue
                        @constraint(model,v.pg[i]==base.pg[i]+alpha[i]*delta)
                        if haskey(s.redispatch_limits,g.id)
                            r=s.redispatch_limits[g.id];@constraint(model,-r<=v.pg[i]-base.pg[i]<=r)
                        end
                    end
                    deltas[t][id]=delta
                else
                    deltas[t][id]=_add_response_constraints!(model,s,c,base,v,prefix,:smooth)
                end
                if haskey(initial_balancing_power[t],id)
                    signal=deltas[t][id]
                    signal isa VariableRef || throw(ArgumentError("balancing start requires a response variable"))
                    set_start_value(signal,initial_balancing_power[t][id])
                end
                _couple_equipment!(model,s.control_policy,
                    fixed ? fixed_base_taps[t] : base.taps,fixed ? fixed_base_shunts[t] : base.shunts,v)
            end
        end
    end
    for t in 2:n,(i,g) in enumerate(ss[1].case.generators)
        haskey(ramp_limits,g.id) || continue
        up,down=ramp_limits[g.id];dt=duration_hours[t-1]
        if !fixed
            @constraint(model,-down*dt<=blocks[t][:base].pg[i]-blocks[t-1][:base].pg[i]<=up*dt)
        end
    end
    # Optional explicit full-replacement active reserve targets. These do not
    # replace AC contingency constraints or certify reactive/thermal feasibility.
    for (t,s) in enumerate(ss),gid in reserve_ids
        i=findfirst(g->g.id==gid,s.case.generators)
        !isnothing(i) && s.case.generators[i].available && s.case.generators[i].p_min>=0 ||
            throw(ArgumentError("reserve outage must name an online nonnegative generator"))
        sc=scenario_case(s.case,Contingency(Symbol("reserve_",gid);generator_ids=[gid]))
        alpha=_participation(s,sc)
        sum(alpha)>0 || throw(ArgumentError("reserve outage has no surviving participants"))
        for (j,g) in enumerate(sc.generators)
            g.available && alpha[j]>0 || continue
            lo,hi=_active_response_bounds(sc,j,s.reactive_assignments)
            movement=alpha[j]*(blocks[t][:base].pg[i]+reserve_margin_pu)
            @constraint(model,blocks[t][:base].pg[j]+movement<=hi)
            if haskey(s.redispatch_limits,g.id)
                @constraint(model,movement<=s.redispatch_limits[g.id])
            end
        end
    end
    loss=sum(duration_hours[t]*s.case.base_power*(sum(blocks[t][:base].pg)-sum(l.p for l in s.case.loads)) for (t,s) in enumerate(ss))
    if !isnothing(objective_upper_bound)
        isfinite(objective_upper_bound) || throw(ArgumentError("finite objective upper bound required"))
        @constraint(model,loss<=objective_upper_bound)
    end
    reserve=nothing
    if !fixed && objective_policy in (:reserve,:reserve_loss)
        reserve=@variable(model,lower_bound=0.,upper_bound=1.,base_name="minimum_upward_headroom_fraction")
        participants=0
        for (t,s) in enumerate(ss),(i,g) in enumerate(s.case.generators)
            lo,hi=_active_response_bounds(s.case,i,s.reactive_assignments)
            g.available && get(s.participation,g.id,0.)>0 && hi>lo || continue
            @constraint(model,blocks[t][:base].pg[i]+(hi-lo)*reserve<=hi)
            participants+=1
        end
        participants>0 || throw(ArgumentError("reserve objective requires participating active range"))
    end
    for (k,v) in optimizer_attributes;set_optimizer_attribute(model,k,v);end
    stages=NamedTuple[]
    objectives=(fixed || objective_policy==:feasibility) ? [(:feasibility,0.0)] : isempty(all_shed) ? [(:loss,loss)] : [(:shedding,sum(all_shed)),(:dr,sum(all_dr)),(:loss,loss)]
    if !isnothing(reserve)
        insert!(objectives,length(objectives),(:reserve,-reserve))
        objective_policy==:reserve && pop!(objectives)
    end
    for (stage_index,(name,obj)) in enumerate(objectives)
        @objective(model,Min,obj);optimize!(model)
        status=Symbol(string(termination_status(model)))
        push!(stages,(;name,status,objective=has_values(model) ? value(obj) : NaN))
        status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL) || break
        stage_index==length(objectives) && break
        optimum=value(obj);variables=all_variables(model);values=value.(variables)
        # A zero nonnegative relief optimum is globally bounded below by zero.
        # Fix that face explicitly instead of a near-zero sum inequality, which
        # otherwise gives nearly dependent active rows during subsequent stages.
        zero_resources=name==:shedding ? all_shed : name==:dr ? all_dr : Any[]
        if !isempty(zero_resources) && optimum<=1e-8
            for v in zero_resources;fix(v,0.;force=true);end
        else
            @constraint(model,obj<=optimum+1e-8)
        end
        for (v,x) in zip(variables,values)
            isfinite(x) && set_start_value(v,x)
        end
    end
    present=has_values(model);status=Symbol(string(termination_status(model)));primal=Symbol(string(primal_status(model)))
    settings=Dict{Int,DroopSettings{Float64}}()
    present && foreach(p->(settings[p.first]=DroopSettings((_droop_design_value(getfield(p.second,k)) for k in keys(p.second))...)),pars)
    targets_out=[present ? Dict{Int,Float64}(id=>value(v) for (id,v) in d) : Dict{Int,Float64}() for d in targets]
    results=SCOPFResult[];reliefout=Vector{Dict{Symbol,NamedTuple}}()
    for (t,s) in enumerate(ss)
        states=Dict{Symbol,Union{Nothing,ACState{Float64}}}();taps=Dict{Symbol,Dict{Int,Float64}}();shunts=Dict{Symbol,Dict{Int,Float64}}()
        for (id,v) in blocks[t]
            states[id]=present ? ACState(Float64.(value.(v.vm)),Float64.(value.(v.va)),Float64.(value.(v.pg)),Float64.(value.(v.qg))) : nothing
            taps[id]=!present ? Dict() : fixed && id==:base ? fixed_base_taps[t] : Dict(k=>Float64(value(x)) for (k,x) in v.taps)
            shunts[id]=!present ? Dict() : fixed && id==:base ? fixed_base_shunts[t] : Dict(k=>Float64(value(x)) for (k,x) in v.shunts)
        end
        a=_security_assignments(s.case,s.reactive_assignments,settings,targets_out[t])
        push!(results,SCOPFResult(states,Dict{Symbol,Float64}(id=>Float64(value(v)) for (id,v) in deltas[t] if present),
            present ? value(loss) : NaN,status,primal,:preventive,:smooth,Float64(smooth_epsilon),Float64(smooth_epsilon),nothing,
            solver_name(model),a,taps,shunts,s.tap_controls,s.shunt_controls,s.control_policy))
        push!(reliefout,Dict{Symbol,NamedTuple}(id=>(;dr=present ? Float64.(value.(r.dr)) : fill(NaN,length(r.dr)),
            shed=present ? Float64.(value.(r.shed)) : fill(NaN,length(r.shed))) for (id,r) in rels[t]))
    end
    MultiPeriodSecurityResult(results,settings,collect(droop_controls),reliefout,present ? value(loss) : NaN,
        status,primal,temporal.duration_hours,temporal.ramp_limits,temporal.angle_limits,response,s2_emergency,
        targets_out,bounds,Float64(avr_movement_per_hour),stages)
end

"""Replay original AC physics, exact mixed controls, circles, response, relief,
equipment bounds/timing, preventive ramps, angles and objective without solving.
"""
function validate_multi_period_security(studies,result::MultiPeriodSecurityResult;tolerance=1e-6)
    ss=Study[studies...];n=length(ss)
    n==length(result.periods)==length(result.relief)==length(result.duration_hours)==length(result.avr_targets) ||
        return (;valid=false,reason=:period_count)
    rows=NamedTuple[];policy=true;ramp_violation=0.;objective=0.;movement=0.
    controls=result.droop_controls
    policy &= result.response in (:limit_aware,:s2_proportional) &&
        all(d->isfinite(d)&&d>0,result.duration_hours)
    policy &= length(unique(c.control_id for c in controls))==length(controls) &&
        Set(keys(result.droops))==Set(c.control_id for c in controls)
    for c in controls
        p=_joint_droop_policy(ss[1].case,c);s=get(result.droops,c.control_id,nothing)
        policy &= !isnothing(s) && all(getfield(p.ranges,k)[1]-tolerance<=getfield(s,k)<=getfield(p.ranges,k)[2]+tolerance for k in keys(p.ranges))
    end
    for (t,s) in enumerate(ss)
        r=result.periods[t];base=r.states[:base]
        isnothing(base) && return (;valid=false,reason=:missing_base)
        expected=_security_assignments(s.case,s.reactive_assignments,result.droops,result.avr_targets[t])
        policy &= _json_data(expected)==_json_data(r.reactive_assignments)
        ids=Set([:base;[c.id for c in s.contingencies]])
        policy &= Set(keys(r.states))==ids && Set(keys(r.tap_settings))==ids && Set(keys(r.shunt_settings))==ids
        policy &= Set(keys(result.relief[t]))==(result.emergency ? setdiff(ids,Set([:base])) : Set{Symbol}())
        policy &= Set(keys(result.avr_targets[t]))==Set(keys(result.avr_bounds))
        for (id,b) in result.avr_bounds
            v=result.avr_targets[t][id];policy &= b[1]-tolerance<=v<=b[2]+tolerance
            t>1 && (movement=max(movement,abs(v-result.avr_targets[t-1][id])-result.avr_movement_per_hour*result.duration_hours[t-1]))
        end
        for id in ids
            state=get(r.states,id,nothing)
            isnothing(state) && return (;valid=false,reason=:missing_state)
            raw=id==:base ? s.case : scenario_case(s.case,only(c for c in s.contingencies if c.id==id))
            c=result.emergency && id!=:base ? _security_emergency_case(raw) : raw
            for (did,setting) in result.droops
                c=with_droop_settings(Study(c),did,setting).case
            end
            relief_valid=true;dr_mw=0.;shed_mw=0.
            if result.emergency && id!=:base
                rel=result.relief[t][id]
                length(rel.dr)==length(c.loads)==length(rel.shed) || return (;valid=false,reason=:relief_dimensions)
                for (i,l) in enumerate(c.loads)
                    d,h=rel.dr[i],rel.shed[i]
                    relief_valid &= -tolerance<=d<=.01max(l.p,0.)+tolerance &&
                        h>=-tolerance && d+h<=.1max(l.p,0.)+tolerance
                end
                dr_mw=sum(rel.dr)*c.base_power;shed_mw=sum(rel.shed)*c.base_power
                relief_valid &= shed_mw<=10+tolerance*c.base_power
                c=_security_relief_case(c,rel.dr,rel.shed)
            end
            taps=r.tap_settings[id];shunts=r.shunt_settings[id]
            expected_taps=Set(x.branch_id for x in _scenario_tap_controls(s,c))
            equipment_valid=Set(keys(taps))==expected_taps && Set(keys(shunts))==Set(x.bank_id for x in s.shunt_controls)
            for x in _scenario_tap_controls(s,c)
                v=get(taps,x.branch_id,NaN);equipment_valid &= x.lower-tolerance<=v<=x.upper+tolerance
            end
            for x in s.shunt_controls
                p=_shunt_policy(c,x);v=get(shunts,x.bank_id,NaN)
                equipment_valid &= p.lower-tolerance<=v<=p.upper+tolerance
            end
            if id!=:base
                for (family,timing,limits,settings) in ((:tap_settings,s.control_policy.taps,s.control_policy.tap_movement_limits,taps),
                    (:shunt_settings,s.control_policy.shunts,s.control_policy.shunt_movement_limits,shunts))
                    b=getproperty(r,family)[:base]
                    for did in intersect(Set(keys(b)),Set(keys(settings)))
                        cap=timing==:preventive ? 0. : isnothing(limits) ? Inf : get(limits,did,0.)
                        equipment_valid &= abs(settings[did]-b[did])<=cap+tolerance
                    end
                end
            end
            c=with_shunt_settings(with_tap_settings(c,taps),shunts)
            physical=validate_equilibrium(c,state;reactive_assignments=expected)
            idx=_bus_indices(c.network);angle_violation=0.;circle_margin=Inf
            reference=only(i for (i,b) in enumerate(c.network.buses) if b.reference)
            angle_violation=max(angle_violation,abs(state.va[reference]))
            for b in c.network.branches
                b.available && haskey(result.angle_limits,b.id) || continue
                lo,hi=result.angle_limits[b.id];a=state.va[idx[b.from_bus]]-state.va[idx[b.to_bus]]
                angle_violation=max(angle_violation,lo-a,a-hi)
            end
            for (i,g) in enumerate(c.generators)
                g.available && !isnothing(g.s_rated) || continue
                circle_margin=min(circle_margin,g.s_rated-hypot(state.pg[i],state.qg[i]))
            end
            response_violation=0.
            if id!=:base
                alpha=_participation(s,c);delta=get(r.balancing_power,id,NaN)
                for (i,g) in enumerate(c.generators)
                    g.available || continue
                    request=base.pg[i]+alpha[i]*delta
                    if result.response==:limit_aware
                        lo,hi=_response_bounds(s,c,i,base.pg[i]);request=clamp(request,lo,hi)
                    end
                    response_violation=max(response_violation,abs(state.pg[i]-request))
                    if haskey(s.redispatch_limits,g.id)
                        response_violation=max(response_violation,abs(state.pg[i]-base.pg[i])-s.redispatch_limits[g.id])
                    end
                end
            end
            push!(rows,(;period=t,scenario=id,valid=physical.valid&&equipment_valid&&relief_valid&&
                response_violation<=tolerance&&angle_violation<=tolerance,physical,equipment_valid,relief_valid,
                response_violation,angle_violation,circle_margin_pu=circle_margin,dr_mw,shed_mw))
        end
        objective+=result.duration_hours[t]*s.case.base_power*(sum(base.pg)-sum(l.p for l in s.case.loads))
        if t>1
            for (i,g) in enumerate(s.case.generators)
                haskey(result.ramp_limits,g.id) || continue
                up,down=result.ramp_limits[g.id];dt=result.duration_hours[t-1]
                d=base.pg[i]-result.periods[t-1].states[:base].pg[i]
                ramp_violation=max(ramp_violation,d-up*dt,-d-down*dt)
            end
        end
    end
    for stage in result.stages
        if stage.name==:reserve
            delivered=maximum((result.periods[t].states[:base].pg[i]-hi)/(hi-lo)
                for (t,s) in enumerate(ss) for (i,g) in enumerate(s.case.generators)
                for (lo,hi) in (_active_response_bounds(s.case,i,s.reactive_assignments),)
                if g.available && get(s.participation,g.id,0.)>0 && hi>lo)
            policy &= delivered<=stage.objective+1e-8+tolerance
        end
        key=stage.name==:shedding ? :shed : stage.name==:dr ? :dr : nothing
        isnothing(key) && continue
        delivered=sum(sum(getproperty(rel,key)) for period in result.relief for rel in values(period);init=0.)
        policy &= delivered<=stage.objective+1e-8+tolerance
    end
    solver=result.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL) &&
        all(p->p.termination_status==result.termination_status&&p.primal_status==result.primal_status,result.periods) &&
        all(s->s.status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL),result.stages)
    error=abs(objective-result.objective_mwh)
    (;valid=solver&&policy&&all(r->r.valid,rows)&&ramp_violation<=tolerance&&movement<=tolerance&&error<=tolerance,
        solver_valid=solver,policy_valid=policy,rows,ramp_violation,avr_movement_violation=movement,
        objective_recomputed_mwh=objective,objective_error_mwh=error)
end

# DroopControl serialization is provided by droop_security.jl.
_json_data(r::MultiPeriodSecurityResult)=Dict(string(k)=>_json_data(getfield(r,k)) for k in fieldnames(typeof(r)))
function write_multi_period_security(path,r::MultiPeriodSecurityResult)
    write(path,JSON.json(Dict("schema_version"=>1,"kind"=>"DroopOPF.MultiPeriodSecurityResult",
        "data"=>_json_data(r));pretty=true)*"\n");path
end
function read_multi_period_security(path)
    d=JSON.parsefile(path)
    d["schema_version"]==1 && d["kind"]=="DroopOPF.MultiPeriodSecurityResult" || throw(ArgumentError("unsupported security result"))
    r=d["data"]
    controls=[DroopControl(c["control_id"];slope_bounds=c["bounds"]["slope"],v_ref_bounds=c["bounds"]["v_ref"],
        deadband_low_bounds=c["bounds"]["deadband_low"],deadband_high_bounds=c["bounds"]["deadband_high"],
        initial=isnothing(c["initial"]) ? nothing : _droop_settings_from_data(c["initial"])) for c in r["droop_controls"]]
    floats(v)=[isnothing(x) ? NaN : Float64(x) for x in v]
    dictpair(d)=Dict{Int,Tuple{Float64,Float64}}(parse(Int,k)=>Tuple(Float64.(v)) for (k,v) in d)
    MultiPeriodSecurityResult([_scopf_result_from_data(x) for x in r["periods"]],
        Dict(parse(Int,k)=>_droop_settings_from_data(v) for (k,v) in r["droops"]),controls,
        [Dict{Symbol,NamedTuple}(Symbol(k)=>(;dr=floats(v["dr"]),shed=floats(v["shed"])) for (k,v) in x) for x in r["relief"]],
        isnothing(r["objective_mwh"]) ? NaN : Float64(r["objective_mwh"]),Symbol(r["termination_status"]),Symbol(r["primal_status"]),
        Float64.(r["duration_hours"]),dictpair(r["ramp_limits"]),dictpair(r["angle_limits"]),Symbol(r["response"]),r["emergency"],
        [Dict(parse(Int,k)=>Float64(v) for (k,v) in x) for x in r["avr_targets"]],dictpair(r["avr_bounds"]),
        Float64(r["avr_movement_per_hour"]),NamedTuple[(;name=Symbol(x["name"]),status=Symbol(x["status"]),
            objective=isnothing(x["objective"]) ? NaN : Float64(x["objective"])) for x in r["stages"]])
end
