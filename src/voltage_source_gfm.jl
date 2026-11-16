"""Balanced voltage-source GFM settings, with terminal P/Q feedback.

P/Q, impedance, current and apparent ratings use `base_mva` and the terminal
network voltage base. `z_physical` is an additional series connection NOT already
in the network; `z_virtual` is a fixed controller impedance, never a physical loss.
`e_bounds` constrain the virtual source; `u_bounds` constrain converter voltage
before the physical connection. Both are pu. No limiter dynamics are implied.
"""
struct VoltageSourceGFM
    generator_id::Int
    terminal_bus::Int
    base_mva::Float64
    z_physical::ComplexF64
    z_virtual::ComplexF64
    p_ref::Float64
    q_ref::Float64
    f_ref_hz::Float64
    p_droop_hz::Float64
    e_ref::Float64
    q_droop::Float64
    e_bounds::Tuple{Float64,Float64}
    u_bounds::Tuple{Float64,Float64}
    i_max::Float64
    s_max::Float64
    p_available::Float64
    function VoltageSourceGFM(;generator_id::Integer,terminal_bus::Integer,base_mva::Real,
        z_physical::Number,z_virtual::Number,p_ref::Real,q_ref::Real,f_ref_hz::Real,
        p_droop_hz::Real,e_ref::Real,q_droop::Real,e_bounds,u_bounds,
        i_max::Real,s_max::Real,p_available::Real)
        generator_id>0 && terminal_bus>0 || throw(ArgumentError("positive identities required"))
        all(x->isfinite(x)&&x>0,(base_mva,f_ref_hz,p_droop_hz,e_ref,q_droop,i_max,s_max)) ||
            throw(ArgumentError("bases, slopes and ratings must be positive and finite"))
        all(isfinite,(p_ref,q_ref,p_available)) && p_available>=0 || throw(ArgumentError("invalid power declarations"))
        for z in (z_physical,z_virtual)
            isfinite(z) && real(z)>=0 && imag(z)>=0 || throw(ArgumentError("passive resistive/inductive impedances required"))
        end
        abs(z_physical+z_virtual)>0 || throw(ArgumentError("nonzero total impedance required"))
        for b in (e_bounds,u_bounds)
            length(b)==2 && all(isfinite,b) && 0<b[1]<b[2] || throw(ArgumentError("invalid voltage bounds"))
        end
        e_bounds[1]<=e_ref<=e_bounds[2] || throw(ArgumentError("reference outside internal voltage bounds"))
        new(generator_id,terminal_bus,base_mva,z_physical,z_virtual,p_ref,q_ref,f_ref_hz,
            p_droop_hz,e_ref,q_droop,Tuple(Float64.(e_bounds)),Tuple(Float64.(u_bounds)),i_max,s_max,p_available)
    end
end

"""Finite-gain threshold virtual impedance for a voltage-source GFM.

The onset is `onset_fraction * plant.i_max`. The dimensionless multiplier is
`min(max_multiplier, max(0, (abs(I)/onset)^2 - 1))`; added virtual impedance is
`impedance_gain * multiplier` on the plant base. Settings are fixed, not optimized.
Finite impedance does not guarantee the hard current ceiling: the original ceiling
is enforced separately. This is an algebraic controller, not dynamic ride-through.
"""
struct ThresholdVirtualImpedance
    onset_fraction::Float64
    impedance_gain::ComplexF64
    max_multiplier::Float64
    function ThresholdVirtualImpedance(;onset_fraction::Real,impedance_gain::Number,max_multiplier::Real)
        isfinite(onset_fraction) && 0<onset_fraction<1 || throw(ArgumentError("onset fraction must lie strictly between zero and one"))
        isfinite(impedance_gain) && real(impedance_gain)>=0 && imag(impedance_gain)>=0 && abs(impedance_gain)>0 ||
            throw(ArgumentError("positive passive impedance gain required"))
        isfinite(max_multiplier) && max_multiplier>0 || throw(ArgumentError("positive finite multiplier ceiling required"))
        new(onset_fraction,impedance_gain,max_multiplier)
    end
end

_limiter_law(p,l,current_squared)=min(l.max_multiplier,max(0.,current_squared/(l.onset_fraction*p.i_max)^2-1))

# Passive impedances make |I(lambda)| nonincreasing. The scalar residual
# lambda - law(|I(lambda)|²) is strictly increasing, so bisection is unambiguous.
function _limiter_multiplier(p,l,voltage,internal_voltage)
    lo=0.;hi=l.max_multiplier;delta=internal_voltage-voltage
    for _ in 1:80
        mid=(lo+hi)/2
        i=delta/(p.z_physical+p.z_virtual+mid*l.impedance_gain)
        if mid<_limiter_law(p,l,abs2(i));lo=mid;else;hi=mid;end
    end
    (lo+hi)/2
end

function _voltage_source_context(case,p)
    gi=findfirst(g->g.id==p.generator_id,case.generators)
    isnothing(gi) && throw(ArgumentError("unknown voltage-source generator"))
    g=case.generators[gi]
    g.bus_id==p.terminal_bus || throw(ArgumentError("terminal differs from generator bus"))
    bi=findfirst(b->b.id==p.terminal_bus,case.network.buses)
    isnothing(bi) && throw(ArgumentError("unknown terminal bus"))
    any(a->a.generator_id==p.generator_id,case.attachments) && throw(ArgumentError("duplicate reactive controller"))
    (;gi,bi,g,ratio=p.base_mva/case.base_power)
end

"""Independent complex-phasor evaluation; no clipping or state repair.

`voltage` and `internal_voltage` are complex pu phasors. Physical connection
loss is returned on the plant base. The virtual impedance consumes no energy.
"""
function voltage_source_response(p::VoltageSourceGFM,voltage::Number,internal_voltage::Number;
    limiter::Union{Nothing,ThresholdVirtualImpedance}=nothing)
    all(isfinite,(voltage,internal_voltage)) || throw(ArgumentError("nonfinite voltage"))
    multiplier=isnothing(limiter) ? 0. : _limiter_multiplier(p,limiter,voltage,internal_voltage)
    zv=p.z_virtual+(isnothing(limiter) ? 0im : multiplier*limiter.impedance_gain)
    i=(internal_voltage-voltage)/(p.z_physical+zv)
    u=internal_voltage-zv*i
    s=voltage*conj(i)
    (;current=i,p=real(s),q=imag(s),converter_voltage=u,
        physical_loss=real(p.z_physical)*abs2(i),converter_power=u*conj(i),
        limiter_multiplier=multiplier,effective_virtual_impedance=zv,
        current_within_limit=abs(i)<=p.i_max)
end

"""Network equilibrium, internal phasors and the exact frozen controller contract."""
struct VoltageSourceResult
    opf::ACOPFResult{Float64}
    plants::Vector{VoltageSourceGFM}
    inverters::Vector{StaticInverter}
    responses::Vector{GeneratorFrequencyResponse}
    internal_voltage::Vector{ComplexF64}
    frequency_hz::Float64
    frequency_bounds::Tuple{Float64,Float64}
    solved_frequency::Bool
    limiters::Dict{Int,ThresholdVirtualImpedance}
    limiter_multiplier::Vector{Float64}
    branch_angle_bounds::Dict{Int,Tuple{Float64,Float64}}
end

# Preserve construction of existing unsaturated results.
VoltageSourceResult(opf,plants,inverters,responses,ev,f,bounds,solved)=
    VoltageSourceResult(opf,plants,inverters,responses,ev,f,bounds,solved,
        Dict{Int,ThresholdVirtualImpedance}(),zeros(length(plants)),Dict{Int,Tuple{Float64,Float64}}())
VoltageSourceResult(opf,plants,inverters,responses,ev,f,bounds,solved,limiters,multipliers)=
    VoltageSourceResult(opf,plants,inverters,responses,ev,f,bounds,solved,limiters,multipliers,Dict{Int,Tuple{Float64,Float64}}())

function _voltage_source_angles(case,angles)
    for (id,bounds) in angles
        any(b->b.id==id,case.network.branches) && length(bounds)==2 &&
            all(isfinite,bounds) && bounds[1]<=bounds[2] || throw(ArgumentError("invalid branch angle bounds"))
    end
    Dict(Int(k)=>(Float64(v[1]),Float64(v[2])) for (k,v) in angles)
end

function _check_voltage_source_limiters(plants,limiters)
    all(id->any(p->p.generator_id==id,plants),keys(limiters)) ||
        throw(ArgumentError("limiter must belong to a declared voltage source"))
    all(l->l isa ThresholdVirtualImpedance,values(limiters)) || throw(ArgumentError("unsupported limiter"))
end

function _voltage_source_contract(case,plants,inverters,responses,solved)
    validate_case(case); _check_connected(case)
    isempty(plants) && throw(ArgumentError("at least one voltage source required"))
    _check_inverter_inputs(case,inverters,case.base_frequency)
    ids=vcat([p.generator_id for p in plants],[p.generator_id for p in inverters],[r.generator_id for r in responses])
    length(ids)==length(unique(ids)) || throw(ArgumentError("duplicate generator control"))
    all(id->any(g->g.id==id,case.generators),ids) || throw(ArgumentError("unknown generator"))
    solved && Set(ids)!=Set(g.id for g in case.generators) && throw(ArgumentError("solved frequency requires one active law per generator"))
    for p in plants; _voltage_source_context(case,p); end
    # An online source with a nonzero permitted active range is required.
    if solved
        responsive=any(plants) do p
            c=_voltage_source_context(case,p)
            c.g.available && min(c.g.p_max,c.ratio*p.p_available)>c.g.p_min
        end
        responsive |= any(p->p.frequency_response && _inverter_context(case,p).online &&
            _inverter_context(case,p).pmax>_inverter_context(case,p).pmin,inverters)
        responsive |= any(responses) do r
            gi=findfirst(g->g.id==r.generator_id,case.generators)
            lo,hi=_active_response_bounds(case,gi)
            case.generators[gi].available && r.gain_pu_per_hz>0 && hi>lo
        end
        responsive || throw(ArgumentError("no available active-frequency responder"))
    end
end

"""Solve a voltage-source equilibrium with fixed settings and optional impedance limiting.

Omit `frequency_bounds` for prescribed `frequency_hz`; provide a positive interval
for solved common frequency and declare every other generator through `inverters`
or `responses`. Prescribed-frequency unassigned generators retain native OPF
freedom. All source bounds are terminal injection bounds. Additional physical
connection losses are reported, but a DC-side energy/rating model is not inferred.
Without `limiters`, hard current/voltage inequalities define the unsaturated envelope.
`limiters` maps source generator IDs to fixed `ThresholdVirtualImpedance` settings.
The law determines added impedance; original current/voltage/power bounds remain.
Optional `branch_angle_bounds` map branch IDs to unchanged angle intervals in radians.
No hard-clipping fallback, reference adaptation or dynamics are inferred.
"""
function solve_voltage_source_opf(case::Case,plants::AbstractVector{VoltageSourceGFM};
    inverters=StaticInverter[],responses=GeneratorFrequencyResponse[],
    limiters=Dict{Int,ThresholdVirtualImpedance}(),
    branch_angle_bounds=Dict{Int,Tuple{Float64,Float64}}(),
    frequency_hz::Real=case.base_frequency,frequency_bounds=nothing,initial_state=nothing,
    optimizer_factory=Ipopt.Optimizer,optimizer_attributes=Dict{String,Any}(),silent::Bool=true)
    solved=!isnothing(frequency_bounds)
    isfinite(frequency_hz) && frequency_hz>0 || throw(ArgumentError("invalid frequency"))
    bounds=solved ? frequency_bounds : (frequency_hz,frequency_hz)
    length(bounds)==2 && all(isfinite,bounds) && 0<bounds[1]<=bounds[2] &&
        (!solved || bounds[1]<bounds[2]) || throw(ArgumentError("invalid frequency bounds"))
    _voltage_source_contract(case,plants,inverters,responses,solved)
    _check_voltage_source_limiters(plants,limiters)
    angles=_voltage_source_angles(case,branch_angle_bounds)
    model,v=_build_acopf_model(case;voltage_epsilon=1e-4,reactive_relative_epsilon=1e-4,
        reactive_epsilon=nothing,silent,optimizer_factory,initial_state)
    f=solved ? @variable(model,lower_bound=bounds[1],upper_bound=bounds[2],start=clamp(frequency_hz,bounds...),base_name="source_frequency") : Float64(frequency_hz)
    add_static_inverter_constraints!(model,case,v,inverters;frequency_hz=f)
    internal=Tuple{VariableRef,VariableRef}[]
    multipliers=Union{Float64,VariableRef}[]
    for p in plants
        c=_voltage_source_context(case,p);g=c.g;ratio=c.ratio
        vm=v.vm[c.bi];va=v.va[c.bi];pg=v.pg[c.gi];qg=v.qg[c.gi]
        # Cartesian internal voltage avoids an additional angular gauge.
        vv=complex(start_value(vm)*cos(start_value(va)),start_value(vm)*sin(start_value(va)))
        ss=complex(start_value(pg),start_value(qg))/ratio
        limiter=get(limiters,p.generator_id,nothing)
        current_seed=conj(ss/vv)
        multiplier_seed=isnothing(limiter) ? 0. : _limiter_law(p,limiter,abs2(current_seed))
        extra_seed=isnothing(limiter) ? 0im : multiplier_seed*limiter.impedance_gain
        seed=vv+(p.z_physical+p.z_virtual+extra_seed)*current_seed
        er=@variable(model,start=real(seed));ei=@variable(model,start=imag(seed))
        push!(internal,(er,ei))
        if !g.available
            fix(er,0.;force=true);fix(ei,0.;force=true);push!(multipliers,0.);continue
        end
        rr=real(p.z_physical+p.z_virtual);xx=imag(p.z_physical+p.z_virtual)
        rv=real(p.z_virtual);xv=imag(p.z_virtual)
        if isnothing(limiter)
            den=rr^2+xx^2
            ir=@NLexpression(model,(rr*(er-vm*cos(va))+xx*(ei-vm*sin(va)))/den)
            ii=@NLexpression(model,(rr*(ei-vm*sin(va))-xx*(er-vm*cos(va)))/den)
            push!(multipliers,0.)
        else
            lam=@variable(model,lower_bound=0.,upper_bound=limiter.max_multiplier,start=multiplier_seed)
            push!(multipliers,lam)
            ir=@variable(model,start=real(current_seed))
            ii=@variable(model,start=imag(current_seed))
            rg=real(limiter.impedance_gain);xg=imag(limiter.impedance_gain)
            onset2=(limiter.onset_fraction*p.i_max)^2;cap=limiter.max_multiplier
            @NLconstraint(model,er-vm*cos(va)==(rr+rg*lam)*ir-(xx+xg*lam)*ii)
            @NLconstraint(model,ei-vm*sin(va)==(rr+rg*lam)*ii+(xx+xg*lam)*ir)
            @NLconstraint(model,lam==min(cap,max(0.,(ir^2+ii^2)/onset2-1)))
            rv=@expression(model,rv+rg*lam)
            xv=@expression(model,xv+xg*lam)
        end
        @NLconstraint(model,pg==ratio*vm*(cos(va)*ir+sin(va)*ii))
        @NLconstraint(model,qg==ratio*vm*(sin(va)*ir-cos(va)*ii))
        @constraint(model,f==p.f_ref_hz-p.p_droop_hz*(pg/ratio-p.p_ref))
        ec=@expression(model,p.e_ref-p.q_droop*(qg/ratio-p.q_ref))
        @constraint(model,p.e_bounds[1]<=ec<=p.e_bounds[2])
        @constraint(model,er^2+ei^2==ec^2)
        @NLconstraint(model,ir^2+ii^2<=p.i_max^2)
        @constraint(model,pg^2+qg^2<=(ratio*p.s_max)^2)
        @constraint(model,pg<=ratio*p.p_available)
        ur=@NLexpression(model,er-rv*ir+xv*ii)
        ui=@NLexpression(model,ei-rv*ii-xv*ir)
        @NLconstraint(model,p.u_bounds[1]^2<=ur^2+ui^2<=p.u_bounds[2]^2)
    end
    for r in responses
        gi=findfirst(g->g.id==r.generator_id,case.generators)
        case.generators[gi].available || continue
        lo,hi=_active_response_bounds(case,gi)
        lo<=hi || throw(ArgumentError("empty response bounds"))
        pg=v.pg[gi];pr=r.p_ref;k=r.gain_pu_per_hz;fr=r.f_ref_hz
        @NLconstraint(model,pg==min(hi,max(lo,pr+k*(fr-f))))
    end
    _initialization_angles!(model,case,v,angles)
    @objective(model,Min,0.)
    for (k,val) in optimizer_attributes;set_optimizer_attribute(model,k,val);end
    optimize!(model)
    ok=has_values(model)
    state=ok ? ACState(value.(v.vm),value.(v.va),value.(v.pg),value.(v.qg)) : nothing
    opf=ACOPFResult{Float64}(state,ok ? objective_value(model) : NaN,
        Symbol(string(termination_status(model))),Symbol(string(primal_status(model))),1e-4,1e-4,nothing)
    ev=ok ? [complex(value(a),value(b)) for (a,b) in internal] : fill(complex(NaN,NaN),length(plants))
    VoltageSourceResult(opf,collect(plants),collect(inverters),collect(responses),ev,
        ok ? (solved ? value(f) : f) : NaN,Tuple(Float64.(bounds)),solved,
        Dict{Int,ThresholdVirtualImpedance}(limiters),
        ok ? [a isa VariableRef ? value(a) : a for a in multipliers] : fill(NaN,length(plants)),angles)
end

"""Independent phasor/controller replay plus native AC validation. No state repair."""
function validate_voltage_source_opf(case::Case,r::VoltageSourceResult;tolerance::Real=1e-6)
    isfinite(tolerance) && tolerance>0 || throw(ArgumentError("invalid tolerance"))
    _voltage_source_contract(case,r.plants,r.inverters,r.responses,r.solved_frequency)
    _check_voltage_source_limiters(r.plants,r.limiters)
    _voltage_source_angles(case,r.branch_angle_bounds)
    converged=r.opf.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
    st=r.opf.state;f=r.frequency_hz;b=r.frequency_bounds
    frequency_valid=all(isfinite,b) && 0<b[1]<=b[2] && (r.solved_frequency ? b[1]<b[2] : b[1]==b[2]) && isfinite(f) && b[1]-tolerance<=f<=b[2]+tolerance
    if isnothing(st) || length(r.internal_voltage)!=length(r.plants) || length(r.limiter_multiplier)!=length(r.plants) || !frequency_valid
        return (;valid=false,converged,frequency_valid,ac=nothing,plants=NamedTuple[])
    end
    ac=validate_equilibrium(case,r.opf)
    inv=validate_static_inverters(case,st,r.inverters;frequency_hz=f,tolerance)
    rows=NamedTuple[]
    for (p,e,lm) in zip(r.plants,r.internal_voltage,r.limiter_multiplier)
        c=_voltage_source_context(case,p);g=c.g;ratio=c.ratio
        if !g.available
            residual=max(abs(e),abs(st.pg[c.gi]),abs(st.qg[c.gi]),abs(lm))
            push!(rows,(;generator_id=p.generator_id,valid=isfinite(residual)&&residual<=tolerance,residual,current=0.,physical_loss_mw=0.,limiter_mode=:offline,limiter_multiplier=lm))
            continue
        end
        if !isfinite(e) || !isfinite(st.vm[c.bi]) || !isfinite(st.va[c.bi]) || st.vm[c.bi]<=0
            push!(rows,(;generator_id=p.generator_id,valid=false,residual=Inf,current=NaN,physical_loss_mw=NaN,limiter_mode=:invalid,limiter_multiplier=lm));continue
        end
        vv=st.vm[c.bi]*cis(st.va[c.bi]);limiter=get(r.limiters,p.generator_id,nothing)
        a=voltage_source_response(p,vv,e;limiter)
        limiter_mode=isnothing(limiter) ? :disabled :
            (a.limiter_multiplier<=tolerance ? :inactive :
             a.limiter_multiplier>=limiter.max_multiplier-tolerance ? :ceiling : :active)
        residual=maximum(abs.((st.pg[c.gi]-ratio*a.p,st.qg[c.gi]-ratio*a.q,
            f-p.f_ref_hz+p.p_droop_hz*(a.p-p.p_ref),abs(e)-p.e_ref+p.q_droop*(a.q-p.q_ref),lm-a.limiter_multiplier)))
        envelope=abs(a.current)<=p.i_max+tolerance && hypot(a.p,a.q)<=p.s_max+tolerance &&
            a.p<=p.p_available+tolerance && p.e_bounds[1]-tolerance<=abs(e)<=p.e_bounds[2]+tolerance &&
            p.u_bounds[1]-tolerance<=abs(a.converter_voltage)<=p.u_bounds[2]+tolerance
        push!(rows,(;generator_id=p.generator_id,valid=isfinite(residual)&&residual<=tolerance&&envelope,
            residual,current=abs(a.current),physical_loss_mw=p.base_mva*a.physical_loss,limiter_mode,limiter_multiplier=lm))
    end
    bm=Dict(b.id=>i for (i,b) in enumerate(case.network.buses))
    angles_valid=all(!b.available || !haskey(r.branch_angle_bounds,b.id) ||
        r.branch_angle_bounds[b.id][1]-tolerance<=st.va[bm[b.from_bus]]-st.va[bm[b.to_bus]]<=r.branch_angle_bounds[b.id][2]+tolerance
        for b in case.network.branches)
    response_valid=all(abs(st.pg[findfirst(g->g.id==law.generator_id,case.generators)]-_frequency_power(case,law,f))<=tolerance for law in r.responses)
    (;valid=converged&&ac.valid&&inv.valid&&frequency_valid&&response_valid&&angles_valid&&all(x->x.valid,rows),
        converged,frequency_valid,angles_valid,ac,plants=rows)
end
