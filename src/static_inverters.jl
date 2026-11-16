"""Explicit aggregate inverter settings for a static positive-sequence study.

P/Q references and available active power are on `base_mva`; current is on
`base_mva/(sqrt(3)*terminal_base_kv)`. Voltage is on the network terminal base.
`:gfl` supports fixed Q or Volt/VAR. `:gfm` requires local Q/V; P/f response
is controlled by `frequency_response`. Use `qv_inverter` for the main study.
This equilibrium model does not establish dynamic voltage-forming performance.
"""
struct StaticInverter
    generator_id::Int
    terminal_bus::Int
    poi_bus::Int
    regulated_bus::Int
    mode::Symbol
    priority::Symbol
    q_control::Symbol
    base_mva::Float64
    terminal_base_kv::Float64
    i_max::Float64
    s_max::Float64
    p_available::Float64
    p_ref::Float64
    q_ref::Float64
    v_ref::Float64
    q_droop::Float64
    voltage_deadband::Float64
    f_ref_hz::Float64
    p_droop_hz::Float64
    available::Bool
    reactive_available::Bool
    frequency_response::Bool
    q_cap_fraction::Float64
    function StaticInverter(; generator_id::Integer, terminal_bus::Integer,
        poi_bus::Integer=terminal_bus, regulated_bus::Integer=terminal_bus,
        mode::Symbol, priority::Symbol, q_control::Symbol,
        base_mva::Real, terminal_base_kv::Real, i_max::Real, s_max::Real,
        p_available::Real, p_ref::Real, q_ref::Real,
        v_ref::Real, q_droop::Real, voltage_deadband::Real=0.0,
        f_ref_hz::Real, p_droop_hz::Real,
        available::Bool=true, reactive_available::Bool,
        frequency_response::Bool=(mode==:gfm), q_cap_fraction::Real=1.0)
        all(>(0),(generator_id,terminal_bus,poi_bus,regulated_bus)) ||
            throw(ArgumentError("plant generator and bus identities must be positive"))
        mode in (:gfl,:gfm) || throw(ArgumentError("mode must be :gfl or :gfm"))
        priority in (:active,:reactive) || throw(ArgumentError("priority must be :active or :reactive"))
        q_control in (:fixed_q,:volt_var) || throw(ArgumentError("unsupported inverter Q control"))
        mode==:gfm && (q_control!=:volt_var || regulated_bus!=terminal_bus) &&
            throw(ArgumentError("static GFM requires local terminal Q/V droop"))
        isfinite(q_cap_fraction) && 0<=q_cap_fraction<=1 ||
            throw(ArgumentError("q_cap_fraction must be finite and in [0,1]"))
        frequency_response && mode!=:gfm &&
            throw(ArgumentError("frequency response requires GFM mode"))
        positive=(base_mva,terminal_base_kv,i_max,s_max,v_ref,q_droop,f_ref_hz,p_droop_hz)
        all(x->isfinite(x)&&x>0,positive) || throw(ArgumentError("bases, ratings and droop slopes must be finite and positive"))
        all(isfinite,(p_available,p_ref,q_ref,voltage_deadband)) || throw(ArgumentError("commands must be finite"))
        p_available>=0 && voltage_deadband>=0 || throw(ArgumentError("availability and deadband must be nonnegative"))
        new(Int(generator_id),Int(terminal_bus),Int(poi_bus),Int(regulated_bus),mode,priority,q_control,
            Float64(base_mva),Float64(terminal_base_kv),Float64(i_max),Float64(s_max),
            Float64(p_available),Float64(p_ref),Float64(q_ref),Float64(v_ref),Float64(q_droop),
            Float64(voltage_deadband),Float64(f_ref_hz),Float64(p_droop_hz),available,reactive_available,frequency_response,Float64(q_cap_fraction))
    end
end


"""Construct the main fixed-frequency terminal Q–V study model.

`q_cap_fraction=0.395` caps both Q directions as a fraction of the effective
apparent rating, intersecting supplied asymmetric limits and both capability
circles. It does not reserve reactive headroom. BESS uses either inverter mode;
charging requires a negative source P bound, and energy accounting is external.
No physical frequency-response gain is inferred. Legacy `StaticInverter`
construction retains its previous frequency-aware behavior and uncapped Q box.
"""
function qv_inverter(; q_cap_fraction::Real=0.395, frequency_hz::Real=50.0, kwargs...)
    forbidden=(:frequency_response,:f_ref_hz,:p_droop_hz,:q_control)
    any(k->haskey(kwargs,k),forbidden) &&
        throw(ArgumentError("qv_inverter owns fixed-frequency and Volt/VAR settings"))
    StaticInverter(;kwargs...,q_control=:volt_var,frequency_response=false,
        f_ref_hz=frequency_hz,p_droop_hz=1.0,q_cap_fraction)
end

function _inverter_context(case, plant)
    isnothing(case.network) && throw(ArgumentError("inverter requires an AC network"))
    isfinite(case.base_power) && case.base_power>0 || throw(ArgumentError("invalid system MVA base"))
    gi=findfirst(g->g.id==plant.generator_id,case.generators)
    isnothing(gi) && throw(ArgumentError("unknown inverter generator identity"))
    g=case.generators[gi]
    g.bus_id==plant.terminal_bus || throw(ArgumentError("inverter terminal must equal generator bus"))
    busmap=Dict(b.id=>i for (i,b) in enumerate(case.network.buses))
    all(haskey(busmap,b) for b in (plant.terminal_bus,plant.poi_bus,plant.regulated_bus)) ||
        throw(ArgumentError("unknown terminal, POI or regulated bus"))
    components=_network_components(case.network,Set{Int}())
    any(component->all(b in component for b in (plant.terminal_bus,plant.poi_bus,plant.regulated_bus)),components) ||
        throw(ArgumentError("terminal, POI and regulated bus must share an energized network component"))
    # The sequential projection is valid for boxes containing zero. Positive
    # minimum output / mandatory nonzero Q need an explicit commitment model.
    g.p_min<=0<=g.p_max && g.q_min<=0<=g.q_max ||
        throw(ArgumentError("inverter equipment P/Q boxes must contain zero"))
    ratio=plant.base_mva/case.base_power
    s=isnothing(g.s_rated) ? plant.s_max : min(plant.s_max,g.s_rated/ratio)
    (;g,gi,terminal=busmap[plant.terminal_bus],regulated=busmap[plant.regulated_bus],ratio,
        pmin=g.p_min/ratio,pmax=min(g.p_max/ratio,plant.p_available),
        qmin=plant.reactive_available ? max(g.q_min/ratio,-plant.q_cap_fraction*s) : 0.0,
        qmax=plant.reactive_available ? min(g.q_max/ratio,plant.q_cap_fraction*s) : 0.0,s,
        online=g.available && plant.available)
end

function _check_inverter_inputs(case,plants,frequency_hz)
    isfinite(frequency_hz) && frequency_hz>0 || throw(ArgumentError("frequency must be positive and finite"))
    ids=[p.generator_id for p in plants]
    length(unique(ids))==length(ids) || throw(ArgumentError("duplicate inverter generator"))
    for p in plants
        _inverter_context(case,p)
        any(a->a.generator_id==p.generator_id,case.attachments) &&
            throw(ArgumentError("inverter cannot also carry an existing droop attachment"))
    end
    nothing
end

"""Evaluate exact static inverter commands and capability on the case system base.

`terminal_voltage` and `regulated_voltage` are positive voltage magnitudes in pu;
`frequency_hz` is a supplied steady-state frequency, not a solved dynamic state.
"""
function inverter_response(case::Case,plant::StaticInverter,terminal_voltage::Real;
    regulated_voltage::Real=terminal_voltage,frequency_hz::Real=case.base_frequency)
    all(x->isfinite(x)&&x>0,(terminal_voltage,regulated_voltage,frequency_hz)) ||
        throw(ArgumentError("voltage and frequency must be positive and finite"))
    _inverter_response(_inverter_context(case,plant),plant,terminal_voltage,regulated_voltage,frequency_hz)
end

# Shared arithmetic for validated callers that cache topology/context while seeding frequency.
function _inverter_response(c,plant,terminal_voltage,regulated_voltage,frequency_hz)
    pstar=plant.p_ref+(plant.frequency_response ? (plant.f_ref_hz-frequency_hz)/plant.p_droop_hz : 0.0)
    qstar=plant.q_control==:fixed_q ? plant.q_ref : plant.q_ref+
        (max(plant.v_ref-plant.voltage_deadband-regulated_voltage,0)-
         max(regulated_voltage-plant.v_ref-plant.voltage_deadband,0))/plant.q_droop
    radius=min(c.s,terminal_voltage*plant.i_max)
    if !c.online
        p=q=0.0
    elseif plant.priority==:active
        p=clamp(pstar,max(c.pmin,-radius),min(c.pmax,radius))
        h=sqrt(max(radius^2-p^2,0.0))
        q=clamp(qstar,max(c.qmin,-h),min(c.qmax,h))
    else
        q=clamp(qstar,max(c.qmin,-radius),min(c.qmax,radius))
        h=sqrt(max(radius^2-q^2,0.0))
        p=clamp(pstar,max(c.pmin,-h),min(c.pmax,h))
    end
    # q-current denotes the injection component; in I=conj(S/V), Im(I)=-iq.
    (;p=c.ratio*p,q=c.ratio*q,p_plant=p,q_plant=q,
        p_request=pstar,q_request=qstar,radius_plant=radius,
        current_plant=hypot(p,q)/terminal_voltage,
        current_base_ka=plant.base_mva/(sqrt(3)*plant.terminal_base_kv),
        p_limited=abs(p-pstar)>1e-10,q_limited=abs(q-qstar)>1e-10,
        online=c.online,reactive_available=plant.reactive_available)
end

"""Replay inverter command equations, equipment bounds and current/apparent limits.

Returns per-plant rows in supplied order. No state is solved, repaired or clamped.
Power margins/residuals use system pu; current margins use plant pu.
"""
function validate_static_inverters(case::Case,state::ACState,plants;
    frequency_hz::Real=case.base_frequency,tolerance::Real=1e-6)
    isfinite(tolerance) && tolerance>=0 || throw(ArgumentError("invalid inverter tolerance"))
    _check_inverter_inputs(case,plants,frequency_hz)
    length(state.vm)==length(case.network.buses) && length(state.pg)==length(case.generators) &&
        length(state.qg)==length(case.generators) || throw(ArgumentError("inverter replay state dimensions differ"))
    rows=NamedTuple[]
    for plant in plants
        c=_inverter_context(case,plant)
        v=state.vm[c.terminal];vr=state.vm[c.regulated];p=state.pg[c.gi];q=state.qg[c.gi]
        if !all(isfinite,(v,vr,p,q)) || v<=0 || vr<=0
            push!(rows,(;generator_id=plant.generator_id,valid=false,reason=:nonfinite_or_nonpositive_state,
                p_residual=Inf,q_residual=Inf,current_margin=-Inf,apparent_margin=-Inf))
            continue
        end
        target=inverter_response(case,plant,v;regulated_voltage=vr,frequency_hz)
        cp=p/c.ratio;cq=q/c.ratio
        current_margin=plant.i_max-hypot(cp,cq)/v
        apparent_margin=c.ratio*c.s-hypot(p,q)
        box_ok=c.g.p_min-tolerance<=p<=c.g.p_max+tolerance &&
            c.g.q_min-tolerance<=q<=c.g.q_max+tolerance && p<=c.ratio*plant.p_available+tolerance
        valid=abs(p-target.p)<=tolerance && abs(q-target.q)<=tolerance &&
            current_margin>=-tolerance && apparent_margin>=-tolerance && box_ok
        push!(rows,(;generator_id=plant.generator_id,valid,reason=valid ? :passed : :inverter_equilibrium,
            p_residual=p-target.p,q_residual=q-target.q,current_margin,apparent_margin))
    end
    (;valid=all(r->r.valid,rows),rows,tolerance=Float64(tolerance),frequency_hz=Float64(frequency_hz))
end

"""Add declared inverter laws to existing AC-model voltage and injection variables.

Variables must be in case bus/generator order and on the case system base.
Rejects duplicate control ownership. `active_reference_variables` optionally maps generator IDs to model-owned, finite-bounded
active references on each inverter plant base, for explicit preventive design.
`preventive_dispatch=true` links those references to base active output at the
reference frequency, retaining priority-dependent reactive projection and both
capability circles without duplicating the base active projection equality.
This adds constraints, not a solver or an
automatic SCOPF participation policy. Voltage magnitudes must have positive bounds or fixed positive values.
`frequency_hz` may be a positive real input or a model-owned variable with finite
positive bounds; the latter requires a complete external frequency/balance contract.
"""
function add_static_inverter_constraints!(model::JuMP.Model,case::Case,variables,plants;
    frequency_hz::Union{Real,JuMP.VariableRef}=case.base_frequency,
    active_reference_variables::AbstractDict=Dict(),
    preventive_dispatch::Bool=false)
    preventive_dispatch && (!(frequency_hz isa Real) || any(p->p.f_ref_hz!=frequency_hz,plants)) &&
        throw(ArgumentError("preventive dispatch must be anchored at each plant reference frequency"))
    if frequency_hz isa JuMP.VariableRef
        owner_model(frequency_hz)===model || throw(ArgumentError("frequency belongs to another model"))
        (is_fixed(frequency_hz) ? isfinite(fix_value(frequency_hz)) && fix_value(frequency_hz)>0 :
            has_lower_bound(frequency_hz) && has_upper_bound(frequency_hz) &&
            0<lower_bound(frequency_hz)<=upper_bound(frequency_hz)<Inf) ||
            throw(ArgumentError("frequency requires finite positive bounds or a fixed positive value"))
        _check_inverter_inputs(case,plants,case.base_frequency)
    else
        _check_inverter_inputs(case,plants,frequency_hz)
    end
    length(variables.vm)==length(case.network.buses) &&
        length(variables.pg)==length(case.generators) && length(variables.qg)==length(case.generators) ||
        throw(ArgumentError("inverter model variable dimensions differ"))
    for (id,ref) in active_reference_variables
        any(p->p.generator_id==id,plants) || throw(ArgumentError("unknown active-reference generator"))
        ref isa JuMP.VariableRef && owner_model(ref)===model ||
            throw(ArgumentError("active reference must be a variable owned by this model"))
        (is_fixed(ref) ? isfinite(fix_value(ref)) :
            has_lower_bound(ref) && has_upper_bound(ref) &&
            isfinite(lower_bound(ref)) && isfinite(upper_bound(ref))) ||
            throw(ArgumentError("active reference requires finite bounds"))
    end
    get!(model.ext,:static_inverter_generator_ids,Set{Int}())
    any(p->p.generator_id in model.ext[:static_inverter_generator_ids],plants) &&
        throw(ArgumentError("inverter constraints already installed"))
    for plant in plants
        c=_inverter_context(case,plant)
        plant.generator_id in model.ext[:static_inverter_generator_ids] &&
            throw(ArgumentError("inverter constraints already installed"))
        v=variables.vm[c.terminal];vr=variables.vm[c.regulated]
        pg=variables.pg[c.gi];qg=variables.qg[c.gi];ratio=c.ratio
        all(x->x isa JuMP.VariableRef && owner_model(x)===model,(v,vr,pg,qg)) ||
            throw(ArgumentError("inverter requires explicit injection/voltage variables owned by this model"))
        all(x->is_fixed(x) ? fix_value(x)>0 : has_lower_bound(x) && lower_bound(x)>0,(v,vr)) ||
            throw(ArgumentError("positive voltage bounds or fixed positive voltages required"))
        if !c.online
            fix(pg,0.0;force=true)
            fix(qg,0.0;force=true)
        else
            s=c.s;imax=plant.i_max
            radius=@NLexpression(model,min(s,v*imax))
            if preventive_dispatch
                haskey(active_reference_variables,plant.generator_id) || throw(ArgumentError("preventive dispatch requires explicit active-reference ownership"))
                # Link the reference once, retaining capability without a duplicate projection equality.
                ref=active_reference_variables[plant.generator_id]
                @constraint(model,pg==ratio*ref)
                @constraint(model,pg>=ratio*c.pmin)
                @constraint(model,pg<=ratio*c.pmax)
                if plant.priority==:active
                    # Q projection below already enforces the remaining circle.
                    @constraint(model,(pg/(ratio*s))^2<=1)
                    @constraint(model,(pg/(ratio*imax))^2<=v^2)
                else
                    @constraint(model,(pg/(ratio*s))^2+(qg/(ratio*s))^2<=1)
                    @constraint(model,(pg/(ratio*imax))^2+(qg/(ratio*imax))^2<=v^2)
                end
            end
            pref=get(active_reference_variables,plant.generator_id,plant.p_ref);fref=plant.f_ref_hz;mp=plant.p_droop_hz
            pstar=plant.frequency_response ? @NLexpression(model,pref+(fref-frequency_hz)/mp) : pref
            qref=plant.q_ref;vref=plant.v_ref;db=plant.voltage_deadband;nq=plant.q_droop
            qstar=plant.q_control==:fixed_q ? qref :
                @NLexpression(model,qref+(max(vref-db-vr,0)-max(vr-vref-db,0))/nq)
            pmin=c.pmin;pmax=c.pmax;qmin=c.qmin;qmax=c.qmax
            if plant.priority==:active
                p=preventive_dispatch ? @NLexpression(model,pg/ratio) : @NLexpression(model,min(min(pmax,radius),max(max(pmin,-radius),pstar)))
                # The floor is solely an intermediate-iterate derivative guard.
                # Exact replay uses zero and independently checks both circles.
                h=@NLexpression(model,sqrt(max(radius^2-p^2,1e-24)))
                q=@NLexpression(model,min(min(qmax,h),max(max(qmin,-h),qstar)))
            else
                q=@NLexpression(model,min(min(qmax,radius),max(max(qmin,-radius),qstar)))
                h=@NLexpression(model,sqrt(max(radius^2-q^2,1e-24)))
                p=@NLexpression(model,min(min(pmax,h),max(max(pmin,-h),pstar)))
            end
            preventive_dispatch || @NLconstraint(model,pg==ratio*p)
            @NLconstraint(model,qg==ratio*q)
        end
        push!(model.ext[:static_inverter_generator_ids],plant.generator_id)
    end
    nothing
end

"""Static-inverter OPF output retaining the controller settings and frequency."""
struct StaticInverterOPFResult
    opf::ACOPFResult{Float64}
    plants::Vector{StaticInverter}
    frequency_hz::Float64
end

"""Solve a fixed-equipment AC OPF with explicit static inverter commands.

Other generators retain the existing AC OPF semantics. No plant reference,
frequency or current rating is optimized. All native network limits remain.
Use `validate_inverter_opf` to check native convergence, AC physics and inverter
laws together; ordinary AC validation alone cannot certify these added laws.
"""
function solve_inverter_opf(case::Case,plants::AbstractVector{StaticInverter};
    frequency_hz::Real=case.base_frequency,initial_state=nothing,
    optimizer_factory=Ipopt.Optimizer,optimizer_attributes=Dict{String,Any}(),silent::Bool=true)
    validate_case(case)
    _check_inverter_inputs(case,plants,frequency_hz)
    model,variables=_build_acopf_model(case;voltage_epsilon=1e-4,
        reactive_relative_epsilon=1e-4,reactive_epsilon=nothing,silent,
        optimizer_factory,initial_state)
    add_static_inverter_constraints!(model,case,variables,plants;frequency_hz)
    for (key,val) in optimizer_attributes
        set_optimizer_attribute(model,key,val)
    end
    optimize!(model)
    state=has_values(model) ? ACState(value.(variables.vm),value.(variables.va),
        value.(variables.pg),value.(variables.qg)) : nothing
    opf=ACOPFResult{Float64}(state,has_values(model) ? objective_value(model) : NaN,
        Symbol(string(termination_status(model))),Symbol(string(primal_status(model))),1e-4,1e-4,nothing)
    StaticInverterOPFResult(opf,collect(plants),Float64(frequency_hz))
end

"""Require native OPF convergence, independent AC replay and inverter-law replay."""
function validate_inverter_opf(case::Case,result::StaticInverterOPFResult; tolerance::Real=1e-6)
    isfinite(tolerance) && tolerance>=0 || throw(ArgumentError("invalid inverter tolerance"))
    converged=result.opf.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
    if isnothing(result.opf.state)
        return (;valid=false,converged,ac=nothing,inverters=nothing)
    end
    ac=validate_equilibrium(case,result.opf)
    inverters=validate_static_inverters(case,result.opf.state,result.plants;
        frequency_hz=result.frequency_hz,tolerance)
    (;valid=converged && ac.valid && inverters.valid,converged,ac,inverters)
end

_json_data(x::StaticInverter)=Dict(string(k)=>_json_data(getfield(x,k)) for k in fieldnames(StaticInverter))

function materialize_operating_point(case::Case,result::StaticInverterOPFResult)
    validate_inverter_opf(case,result).valid || throw(ArgumentError("inverter result failed replay"))
    context=Dict("origin"=>"StaticInverterOPFResult","frequency_hz"=>result.frequency_hz,
        "inverters"=>model_data(result.plants),"dynamic_qualification"=>"not_assessed")
    _materialized_point(case,result.opf.state,nothing,context)
end
