# Static reactive laws and coupled operating/probe witnesses. No dynamic model.
export StaticReactiveLaw, StaticWitness, static_reactive_output,
       validate_static_reactive, optimize_static_witnesses, validate_static_witnesses, static_witness_metrics

"""Explicit system-base static reactive law with optional terminal current limit.

Current limits restrict the feasible P/Q state; they never change active response.
Supported modes: droop, AVR with Q-limit release, fixed Q/PF, piecewise Q(V),
SVC (bounded B(V) times terminal V²), and STATCOM (Q(V) with current capability).
This is not a technology classifier, current-priority projection or dynamic model.
"""
struct StaticReactiveLaw
    generator_id::Int
    mode::Symbol
    measured_bus::Int
    parameters::NamedTuple
    current_limit::Union{Nothing,Float64}
    function StaticReactiveLaw(id::Integer,mode::Symbol,bus::Integer;
        current_limit=nothing,kwargs...)
        id>0 && bus>0 || throw(ArgumentError("positive identities required"))
        mode in (:droop,:avr,:fixed_q,:fixed_pf,:piecewise,:svc,:statcom,:smooth_droop,:smooth_avr) || throw(ArgumentError("unsupported reactive law"))
        required= mode==:smooth_droop ? (:q_ref,:gain,:v_ref,:deadband,:voltage_epsilon,:reactive_epsilon) :
            mode==:smooth_avr ? (:v_ref,:projection_gain,:reactive_epsilon) : mode in (:droop,:statcom) ? (:q_ref,:gain,:v_ref,:deadband) :
            mode==:avr ? (:v_ref,) : mode==:fixed_q ? (:q_ref,) :
            mode==:fixed_pf ? (:q_over_p,) : mode==:piecewise ? (:voltages,:reactive,:extrapolation) :
            (:b_ref,:b_min,:b_max,:gain,:v_ref,:deadband)
        Set(keys(kwargs))==Set(required) || throw(ArgumentError("exact explicit law parameters required"))
        p=(;kwargs...)
        for v in values(p)
            v isa Number && !isfinite(v) && throw(ArgumentError("nonfinite law parameter"))
        end
        if mode in (:droop,:statcom,:svc,:smooth_droop)
            p.gain>0 && p.v_ref>0 && p.deadband>=0 || throw(ArgumentError("invalid droop parameters"))
        elseif mode in (:avr,:smooth_avr)
            p.v_ref>0 || throw(ArgumentError("positive AVR target required"))
        elseif mode==:piecewise
            length(p.voltages)==length(p.reactive)>=2 && all(isfinite,p.voltages) && all(isfinite,p.reactive) &&
                all(diff(p.voltages).>0) && p.extrapolation in (:clamp,:linear) || throw(ArgumentError("invalid knots/extrapolation"))
        end
        mode in (:smooth_droop,:smooth_avr) && !(p.reactive_epsilon>0) && throw(ArgumentError("positive explicit reactive smoothing width required"))
        mode==:smooth_droop && !(p.voltage_epsilon>0) && throw(ArgumentError("positive voltage smoothing width required"))
        mode==:smooth_avr && !(p.projection_gain>0) && throw(ArgumentError("positive AVR projection gain required"))
        mode==:svc && !(p.b_min<=p.b_ref<=p.b_max) && throw(ArgumentError("invalid SVC bounds"))
        isnothing(current_limit) || (isfinite(current_limit)&&current_limit>0) || throw(ArgumentError("invalid current limit"))
        mode==:statcom && isnothing(current_limit) && throw(ArgumentError("STATCOM requires current capability"))
        new(Int(id),mode,Int(bus),p,isnothing(current_limit) ? nothing : Float64(current_limit))
    end
end

function _static_law_context(case,laws)
    ids=[g.id for g in case.generators]
    Set(x.generator_id for x in laws)==Set(ids) && length(laws)==length(ids) || throw(ArgumentError("one law per generator required"))
    buses=Dict(b.id=>i for (i,b) in enumerate(case.network.buses))
    for law in laws
        haskey(buses,law.measured_bus) || throw(ArgumentError("unknown measurement bus"))
        g=only(g for g in case.generators if g.id==law.generator_id)
        law.mode==:svc && !(g.p_min==g.p_max==g.initial_p==0) && throw(ArgumentError("ideal SVC has zero active capability"))
    end
    Dict(l.generator_id=>l for l in laws),buses
end

function _static_bounds(g,law,p,v)
    low=g.q_min;high=g.q_max
    for r in (g.s_rated,isnothing(law.current_limit) ? nothing : law.current_limit*v)
        isnothing(r) && continue
        cap=sqrt(max(r*r-p*p,0.));low=max(low,-cap);high=min(high,cap)
    end
    low,high
end

"""Exact requested/clipped Q. AVR uses Q as the projection's fixed-point input."""
function static_reactive_output(g,law::StaticReactiveLaw,p,q,terminal_v,measured_v;settings=nothing)
    !g.available && return 0.
    par=law.parameters;lo,hi=_static_bounds(g,law,p,terminal_v)
    gain=isnothing(settings) || !haskey(settings,:gain) ? get(par,:gain,0.) : settings.gain
    ref=isnothing(settings) || !haskey(settings,:v_ref) ? get(par,:v_ref,1.) : settings.v_ref
    if law.mode==:fixed_q
        return par.q_ref # fixed Q is not silently released at a capability boundary
    elseif law.mode==:fixed_pf
        desired=par.q_over_p*p
    elseif law.mode==:piecewise
        x=par.extrapolation==:clamp ? clamp(measured_v,first(par.voltages),last(par.voltages)) : measured_v
        j=clamp(searchsortedlast(par.voltages,x),1,length(par.voltages)-1)
        desired=par.reactive[j]+(par.reactive[j+1]-par.reactive[j])/(par.voltages[j+1]-par.voltages[j])*(x-par.voltages[j])
    elseif law.mode in (:avr,:smooth_avr)
        desired=q+(law.mode==:smooth_avr ? par.projection_gain : 1.)*(ref-measured_v)
    elseif law.mode==:smooth_droop
        action=par.deadband==0 ? ref-measured_v : _smooth_positive(ref-par.deadband-measured_v,par.voltage_epsilon)-_smooth_positive(measured_v-ref-par.deadband,par.voltage_epsilon)
        desired=par.q_ref+gain*action
    else
        e=measured_v-ref;action=max(e-par.deadband,0)-max(-e-par.deadband,0)
        desired=law.mode==:svc ? clamp(par.b_ref-gain*action,par.b_min,par.b_max)*terminal_v^2 : par.q_ref-gain*action
    end
    law.mode in (:smooth_droop,:smooth_avr) && return lo+_smooth_positive(desired-lo,par.reactive_epsilon)-_smooth_positive(desired-hi,par.reactive_epsilon)
    clamp(desired,lo,hi)
end

function validate_static_reactive(case::Case,state::ACState,laws;settings=Dict(),tolerance=1e-8)
    isfinite(tolerance)&&tolerance>=0 || throw(ArgumentError("invalid tolerance"))
    byid,bus=_static_law_context(case,laws);rows=[]
    length(state.pg)==length(case.generators) && length(state.vm)==length(case.network.buses) || throw(ArgumentError("state dimensions"))
    for (i,g) in enumerate(case.generators)
        l=byid[g.id];p=state.pg[i];q=state.qg[i];v=state.vm[bus[g.bus_id]];mv=state.vm[bus[l.measured_bus]]
        lo,hi=_static_bounds(g,l,p,v)
        target=static_reactive_output(g,l,p,q,v,mv;settings=get(settings,g.id,nothing))
        radius_ok=!g.available || ((isnothing(g.s_rated)||hypot(p,q)<=g.s_rated+tolerance) &&
            (isnothing(l.current_limit)||hypot(p,q)<=l.current_limit*v+tolerance))
        valid=abs(q-target)<=tolerance && radius_ok && (!g.available || lo-tolerance<=q<=hi+tolerance)
        push!(rows,(;generator_id=g.id,valid,residual=abs(q-target),capability_valid=radius_ok))
    end
    (;valid=all(x.valid for x in rows),rows)
end

"""One state in a shared static design. anchor=0 permits preventive scheduling.

A positive anchor references an earlier ordinary preventive state and enforces
limit-aware automatic active response to its actual PG. Only explicit probe
states may have nonzero test_q; test Q is a fixed conditional experiment, never
operating supply. Controls/equipment/load data of a recourse state must match its
anchor except device outages. Independent capability contexts may be separate
base witnesses and share the selected controller parameters.
"""
struct StaticWitness
    case::Case
    laws::Vector{StaticReactiveLaw}
    anchor::Int
    test_bus::Union{Nothing,Int}
    test_q::Float64
    participation::Dict{Int,Float64}
    weight::Float64
    angle_limits::Dict{Int,Tuple{Float64,Float64}}
    function StaticWitness(c::Case,laws;anchor::Integer=0,test_bus=nothing,test_q::Real=0.,
        participation=nothing,weight::Real=0.,angle_limits=Dict())
        validate_case(c);_check_connected(c);_static_law_context(c,laws)
        anchor>=0 && isfinite(test_q) && isfinite(weight) && weight>=0 || throw(ArgumentError("invalid witness parameters"))
        isempty(c.attachments) || throw(ArgumentError("static laws require sole reactive ownership"))
        test_q!=0 && (anchor==0 || isnothing(test_bus)) && throw(ArgumentError("virtual Q requires anchored explicit probe"))
        isnothing(test_bus) || any(b.id==test_bus for b in c.network.buses) || throw(ArgumentError("unknown test bus"))
        weight>0 && (anchor!=0 || !isnothing(test_bus)) && throw(ArgumentError("objective weights only on ordinary bases"))
        weights=isnothing(participation) ? default_participation(c) : Dict{Int,Float64}(participation)
        all(isfinite(w)&&w>=0 for w in values(weights)) && all(id in [g.id for g in c.generators] for id in keys(weights)) || throw(ArgumentError("invalid participation"))
        angles=Dict{Int,Tuple{Float64,Float64}}(angle_limits)
        all(any(b.id==id for b in c.network.branches)&&isfinite(lo)&&isfinite(hi)&&lo<=hi for (id,(lo,hi)) in angles) || throw(ArgumentError("invalid angle limits"))
        new(c,StaticReactiveLaw[laws...],Int(anchor),isnothing(test_bus) ? nothing : Int(test_bus),Float64(test_q),weights,Float64(weight),angles)
    end
end

function _static_probe_case(w)
    isnothing(w.test_bus) && return w.case
    c=w.case;id=maximum((l.id for l in c.loads);init=0)+1
    Case(c.id*"/conditional-Q";base_power=c.base_power,base_frequency=c.base_frequency,network=c.network,
        loads=[c.loads;Load(id,w.test_bus;p=0.,q=-w.test_q)],generators=c.generators,controls=c.controls,attachments=c.attachments)
end

function _static_witness_contract(ws,bounds)
    isempty(ws) && throw(ArgumentError("witnesses required"))
    for (i,w) in enumerate(ws)
        w.anchor<i || throw(ArgumentError("anchor must precede state"))
        if w.anchor>0
            a=ws[w.anchor];a.anchor==0 && isnothing(a.test_bus) || throw(ArgumentError("anchor must be an ordinary preventive state"))
            c=w.case;b=a.case
            # Exact physical and policy match; availability may only be removed.
            _json_data(c.loads)==_json_data(b.loads) && _json_data(c.network.buses)==_json_data(b.network.buses) &&
                _json_data(c.network.shunts)==_json_data(b.network.shunts) && _json_data(c.network.banks)==_json_data(b.network.banks) &&
                c.base_power==b.base_power && c.base_frequency==b.base_frequency || throw(ArgumentError("recourse changed physical data"))
            _json_data(w.laws)==_json_data(a.laws) && w.participation==a.participation && w.angle_limits==a.angle_limits || throw(ArgumentError("recourse changed controls/response"))
            length(c.generators)==length(b.generators) && length(c.network.branches)==length(b.network.branches) || throw(ArgumentError("recourse identities"))
            for (g,h) in zip(c.generators,b.generators)
                (g.id,g.bus_id,g.p_min,g.p_max,g.q_min,g.q_max,g.s_rated)==(h.id,h.bus_id,h.p_min,h.p_max,h.q_min,h.q_max,h.s_rated) && (!g.available||h.available) || throw(ArgumentError("recourse changed generator"))
            end
            for (g,h) in zip(c.network.branches,b.network.branches)
                all(getfield(g,k)==getfield(h,k) for k in fieldnames(typeof(g)) if k!=:available) && (!g.available||h.available) || throw(ArgumentError("recourse changed branch"))
            end
        end
    end
    for (id,b) in bounds
        Set(keys(b)) in (Set((:gain,:v_ref)),Set((:v_ref,))) || throw(ArgumentError("explicit gain/reference or AVR reference bounds required"))
        all(length(x)==2&&all(isfinite,x)&&0<x[1]<=x[2] for x in values(b)) || throw(ArgumentError("invalid design bounds"))
        for w in ws
            law=only(l for l in w.laws if l.generator_id==id)
            if law.mode in (:avr,:smooth_avr)
                Set(keys(b))==Set((:v_ref,)) || throw(ArgumentError("AVR design changes only the target"))
            else
                law.mode in (:droop,:statcom,:smooth_droop) && Set(keys(b))==Set((:gain,:v_ref)) || throw(ArgumentError("shared droop design requires gain/reference bounds"))
            end
        end
    end
    nothing
end

function _static_law_constraints!(model,c,vars,laws,settings)
    byid,bus=_static_law_context(c,laws)
    for (i,g) in enumerate(c.generators)
        !g.available && continue
        l=byid[g.id];p=l.parameters;pg=vars.pg[i];qg=vars.qg[i];v=vars.vm[bus[g.bus_id]];mv=vars.vm[bus[l.measured_bus]]
        lo=g.q_min;hi=g.q_max
        for radius in (g.s_rated,isnothing(l.current_limit) ? nothing : @NLexpression(model,l.current_limit*v))
            isnothing(radius) && continue
            @NLconstraint(model,pg^2+qg^2<=radius^2)
            # Numerical derivative guard only; exact circles above retain limits.
            cap=@NLexpression(model,sqrt(max(radius^2-pg^2,1e-20)))
            lo=@NLexpression(model,max(lo,-cap));hi=@NLexpression(model,min(hi,cap))
        end
        setting=get(settings,g.id,nothing)
        gain=isnothing(setting) ? get(p,:gain,0.) : get(setting,:gain,get(p,:gain,0.))
        ref=isnothing(setting) ? get(p,:v_ref,1.) : setting.v_ref
        if l.mode==:fixed_q
            @constraint(model,qg==p.q_ref);continue
        elseif l.mode==:fixed_pf
            desired=@NLexpression(model,p.q_over_p*pg)
        elseif l.mode in (:avr,:smooth_avr)
            projection=l.mode==:smooth_avr ? p.projection_gain : 1.
            desired=@NLexpression(model,qg+projection*(ref-mv))
        elseif l.mode==:smooth_droop
            if p.deadband==0
                desired=@NLexpression(model,p.q_ref+gain*(ref-mv))
            else
                op=gensym(:static_voltage_softplus);JuMP.register(model,op,1,z->_smooth_positive(z,p.voltage_epsilon);autodiff=true)
                action=JuMP.add_nonlinear_expression(model,Expr(:call,:-,Expr(:call,op,Expr(:call,:-,Expr(:call,:-,ref,p.deadband),mv)),Expr(:call,op,Expr(:call,:-,Expr(:call,:-,mv,ref),p.deadband))))
                desired=@NLexpression(model,p.q_ref+gain*action)
            end
        elseif l.mode==:piecewise
            xs=p.voltages;ys=p.reactive
            x=p.extrapolation==:clamp ? @NLexpression(model,min(xs[end],max(xs[1],mv))) : mv
            slopes=diff(ys)./diff(xs);desired=@NLexpression(model,ys[1]+slopes[1]*(x-xs[1]))
            for k in 2:length(slopes)
                dm=slopes[k]-slopes[k-1];knot=xs[k]
                desired=@NLexpression(model,desired+dm*max(x-knot,0.))
            end
        else
            action=@NLexpression(model,max(mv-ref-p.deadband,0.)-max(ref-mv-p.deadband,0.))
            desired=l.mode==:svc ? @NLexpression(model,min(p.b_max,max(p.b_min,p.b_ref-gain*action))*v^2) : @NLexpression(model,p.q_ref-gain*action)
        end
        if l.mode in (:smooth_droop,:smooth_avr)
            op=gensym(:static_reactive_softplus);JuMP.register(model,op,1,z->_smooth_positive(z,p.reactive_epsilon);autodiff=true)
            clip=Expr(:call,:+,lo,Expr(:call,:-,Expr(:call,op,Expr(:call,:-,desired,lo)),Expr(:call,op,Expr(:call,:-,desired,hi))))
            JuMP.add_nonlinear_constraint(model,Expr(:call,Symbol("=="),qg,clip))
        else
            @NLconstraint(model,qg==min(hi,max(lo,desired)))
        end
    end
end

"""Solve one coupled native AC model for heterogeneous static witnesses.

Shares explicitly selected gains/references and optional preventive taps/banks.
Equipment settings are common to every witness, with zero corrective movement;
unselected equipment stays fixed. Base P is
scheduled independently, anchored P response saturates at equipment limits, and
probe Q is fixed. No feasibility slack, relief or implicit current-priority P
clipping is added. A finite probe endpoint needs independent path qualification.
"""
# Common preventive equipment: a single physical setting across all witnesses.
# Outaged selected branches have no electrical tap variable in that witness.
function _static_equipment_contract(ws,taps,shunts)
    first=ws[1].case
    _check_tap_controls(first,taps);_check_shunt_controls(first,shunts)
    for w in ws
        for t in taps
            b=only(b for b in first.network.branches if b.id==t.branch_id)
            c=only(b for b in w.case.network.branches if b.id==t.branch_id)
            all(getfield(b,k)==getfield(c,k) for k in fieldnames(typeof(b)) if k!=:available) || throw(ArgumentError("shared tap physical data differ"))
        end
        for sh in shunts
            _json_data(_simple_bank(first,sh.bank_id))==_json_data(_simple_bank(w.case,sh.bank_id)) || throw(ArgumentError("shared bank data differ"))
        end
    end
end

function _static_cost_contract(ws,costs)
    isempty(costs) && return
    ids=Set(g.id for w in ws for g in w.case.generators)
    all(id in ids for id in keys(costs)) || throw(ArgumentError("unknown cost generator"))
    all(haskey(costs,g.id) for w in ws for g in w.case.generators if g.available) || throw(ArgumentError("missing online generator cost"))
    for lines in values(costs)
        !isempty(lines) && all(length(x)==2 && all(isfinite,x) for x in lines) && issorted(first.(lines)) || throw(ArgumentError("finite convex PWL segments required, in pu-P coordinates"))
    end
end

"""Recompute objective metrics on materialized physical states. Cost units are
explicit input PWL units; Q reserve is distance to each effective Q limit divided
by that generator's declared Q-box width. Security margin additionally includes
voltage-band and both-terminal rating fractions. Neither is deliverable Q reserve.
"""
function static_witness_metrics(witnesses,result;generation_costs=Dict())
    ws=StaticWitness[witnesses...];length(ws)==length(result.states) || throw(ArgumentError("state count"))
    _static_cost_contract(ws,generation_costs)
    loss=0.;cost=0.;vd=0.;qr=.5;network=.5
    for (i,w) in enumerate(ws)
        c=_static_probe_case(w);isempty(result.taps)||(c=with_tap_settings(c,result.taps));isempty(result.susceptances)||(c=with_shunt_settings(c,result.susceptances));st=result.states[i]
        loss+=w.weight*c.base_power*(sum(st.pg)-sum(l.p for l in c.loads))
        if !isempty(generation_costs)
            cost+=w.weight*sum(maximum(m*st.pg[j]+b for (m,b) in generation_costs[g.id]) for (j,g) in enumerate(c.generators) if g.available)
        end
        vd+=sum(((v-1.)/.1)^2 for v in st.vm)/(length(ws)*length(st.vm))
        idx=Dict(b.id=>j for (j,b) in enumerate(c.network.buses))
        for (j,g) in enumerate(c.generators)
            (!g.available || g.q_max==g.q_min) && continue
            lo=g.q_min;hi=g.q_max;width=hi-lo;l=only(l for l in w.laws if l.generator_id==g.id)
            for rating in (g.s_rated,isnothing(l.current_limit) ? nothing : l.current_limit*st.vm[idx[g.bus_id]])
                isnothing(rating)&&continue
                cap=sqrt(max(0.,rating^2-st.pg[j]^2));lo=max(lo,-cap);hi=min(hi,cap)
            end
            qr=min(qr,(st.qg[j]-lo)/width,(hi-st.qg[j])/width)
        end
        for (j,b) in enumerate(c.network.buses)
            width=b.v_max-b.v_min
            network=min(network,width>0 ? min(st.vm[j]-b.v_min,b.v_max-st.vm[j])/width : 0.)
        end
        flows=branch_flows(c.network,st)
        for (j,b) in enumerate(c.network.branches)
            b.available || continue
            network=min(network,b.thermal_limit>0 ? 1-max(abs(flows.from[j]),abs(flows.to[j]))/b.thermal_limit : 0.)
        end
    end
    (;loss,cost=isempty(generation_costs) ? nothing : cost,q_reserve=qr,security_margin=min(qr,network),voltage_deviation=vd)
end

function optimize_static_witnesses(witnesses;design_bounds=Dict(),initial_parameters=Dict(),
    initial_states=fill(nothing,length(witnesses)),initial_signals=zeros(length(witnesses)),
    optimizer_factory=Ipopt.Optimizer,optimizer_attributes=Dict(),objective=:loss,dispatch_reference=nothing,silent=true,
    tap_controls=TapControl[],shunt_controls=ShuntControl[],
    generation_costs=Dict(),cost_scale=1e4,objective_limits=Dict())
    ws=StaticWitness[witnesses...];_static_witness_contract(ws,design_bounds)
    _static_equipment_contract(ws,tap_controls,shunt_controls)
    objective in (:loss,:feasibility,:dispatch,:cost,:q_reserve,:security_margin,:voltage_deviation) || throw(ArgumentError("unknown objective"))
    _static_cost_contract(ws,generation_costs)
    (objective!=:cost && !haskey(objective_limits,:cost)) || !isempty(generation_costs) || throw(ArgumentError("explicit costs required"))
    isfinite(cost_scale)&&cost_scale>0 || throw(ArgumentError("positive cost scale required"))
    all(k in (:loss,:cost,:q_reserve,:security_margin,:voltage_deviation) && isfinite(v) for (k,v) in objective_limits) || throw(ArgumentError("invalid objective limit"))
    all(!(k in (:q_reserve,:security_margin)) || 0<=v<=.5 for (k,v) in objective_limits) || throw(ArgumentError("reserve fraction outside0–0.5"))
    length(initial_states)==length(initial_signals)==length(ws) || throw(ArgumentError("one start per witness"))
    all(isfinite,initial_signals) || throw(ArgumentError("nonfinite signal starts"))
    model=Model(optimizer_factory);silent&&set_silent(model)
    for (k,v) in optimizer_attributes;set_optimizer_attribute(model,k,v);end
    settings=Dict{Int,NamedTuple}()
    for (id,b) in design_bounds
        l=only(l for l in ws[1].laws if l.generator_id==id);init=get(initial_parameters,id,haskey(b,:gain) ? (;gain=l.parameters.gain,v_ref=l.parameters.v_ref) : (;v_ref=l.parameters.v_ref))
        Set(keys(init))==Set(keys(b)) && all(b[k][1]<=init[k]<=b[k][2] for k in keys(b)) || throw(ArgumentError("design start outside bounds"))
        gain=haskey(b,:gain) ? @variable(model,lower_bound=b.gain[1],upper_bound=b.gain[2],start=init.gain,base_name="gain_$id") : nothing
        ref=@variable(model,lower_bound=b.v_ref[1],upper_bound=b.v_ref[2],start=init.v_ref,base_name="reference_$id")
        settings[id]=isnothing(gain) ? (;v_ref=ref) : (;gain,v_ref=ref)
    end
    need_security=objective==:security_margin || haskey(objective_limits,:security_margin)
    need_q=need_security || objective==:q_reserve || haskey(objective_limits,:q_reserve)
    # A prescribed floor has no objective incentive to increase. Substitute it
    # exactly rather than adding global auxiliary columns/slack degeneracy to
    # every scenario. Primary reserve maximization retains variable headroom.
    qfloor=max(get(objective_limits,:q_reserve,0.),get(objective_limits,:security_margin,0.))
    sfloor=get(objective_limits,:security_margin,0.)
    qr=need_q ? (objective in (:q_reserve,:security_margin) ? @variable(model,lower_bound=0.,upper_bound=.5,start=qfloor,base_name="q_headroom") : qfloor) : nothing
    sm=need_security ? (objective==:security_margin ? @variable(model,lower_bound=0.,upper_bound=.5,start=sfloor,base_name="network_headroom") : sfloor) : nothing
    need_security && !(qr isa Number && sm isa Number) && @constraint(model,sm<=qr)
    variables=[];signals=Any[];shared_taps=Dict{Int,Any}();shared_shunts=Dict{Int,Any}()
    for (i,w) in enumerate(ws)
        c=_static_probe_case(w);free=[ReactiveControlAssignment(g.id,FreeQ()) for g in c.generators]
        active_taps=[t for t in tap_controls if only(b for b in c.network.branches if b.id==t.branch_id).available]
        _,vars=_build_acopf_model(c;voltage_epsilon=1e-9,reactive_relative_epsilon=1e-9,reactive_epsilon=nothing,
            silent,shared_model=model,scenario_prefix="w$(i)_",set_objective=false,initial_state=initial_states[i],
            reactive_assignments=free,sparse_balance=true,
            tap_controls=isempty(tap_controls)&&!need_security ? nothing : active_taps,
            shunt_controls=isempty(shunt_controls) ? nothing : shunt_controls,
            thermal_margin=need_security ? sm : 0.)
        for (localvars,shared) in ((vars.taps,shared_taps),(vars.shunts,shared_shunts))
            for (id,x) in localvars
                if haskey(shared,id)
                    @constraint(model,x==shared[id])
                else
                    shared[id]=x
                end
            end
        end
        push!(variables,vars);_static_law_constraints!(model,c,vars,w.laws,settings)
        bus=Dict(b.id=>j for (j,b) in enumerate(c.network.buses))
        if need_q
            for (j,g) in enumerate(c.generators)
                (!g.available || g.q_max==g.q_min) && continue
                width=g.q_max-g.q_min;qg=vars.qg[j];pg=vars.pg[j];v=vars.vm[bus[g.bus_id]];law=only(l for l in w.laws if l.generator_id==g.id)
                @constraint(model,qg>=g.q_min+qr*width);@constraint(model,qg<=g.q_max-qr*width)
                for direction in (-1.,1.)
                    isnothing(g.s_rated) || @NLconstraint(model,pg^2+(qg+direction*qr*width)^2<=g.s_rated^2)
                    isnothing(law.current_limit) || @NLconstraint(model,pg^2+(qg+direction*qr*width)^2<=(law.current_limit*v)^2)
                end
            end
        end
        if need_security
            all(b.thermal_limit>0 for b in c.network.branches if b.available) || throw(ArgumentError("security margin requires positive ratings"))
            for (j,b) in enumerate(c.network.buses)
                width=b.v_max-b.v_min;width>0||throw(ArgumentError("security margin requires voltage band"))
                @constraint(model,vars.vm[j]>=b.v_min+sm*width);@constraint(model,vars.vm[j]<=b.v_max-sm*width)
            end
        end
        for b in c.network.branches
            !b.available && continue
            if haskey(w.angle_limits,b.id)
                lo,hi=w.angle_limits[b.id];@constraint(model,lo<=vars.va[bus[b.from_bus]]-vars.va[bus[b.to_bus]]<=hi)
            end
        end
        if w.anchor==0
            push!(signals,0.)
        else
            delta=@variable(model,start=initial_signals[i],base_name="signal_$i");push!(signals,delta);base=variables[w.anchor]
            for (j,g) in enumerate(c.generators)
                !g.available && continue
                lo=max(g.p_min,isnothing(g.s_rated) ? -Inf : -g.s_rated);hi=min(g.p_max,isnothing(g.s_rated) ? Inf : g.s_rated)
                weight=get(w.participation,g.id,0.);pg=vars.pg[j];bp=base.pg[j]
                if weight==0 || hi==lo
                    @constraint(model,pg==bp)
                else
                    @NLconstraint(model,pg==min(hi,max(lo,bp+weight*delta)))
                end
            end
        end
    end
    loss_expr=@expression(model,sum(w.weight*w.case.base_power*(sum(variables[i].pg)-sum(l.p for l in w.case.loads)) for (i,w) in enumerate(ws)))
    vd_expr=@expression(model,sum(sum(((v-1.)/.1)^2 for v in vars.vm)/length(vars.vm) for vars in variables)/length(ws))
    cost_terms=Any[]
    if !isempty(generation_costs)
        for (i,w) in enumerate(ws)
            w.weight>0 || continue
            for (j,g) in enumerate(w.case.generators)
                g.available || continue
                z=@variable(model,start=0.,base_name="cost_$(i)_$(g.id)")
                for (m,b) in generation_costs[g.id];@constraint(model,z>=(m*variables[i].pg[j]+b)/cost_scale);end
                push!(cost_terms,w.weight*z*cost_scale)
            end
        end
    end
    cost_expr=@expression(model,sum(cost_terms;init=0.))
    for (key,bound) in objective_limits
        if key==:q_reserve;qr isa Number || @constraint(model,qr>=bound)
        elseif key==:security_margin;sm isa Number || @constraint(model,sm>=bound)
        elseif key==:loss;@constraint(model,loss_expr<=bound)
        elseif key==:cost;@constraint(model,cost_expr/cost_scale<=bound/cost_scale)
        else;@constraint(model,vd_expr<=bound)
        end
    end
    if objective==:loss
        @objective(model,Min,loss_expr)
    elseif objective==:cost
        @objective(model,Min,cost_expr/cost_scale)
    elseif objective==:q_reserve
        @objective(model,Min,-qr)
    elseif objective==:security_margin
        @objective(model,Min,-sm)
    elseif objective==:voltage_deviation
        @objective(model,Min,vd_expr)
    elseif objective==:dispatch
        isnothing(dispatch_reference) && throw(ArgumentError("dispatch objective requires explicit references"))
        length(dispatch_reference)==length(ws) || throw(ArgumentError("one dispatch reference per witness"))
        all(length(dispatch_reference[i])==length(w.case.generators) && all(isfinite,dispatch_reference[i]) for (i,w) in enumerate(ws)) || throw(ArgumentError("invalid dispatch references"))
        scales=[[(max(g.p_max-g.p_min,1.)) for g in w.case.generators] for w in ws]
        @objective(model,Min,sum(w.weight*sum(((variables[i].pg[j]-dispatch_reference[i][j])/scales[i][j])^2 for j in eachindex(w.case.generators)) for (i,w) in enumerate(ws)))

    else
        @objective(model,Min,0.)
    end
    started=time();optimize!(model);seconds=time()-started
    has_values(model) || return (;termination_status=Symbol(string(termination_status(model))),states=ACState[],signals=Float64[],parameters=Dict(),taps=Dict(),susceptances=Dict(),objective=nothing,seconds)
    states=[ACState(value.(v.vm),value.(v.va),value.(v.pg),value.(v.qg)) for v in variables]
    parameters=Dict(id=>NamedTuple{keys(s)}(Tuple(value(v) for v in values(s))) for (id,s) in settings)
    (;termination_status=Symbol(string(termination_status(model))),states,signals=[x isa Real ? Float64(x) : value(x) for x in signals],parameters,taps=Dict(id=>value(x) for (id,x) in shared_taps),susceptances=Dict(id=>value(x) for (id,x) in shared_shunts),objective=objective_value(model),seconds)
end

function validate_static_witnesses(witnesses,result;design_bounds=Dict(),tolerance=1e-8,
    tap_controls=TapControl[],shunt_controls=ShuntControl[],generation_costs=Dict(),objective_limits=Dict())
    ws=StaticWitness[witnesses...];_static_witness_contract(ws,design_bounds)
    length(result.states)==length(ws)==length(result.signals) || return (;valid=false,reason=:state_count)
    Set(keys(result.parameters))==Set(keys(design_bounds)) || return (;valid=false,reason=:design_ids)
    policy=all(Set(keys(value))==Set(keys(design_bounds[id])) && all(design_bounds[id][k][1]-tolerance<=value[k]<=design_bounds[id][k][2]+tolerance for k in keys(design_bounds[id])) for (id,value) in result.parameters)
    _static_equipment_contract(ws,tap_controls,shunt_controls)
    taps=get(result,:taps,Dict());shunts=get(result,:susceptances,Dict())
    Set(keys(taps))==Set(t.branch_id for t in tap_controls) && Set(keys(shunts))==Set(s.bank_id for s in shunt_controls) || return (;valid=false,reason=:equipment_ids)
    equipment=all(isfinite(taps[t.branch_id]) && t.lower-tolerance<=taps[t.branch_id]<=t.upper+tolerance for t in tap_controls) &&
        all(begin p=_shunt_policy(ws[1].case,s);isfinite(shunts[s.bank_id]) && p.lower-tolerance<=shunts[s.bank_id]<=p.upper+tolerance end for s in shunt_controls)
    equipment || return (;valid=false,reason=:equipment_bounds)
    rows=[]
    for (i,w) in enumerate(ws)
        c=_static_probe_case(w)
        isempty(taps) || (c=with_tap_settings(c,taps))
        isempty(shunts) || (c=with_shunt_settings(c,shunts))
        st=result.states[i];free=[ReactiveControlAssignment(g.id,FreeQ()) for g in c.generators]
        physical=validate_equilibrium(c,st;reactive_assignments=free,power_tolerance=tolerance,limit_tolerance=tolerance)
        law=validate_static_reactive(c,st,w.laws;settings=result.parameters,tolerance)
        bus=Dict(b.id=>j for (j,b) in enumerate(c.network.buses))
        angles=all(!b.available || !haskey(w.angle_limits,b.id) || w.angle_limits[b.id][1]-tolerance<=st.va[bus[b.from_bus]]-st.va[bus[b.to_bus]]<=w.angle_limits[b.id][2]+tolerance for b in c.network.branches)
        response=0.
        if w.anchor>0
            base=result.states[w.anchor]
            response=maximum(abs(st.pg[j]-(g.available ? clamp(base.pg[j]+get(w.participation,g.id,0.)*result.signals[i],max(g.p_min,isnothing(g.s_rated) ? -Inf : -g.s_rated),min(g.p_max,isnothing(g.s_rated) ? Inf : g.s_rated)) : 0.)) for (j,g) in enumerate(c.generators))
        end
        ref=only(j for (j,b) in enumerate(c.network.buses) if b.reference)
        valid=physical.valid&&law.valid&&angles&&response<=tolerance&&abs(st.va[ref])<=tolerance
        push!(rows,(;valid,physical,law,response,conditional=!isnothing(w.test_bus)))
    end
    if !isempty(objective_limits)
        metrics=static_witness_metrics(ws,result;generation_costs)
        policy &= all(k in (:q_reserve,:security_margin) ? metrics[k]>=v-tolerance : metrics[k]<=v+tolerance*max(1.,abs(v)) for (k,v) in objective_limits)
    end
    solver=result.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
    (;valid=solver&&policy&&all(x.valid for x in rows),solver_valid=solver,policy_valid=policy,rows)
end

_json_data(l::StaticReactiveLaw)=Dict("generator_id"=>l.generator_id,"mode"=>string(l.mode),"measured_bus"=>l.measured_bus,"parameters"=>_json_data(l.parameters),"current_limit"=>l.current_limit)
