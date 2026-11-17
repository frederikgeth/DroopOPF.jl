"""Numerical seed, never a security witness. Residual is system-base active power."""
struct InitializationSeed
    state::ACState{Float64}
    frequency_hz::Float64
    provenance::Symbol
    balance_residual::Float64
    bracketed::Bool
end

"""Copy/rebase a primal seed and optionally initialize frequency by bounded bisection.

The scalar balance holds guessed voltage and estimated losses fixed. Projection
changes seed injections only, never case data, controller references or limits.
The returned state still needs a native AC solve and independent validation.
"""
function prepare_initialization(case::Case,plants,responses;state=nothing,
    frequency_bounds=(case.base_frequency-2,case.base_frequency+2),
    solve_frequency::Bool=true,loss_estimate::Real=0.,provenance::Symbol=:supplied)
    validate_case(case)
    all(isfinite,frequency_bounds) && length(frequency_bounds)==2 &&
        0<frequency_bounds[1]<frequency_bounds[2] || throw(ArgumentError("invalid seed frequency bounds"))
    isfinite(loss_estimate) || throw(ArgumentError("nonfinite loss estimate"))
    if isnothing(state)
        state=ACState([clamp(1.,b.v_min,b.v_max) for b in case.network.buses],
            zeros(length(case.network.buses)),[g.initial_p for g in case.generators],
            [g.initial_q for g in case.generators])
        provenance=:flat
    end
    length(state.vm)==length(state.va)==length(case.network.buses) &&
        length(state.pg)==length(state.qg)==length(case.generators) || throw(ArgumentError("seed dimensions differ"))
    all(isfinite,vcat(state.vm,state.va,state.pg,state.qg)) && all(>(0),state.vm) ||
        throw(ArgumentError("seed must be finite with positive voltage"))
    solve_frequency && _frequency_contract(case,plants,responses,frequency_bounds,Dict())
    _check_inverter_inputs(case,plants,case.base_frequency)
    vm=Float64.(state.vm);va=Float64.(state.va);pg=Float64.(state.pg);qg=Float64.(state.qg)
    ref=findall(b->b.reference,case.network.buses)
    length(ref)==1 || throw(ArgumentError("one numerical reference required"))
    va .-= va[only(ref)]
    contexts=[_inverter_context(case,p) for p in plants]
    law_contexts=solve_frequency ? [(r,findfirst(g->g.id==r.generator_id,case.generators)) for r in responses] : []
    law_bounds=[_active_response_bounds(case,i) for (_,i) in law_contexts]
    function injections(f)
        p=copy(pg);q=copy(qg)
        for (plant,c) in zip(plants,contexts)
            r=_inverter_response(c,plant,vm[c.terminal],vm[c.regulated],f)
            p[c.gi]=r.p;q[c.gi]=r.q
        end
        if solve_frequency
            for ((law,i),(lo,hi)) in zip(law_contexts,law_bounds)
                p[i]=case.generators[i].available ? clamp(law.p_ref+law.gain_pu_per_hz*(law.f_ref_hz-f),lo,hi) : 0.
            end
        end
        for (i,g) in enumerate(case.generators)
            if !g.available;p[i]=0.;q[i]=0.;end
        end
        p,q
    end
    target=sum(l.p for l in case.loads;init=0.)+loss_estimate
    residual(f)=sum(first(injections(f)))-target
    lo,hi=Float64.(frequency_bounds);a=residual(lo);b=residual(hi)
    bracketed=solve_frequency && a>=0>=b
    f=case.base_frequency
    if bracketed
        # Prefer nominal on a flat interval, including exact saturation balance.
        if abs(residual(clamp(f,lo,hi)))>1e-10
            for _ in 1:70
                mid=(lo+hi)/2
                residual(mid)>0 ? (lo=mid) : (hi=mid)
            end
            f=(lo+hi)/2
        else
            f=clamp(f,lo,hi)
        end
    elseif solve_frequency
        candidates=(lo,clamp(f,lo,hi),hi)
        f=candidates[argmin(abs.(residual.(candidates)))]
    end
    p,q=injections(f)
    InitializationSeed(ACState(vm,va,p,q),f,provenance,residual(f),bracketed)
end

function _initialization_angles!(m,c,v,angles)
    bm=Dict(b.id=>i for (i,b) in enumerate(c.network.buses))
    for b in c.network.branches
        b.available && haskey(angles,b.id) || continue
        lo,hi=angles[b.id]
        @constraint(m,lo<=v.va[bm[b.from_bus]]-v.va[bm[b.to_bus]]<=hi)
    end
end

"""Preventive active-reference design with fixed reactive curves, gains and equipment.

`:reserve` maximizes a common symmetric fraction of each available responder's
active range, respecting base-Q apparent/current capability and frequency bounds.
`:security` minimizes normalized preventive redispatch with supplied branch
scenarios coupled by the same active references. Each scenario retains either
solved primary response or prescribed-frequency semantics. No corrective free-P
redispatch is introduced in solved-frequency scenarios. Reserves describe local
base-point capability, not guaranteed network delivery or dynamic performance.
With `reserve_fraction_target`, hold the stated fraction and minimize redispatch
instead of claiming maximum reserve. This supports explicitly bounded fallback
preparations; a failed maximum-reserve solve is never promoted to an optimum.
All powers use the case system base except inverter reference variables (plant base).
"""
function design_preventive_dispatch(case::Case,plants::AbstractVector{StaticInverter},
    responses::AbstractVector{GeneratorFrequencyResponse};initial_state,
    objective::Symbol=:reserve,contingencies=Contingency[],
    reserve_fraction_target::Union{Nothing,Real}=nothing,
    frequency_choice::Symbol=:solved,frequency_bounds=(case.base_frequency-2,case.base_frequency+2),
    branch_angle_bounds=Dict{Int,Tuple{Float64,Float64}}(),
    scenario_initial_states=Dict(),optimizer_factory=Ipopt.Optimizer,
    optimizer_attributes=Dict{String,Any}(),silent::Bool=true)
    objective in (:reserve,:security) || throw(ArgumentError("unknown preventive objective"))
    isnothing(reserve_fraction_target) || (isfinite(reserve_fraction_target) && 0<=reserve_fraction_target<=.5) ||
        throw(ArgumentError("reserve fraction target must lie in [0, 0.5]"))
    frequency_bounds[1]<=case.base_frequency<=frequency_bounds[2] ||
        throw(ArgumentError("preventive frequency bounds must contain nominal frequency"))
    frequency_choice in (:solved,:prescribed) || throw(ArgumentError("unknown frequency choice"))
    _frequency_contract(case,plants,responses,frequency_bounds,branch_angle_bounds;require_responder=frequency_choice==:solved || objective==:reserve)
    all(p->p.f_ref_hz==case.base_frequency,plants) && all(r->r.f_ref_hz==case.base_frequency,responses) ||
        throw(ArgumentError("preventive anchoring requires nominal frequency references"))
    all(co->isempty(co.generator_ids) && !isempty(co.branch_ids),contingencies) ||
        throw(ArgumentError("this design slice supports branch contingencies only"))
    m=Model(optimizer_factory);silent && set_silent(m)
    for (k,val) in optimizer_attributes;set_optimizer_attribute(m,k,val);end
    base_m,base=_build_acopf_model(case;voltage_epsilon=1e-4,reactive_relative_epsilon=1e-4,
        reactive_epsilon=nothing,silent,shared_model=m,set_objective=false,initial_state,scenario_prefix="base_")
    refs=Dict{Int,VariableRef}()
    for p in plants
        c=_inverter_context(case,p)
        ref=@variable(m,lower_bound=c.pmin,upper_bound=c.pmax,start=initial_state.pg[c.gi]/c.ratio)
        c.online || fix(ref,0.;force=true)
        refs[p.generator_id]=ref
    end
    add_static_inverter_constraints!(m,case,base,plants;active_reference_variables=refs,preventive_dispatch=true)
    _initialization_angles!(m,case,base,branch_angle_bounds)
    eta=@variable(m,lower_bound=0.,upper_bound=.5,start=0.)
    responder_indices=Int[];ranges=Dict{Int,Float64}();gains=Dict{Int,Float64}()
    for (i,g) in enumerate(case.generators)
        g.available || continue
        pi=findfirst(p->p.generator_id==g.id,plants)
        lo,hi=_active_response_bounds(case,i);gain=0.;radius=g.s_rated;imax=nothing
        bus=findfirst(b->b.id==g.bus_id,case.network.buses)
        if !isnothing(pi)
            p=plants[pi];c=_inverter_context(case,p)
            c.online || continue
            lo=max(lo,c.pmin*c.ratio);hi=min(hi,c.pmax*c.ratio)
            radius=c.s*c.ratio;imax=p.i_max*c.ratio
            gain=p.frequency_response ? c.ratio/p.p_droop_hz : 0.
        else
            law=only(r for r in responses if r.generator_id==g.id)
            gain=law.gain_pu_per_hz
        end
        gain>0 && hi>lo || continue
        push!(responder_indices,i);ranges[i]=hi-lo;gains[i]=gain
        width=hi-lo;p=base.pg[i];q=base.qg[i];v=base.vm[bus]
        @constraint(m,p+eta*width<=hi)
        @constraint(m,p-eta*width>=lo)
        @constraint(m,eta*width<=gain*min(case.base_frequency-frequency_bounds[1],frequency_bounds[2]-case.base_frequency))
        if !isnothing(radius)
            # Normalize squared constraints to avoid tiny-unit absolute residual amplification.
            @constraint(m,((p+eta*width)/radius)^2+(q/radius)^2<=1)
            @constraint(m,((p-eta*width)/radius)^2+(q/radius)^2<=1)
        end
        if !isnothing(imax)
            @constraint(m,((p+eta*width)/imax)^2+(q/imax)^2<=v^2)
            @constraint(m,((p-eta*width)/imax)^2+(q/imax)^2<=v^2)
        end
    end
    isempty(responder_indices) && !isnothing(reserve_fraction_target) && reserve_fraction_target>0 &&
        throw(ArgumentError("a positive reserve target requires an available active responder"))
    isempty(responder_indices) && fix(eta,0.;force=true)
    # Numerical scenario seeds use the initial values of the shared reference
    # decisions. These temporary declarations do not change the final constraints.
    seed_plants=[StaticInverter(;merge((; (k=>getfield(p,k) for k in fieldnames(StaticInverter))...),
        (;p_ref=initial_state.pg[_inverter_context(case,p).gi]/_inverter_context(case,p).ratio))...) for p in plants]
    seed_laws=[GeneratorFrequencyResponse(generator_id=r.generator_id,
        p_ref=initial_state.pg[findfirst(g->g.id==r.generator_id,case.generators)],
        gain_pu_per_hz=r.gain_pu_per_hz,f_ref_hz=r.f_ref_hz) for r in responses]
    states=[base];cases=[case];fs=Any[case.base_frequency]
    for (j,co) in enumerate(contingencies)
        sc=scenario_case(case,co);_check_connected(sc)
        seed=get(scenario_initial_states,j,initial_state)
        seed_frequency=case.base_frequency
        if frequency_choice==:solved
            guess=prepare_initialization(sc,seed_plants,seed_laws;state=seed,frequency_bounds,
                loss_estimate=sum(seed.pg)-sum(l.p for l in sc.loads;init=0.),provenance=:security_scenario)
            seed=guess.state;seed_frequency=guess.frequency_hz
        end
        _,v=_build_acopf_model(sc;voltage_epsilon=1e-4,reactive_relative_epsilon=1e-4,
            reactive_epsilon=nothing,silent,shared_model=m,set_objective=false,
            initial_state=seed,scenario_prefix="scenario_$(j)_")
        f=frequency_choice==:solved ? @variable(m,lower_bound=frequency_bounds[1],upper_bound=frequency_bounds[2],start=seed_frequency) : case.base_frequency
        # Ownership is scenario-local, while all references are shared.
        m.ext[:static_inverter_generator_ids]=Set{Int}()
        add_static_inverter_constraints!(m,sc,v,plants;frequency_hz=f,active_reference_variables=refs)
        if frequency_choice==:solved
            for law in responses
                i=findfirst(g->g.id==law.generator_id,sc.generators);g=sc.generators[i]
                g.available || continue
                lo,hi=_active_response_bounds(sc,i);p=v.pg[i];pref=base.pg[i];k=law.gain_pu_per_hz;f0=case.base_frequency
                @NLconstraint(m,p==min(hi,max(lo,pref+k*(f0-f))))
            end
        end
        _initialization_angles!(m,sc,v,branch_angle_bounds)
        push!(states,v);push!(cases,sc);push!(fs,f)
    end
    if objective==:reserve && isnothing(reserve_fraction_target)
        @objective(m,Max,eta)
    else
        fix(eta,isnothing(reserve_fraction_target) ? 0. : reserve_fraction_target;force=true)
        @objective(m,Min,sum(((base.pg[i]-initial_state.pg[i])/max(g.p_max-g.p_min,1e-3))^2
            for (i,g) in enumerate(case.generators) if g.available))
    end
    optimize!(m)
    status=Symbol(string(termination_status(m)));primal=Symbol(string(primal_status(m)))
    if !has_values(m)
        return (;valid=false,status,plants=collect(plants),responses=collect(responses),results=Any[],cases,
            reserve_fraction=NaN,reserves=Dict(),objective,frequency_choice,frequency_bounds,branch_angle_bounds)
    end
    designed=[StaticInverter(;merge((; (k=>getfield(p,k) for k in fieldnames(StaticInverter))...),
        (;p_ref=value(refs[p.generator_id])))...) for p in plants]
    laws=[GeneratorFrequencyResponse(generator_id=r.generator_id,
        p_ref=value(base.pg[findfirst(g->g.id==r.generator_id,case.generators)]),
        gain_pu_per_hz=r.gain_pu_per_hz,f_ref_hz=r.f_ref_hz) for r in responses]
    results=Any[]
    for (j,v) in enumerate(states)
        s=ACState(value.(v.vm),value.(v.va),value.(v.pg),value.(v.qg))
        opf=ACOPFResult{Float64}(s,objective_value(m),status,primal,1e-4,1e-4,nothing)
        f=fs[j] isa Real ? Float64(fs[j]) : value(fs[j])
        r=frequency_choice==:solved ? CommonFrequencyResult(opf,designed,laws,f,
            (Float64(frequency_bounds[1]),Float64(frequency_bounds[2])),Dict(branch_angle_bounds)) :
            StaticInverterOPFResult(opf,designed,f)
        push!(results,r)
    end
    reserves=Dict(case.generators[i].id=>value(eta)*ranges[i] for i in responder_indices)
    candidate=(;valid=false,status,plants=designed,responses=laws,results,cases,
        reserve_fraction=value(eta),reserves,objective,frequency_choice,frequency_bounds,branch_angle_bounds)
    merge(candidate,(;valid=validate_preventive_dispatch(candidate).valid))
end

"""Replay every coupled state plus declared symmetric base-point reserve endpoints."""
function validate_preventive_dispatch(r;tolerance=1e-6)
    isfinite(tolerance) && tolerance>=0 || throw(ArgumentError("invalid preventive replay tolerance"))
    isempty(r.results) && return (;valid=false,states_valid=false,reserves_valid=false)
    states_valid=length(r.cases)==length(r.results) && all(zip(r.cases,r.results)) do (c,x)
        x.plants==r.plants || return false
        if x isa CommonFrequencyResult
            x.responses==r.responses && x.frequency_bounds==r.frequency_bounds && x.branch_angle_bounds==r.branch_angle_bounds || return false
        end
        check=x isa CommonFrequencyResult ? validate_common_frequency(c,x) : validate_inverter_opf(c,x)
        bm=Dict(b.id=>i for (i,b) in enumerate(c.network.buses));s=x.opf.state
        check.valid && all(!b.available || !haskey(r.branch_angle_bounds,b.id) ||
            r.branch_angle_bounds[b.id][1]-tolerance<=s.va[bm[b.from_bus]]-s.va[bm[b.to_bus]]<=r.branch_angle_bounds[b.id][2]+tolerance for b in c.network.branches)
    end
    c=first(r.cases);s=first(r.results).opf.state
    expected=Dict{Int,Float64}()
    for (i,g) in enumerate(c.generators)
        g.available || continue
        lo,hi=_active_response_bounds(c,i)
        pi=findfirst(p->p.generator_id==g.id,r.plants)
        if !isnothing(pi)
            p=r.plants[pi];ctx=_inverter_context(c,p);ctx.online || continue
            lo=max(lo,ctx.pmin*ctx.ratio);hi=min(hi,ctx.pmax*ctx.ratio)
            gain=p.frequency_response ? ctx.ratio/p.p_droop_hz : 0.
        else
            gain=only(law.gain_pu_per_hz for law in r.responses if law.generator_id==g.id)
        end
        gain>0 && hi>lo && (expected[g.id]=r.reserve_fraction*(hi-lo))
    end
    reserve_metadata=isfinite(r.reserve_fraction) && -tolerance<=r.reserve_fraction<=.5+tolerance &&
        Set(keys(expected))==Set(keys(r.reserves)) &&
        all(abs(r.reserves[id]-amount)<=tolerance for (id,amount) in expected)
    reserves_valid=reserve_metadata && all(r.reserves) do (id,reserve)
        i=findfirst(g->g.id==id,c.generators);g=c.generators[i];lo,hi=_active_response_bounds(c,i)
        pi=findfirst(p->p.generator_id==id,r.plants);radius=g.s_rated;current=Inf;gain=0.
        if !isnothing(pi)
            p=r.plants[pi];ctx=_inverter_context(c,p);lo=max(lo,ctx.pmin*ctx.ratio);hi=min(hi,ctx.pmax*ctx.ratio)
            radius=ctx.s*ctx.ratio;current=s.vm[ctx.terminal]*p.i_max*ctx.ratio
            gain=p.frequency_response ? ctx.ratio/p.p_droop_hz : 0.
        else
            gain=only(law.gain_pu_per_hz for law in r.responses if law.generator_id==id)
        end
        isfinite(reserve) && reserve>=-tolerance && gain>0 &&
        reserve<=gain*min(c.base_frequency-r.frequency_bounds[1],r.frequency_bounds[2]-c.base_frequency)+tolerance &&
        all((-1.,1.)) do sign
            p=s.pg[i]+sign*reserve
            lo-tolerance<=p<=hi+tolerance && (isnothing(radius) || hypot(p,s.qg[i])<=radius+tolerance) &&
                hypot(p,s.qg[i])<=current+tolerance
        end
    end
    (;valid=states_valid&&reserves_valid,states_valid,reserves_valid)
end
