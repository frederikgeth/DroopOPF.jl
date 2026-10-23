"""Ordered, deterministic AC periods with fixed equipment and common droop curves.

`duration_hours[t]` weights period t's energy and is the elapsed time from
period t to t+1. `ramp_limits[id] = (up, down)` is in pu/hour on the case MVA
base. Omitted generators have no inter-period ramp restriction. There is no
initial/terminal boundary, storage, commitment, uncertainty or outage recourse.
Only loads may differ between period cases; their IDs and buses must agree.
"""
struct MultiPeriodStudy
    cases::Vector{Case}
    duration_hours::Vector{Float64}
    ramp_limits::Dict{Int,Tuple{Float64,Float64}}
    angle_limits::Dict{Int,Tuple{Float64,Float64}}
    function MultiPeriodStudy(cases;duration_hours=ones(length(cases)),
        ramp_limits=Dict(),angle_limits=Dict())
        cs=Case[cases...]
        isempty(cs) && throw(ArgumentError("at least one period is required"))
        ds=Float64[duration_hours...]
        length(ds)==length(cs) && all(x->isfinite(x)&&x>0,ds) ||
            throw(ArgumentError("one positive finite duration per period is required"))
        reference=cs[1]
        isnothing(reference.network) && throw(ArgumentError("AC network required"))
        # Compare serialized physical data, not object identity. Loads are the
        # only time-varying inputs in this initial multi-period contract.
        signature(c)=(_json_data(c.network),_json_data(c.generators),
            _json_data(c.controls),_json_data(c.attachments),c.base_power,c.base_frequency,
            [(l.id,l.bus_id) for l in c.loads])
        sig=signature(reference)
        for c in cs
            validate_case(c)
            isequal(signature(c),sig) || throw(ArgumentError(
                "periods must share ordered physical data, controls and load identities"))
        end
        ids=Set(g.id for g in reference.generators)
        ramps=Dict{Int,Tuple{Float64,Float64}}()
        for (id,limits) in ramp_limits
            id in ids && length(limits)==2 && all(x->isfinite(x)&&x>=0,limits) ||
                throw(ArgumentError("ramp limits require a known generator and finite nonnegative (up, down) rates"))
            ramps[id]=(Float64(limits[1]),Float64(limits[2]))
        end
        branches=Set(b.id for b in reference.network.branches)
        angles=Dict{Int,Tuple{Float64,Float64}}()
        for (id,limits) in angle_limits
            id in branches && length(limits)==2 && all(isfinite,limits) && limits[1]<=limits[2] ||
                throw(ArgumentError("invalid branch angle limits"))
            angles[id]=(Float64(limits[1]),Float64(limits[2]))
        end
        new(cs,ds,ramps,angles)
    end
end

"""Native multi-period result: per-period states/loss MW, shared droop settings,
and total duration-weighted loss MWh. Acceptance requires `validate_multi_period`.
"""
struct MultiPeriodResult
    periods::Vector{ACOPFResult{Float64}}
    droops::Dict{Int,DroopSettings{Float64}}
    droop_controls::Vector{DroopControl}
    objective_mwh::Float64
    termination_status::Symbol
    primal_status::Symbol
    reactive_assignments::Union{Nothing,Vector{ReactiveControlAssignment}}
end
MultiPeriodResult(a,b,c,d,e,f)=MultiPeriodResult(a,b,c,d,e,f,nothing)

"""Locally minimize duration-weighted active energy loss, with shared droop design
and per-period AC dispatch coupled by explicit generator ramp rates. Equipment
remains supplied and fixed in all periods. Uses sparse original-network AC.
"""
function optimize_multi_period(study::MultiPeriodStudy;droop_controls=DroopControl[],
    initial_states=fill(nothing,length(study.cases)),smooth_epsilon=1e-6,
    optimizer_factory=Ipopt.Optimizer,optimizer_attributes=Dict(),silent=true,reactive_assignments=nothing)
    isfinite(smooth_epsilon)&&smooth_epsilon>0 || throw(ArgumentError("invalid smoothing"))
    length(initial_states)==length(study.cases) || throw(ArgumentError("one initial state per period required"))
    length(unique(c.control_id for c in droop_controls))==length(droop_controls) ||
        throw(ArgumentError("duplicate droop controls"))
    isnothing(reactive_assignments) || validate_reactive_assignments(study.cases[1],reactive_assignments)
    _check_mixed_design(study.cases[1],reactive_assignments,droop_controls)
    model=Model(optimizer_factory)
    parameters=Dict{Int,NamedTuple}()
    for c in droop_controls
        p=_joint_droop_policy(study.cases[1],c)
        parameters[c.control_id]=NamedTuple{keys(p.ranges)}(Tuple(
            _droop_design_variable(model,"shared_$(c.control_id)_$k",getfield(p.ranges,k),
                getfield(p.initial,k);normalize=true) for k in keys(p.ranges)))
    end
    blocks=Any[]
    for (t,c) in enumerate(study.cases)
        _,v=_build_acopf_model(c;voltage_epsilon=smooth_epsilon,
            reactive_relative_epsilon=smooth_epsilon,reactive_epsilon=nothing,
            silent,optimizer_factory,initial_state=initial_states[t],shared_model=model,
            scenario_prefix="period_$(t)_",set_objective=false,
            droop_parameter_variables=parameters,sparse_balance=true,reactive_assignments)
        idx=_bus_indices(c.network)
        for b in c.network.branches
            b.available && haskey(study.angle_limits,b.id) || continue
            lo,hi=study.angle_limits[b.id]
            @constraint(model,lo<=v.va[idx[b.from_bus]]-v.va[idx[b.to_bus]]<=hi)
        end
        push!(blocks,v)
    end
    for t in 2:length(blocks), (i,g) in enumerate(study.cases[1].generators)
        haskey(study.ramp_limits,g.id) || continue
        up,down=study.ramp_limits[g.id]; dt=study.duration_hours[t-1]
        @constraint(model,-down*dt<=blocks[t].pg[i]-blocks[t-1].pg[i]<=up*dt)
    end
    @objective(model,Min,sum(study.duration_hours[t]*c.base_power*
        (sum(blocks[t].pg)-sum(l.p for l in c.loads)) for (t,c) in enumerate(study.cases)))
    silent && set_silent(model)
    for (k,v) in optimizer_attributes;set_optimizer_attribute(model,k,v);end
    optimize!(model)
    present=has_values(model)
    status=Symbol(string(termination_status(model)));primal=Symbol(string(primal_status(model)))
    droops=Dict{Int,DroopSettings{Float64}}()
    if present
        for (id,p) in parameters
            droops[id]=DroopSettings((_droop_design_value(getfield(p,k)) for k in keys(p))...)
        end
    end
    periods=ACOPFResult{Float64}[]
    for (t,c) in enumerate(study.cases)
        v=blocks[t]
        state=present ? ACState(value.(v.vm),value.(v.va),value.(v.pg),value.(v.qg)) : nothing
        loss=present ? c.base_power*(sum(state.pg)-sum(l.p for l in c.loads)) : NaN
        push!(periods,ACOPFResult{Float64}(state,loss,status,primal,
            Float64(smooth_epsilon),Float64(smooth_epsilon),nothing))
    end
    MultiPeriodResult(periods,droops,collect(droop_controls),
        present ? objective_value(model) : NaN,status,primal,
        _settings_assignments(study.cases[1],reactive_assignments,droops))
end

"""Independent original-network, exact-droop, shared-design, ramp, angle and
energy-objective replay. Native convergence is required separately from physics.
"""
function validate_multi_period(study::MultiPeriodStudy,result::MultiPeriodResult;
    tolerance=1e-6,kwargs...)
    isfinite(tolerance)&&tolerance>=0 || throw(ArgumentError("invalid tolerance"))
    n=length(study.cases)
    length(result.periods)==n || return (;valid=false,reason=:period_count)
    policy=Set(keys(result.droops))==Set(c.control_id for c in result.droop_controls) &&
        length(unique(c.control_id for c in result.droop_controls))==length(result.droop_controls)
    for c in result.droop_controls
        p=_joint_droop_policy(study.cases[1],c);s=get(result.droops,c.control_id,nothing)
        policy &= !isnothing(s) && all(getfield(p.ranges,k)[1]-tolerance<=getfield(s,k)<=
            getfield(p.ranges,k)[2]+tolerance for k in keys(p.ranges))
    end
    reports=Any[];ramp_violation=0.;angle_violation=0.;energy=0.;period_objective_error=0.
    for (t,c) in enumerate(study.cases)
        physical=c
        for (id,s) in result.droops
            physical=with_droop_settings(Study(physical),id,s).case
        end
        r=result.periods[t]
        if isnothing(r.state)
            return (;valid=false,reason=:missing_state)
        end
        push!(reports,validate_equilibrium(physical,r;reactive_assignments=result.reactive_assignments,kwargs...))
        loss=c.base_power*(sum(r.state.pg)-sum(l.p for l in c.loads))
        energy+=study.duration_hours[t]*loss
        period_objective_error=max(period_objective_error,abs(loss-r.objective))
        idx=_bus_indices(c.network)
        for b in c.network.branches
            b.available && haskey(study.angle_limits,b.id) || continue
            lo,hi=study.angle_limits[b.id];a=r.state.va[idx[b.from_bus]]-r.state.va[idx[b.to_bus]]
            angle_violation=max(angle_violation,lo-a,a-hi)
        end
        if t>1
            for (i,g) in enumerate(c.generators)
                haskey(study.ramp_limits,g.id) || continue
                up,down=study.ramp_limits[g.id];dt=study.duration_hours[t-1]
                delta=r.state.pg[i]-result.periods[t-1].state.pg[i]
                ramp_violation=max(ramp_violation,delta-up*dt,-delta-down*dt)
            end
        end
    end
    solver=result.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL) &&
        all(r.termination_status==result.termination_status && r.primal_status==result.primal_status for r in result.periods)
    error=abs(energy-result.objective_mwh)
    (;valid=solver && policy && all(r.valid for r in reports) &&
        ramp_violation<=tolerance && angle_violation<=tolerance && error<=tolerance && period_objective_error<=tolerance,
        solver_valid=solver,policy_valid=policy,periods=reports,ramp_violation,
        angle_violation,period_objective_error_mw=period_objective_error,objective_recomputed_mwh=energy,objective_error_mwh=error)
end
