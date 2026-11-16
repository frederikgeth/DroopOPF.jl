"""Declared primary active response on the case system MVA base.

`P(f) = clamp(p_ref + gain_pu_per_hz*(f_ref_hz-f), Pmin, Pmax)`.
Zero gain holds the clipped reference. Bounds intersect source P limits, apparent
rating and native attached-control active limits. The coupled apparent circle is
also enforced by the AC model; source equipment limits are never widened.
This is a settled response law, with no inertia, delay, deadband or load damping.
"""
struct GeneratorFrequencyResponse
    generator_id::Int
    p_ref::Float64
    gain_pu_per_hz::Float64
    f_ref_hz::Float64
    function GeneratorFrequencyResponse(;generator_id::Integer,p_ref::Real,
        gain_pu_per_hz::Real,f_ref_hz::Real)
        generator_id>0 && all(isfinite,(p_ref,gain_pu_per_hz,f_ref_hz)) &&
            gain_pu_per_hz>=0 && f_ref_hz>0 || throw(ArgumentError("invalid frequency response declaration"))
        new(Int(generator_id),Float64(p_ref),Float64(gain_pu_per_hz),Float64(f_ref_hz))
    end
end

function _frequency_contract(case,plants,responses,bounds,angle_bounds;require_responder::Bool=true)
    validate_case(case)
    _check_connected(case)
    length(bounds)==2 && all(isfinite,bounds) && 0<bounds[1]<bounds[2] ||
        throw(ArgumentError("frequency bounds must be finite, positive and strictly ordered"))
    _check_inverter_inputs(case,plants,case.base_frequency)
    ids=vcat([p.generator_id for p in plants],[r.generator_id for r in responses])
    length(ids)==length(unique(ids)) && Set(ids)==Set(g.id for g in case.generators) ||
        throw(ArgumentError("each generator must have exactly one inverter or frequency-response law"))
    gens=Dict(g.id=>g for g in case.generators)
    effective=Dict(g.id=>_active_response_bounds(case,i) for (i,g) in enumerate(case.generators))
    all(r->!gens[r.generator_id].available || effective[r.generator_id][1]<=effective[r.generator_id][2],responses) ||
        throw(ArgumentError("empty effective active-response bounds"))
    responsive=any(p->p.frequency_response && _inverter_context(case,p).online &&
        _inverter_context(case,p).pmax>_inverter_context(case,p).pmin,plants) ||
        any(r->r.gain_pu_per_hz>0 && gens[r.generator_id].available &&
            effective[r.generator_id][2]>effective[r.generator_id][1],responses)
    (!require_responder || responsive) || throw(ArgumentError("at least one available frequency-responsive active range is required"))
    for (id,limits) in angle_bounds
        any(b->b.id==id,case.network.branches) && length(limits)==2 &&
            all(isfinite,limits) && limits[1]<=limits[2] || throw(ArgumentError("invalid branch angle bounds"))
    end
    nothing
end

function _frequency_power(case,r,f)
    gi=findfirst(g->g.id==r.generator_id,case.generators);g=case.generators[gi]
    lo,hi=_active_response_bounds(case,gi)
    g.available ? clamp(r.p_ref+r.gain_pu_per_hz*(r.f_ref_hz-f),lo,hi) : 0.0
end

"""A conditional AC equilibrium with common frequency and a complete active-response contract."""
struct CommonFrequencyResult
    opf::ACOPFResult{Float64}
    plants::Vector{StaticInverter}
    responses::Vector{GeneratorFrequencyResponse}
    frequency_hz::Float64
    frequency_bounds::Tuple{Float64,Float64}
    branch_angle_bounds::Dict{Int,Tuple{Float64,Float64}}
end

"""Solve common frequency jointly with AC balance and saturated resource response.

Every generator (including offline units) requires exactly one declared active law.
Loads remain constant power; conventional reactive injections remain OPF decisions.
One connected network only. `frequency_bounds` are explicit study assumptions in Hz;
optional `branch_angle_bounds` map branch IDs to (minimum, maximum) radians.
Fixed equipment and native voltage, thermal, P/Q and apparent limits are retained.
`objective_policy=:dispatch` retains the native dispatch-distance objective;
`:feasibility` uses a zero objective with identical physical/controller constraints.
This computes a conditional equilibrium, not nadir, RoCoF or dynamic stability.
"""
function solve_common_frequency(case::Case,plants::AbstractVector{StaticInverter},
    responses::AbstractVector{GeneratorFrequencyResponse};frequency_bounds,
    branch_angle_bounds=Dict{Int,Tuple{Float64,Float64}}(),initial_state=nothing,
    initial_frequency_hz::Real=case.base_frequency,objective_policy::Symbol=:dispatch,
    optimizer_factory=Ipopt.Optimizer,optimizer_attributes=Dict{String,Any}(),silent::Bool=true)
    objective_policy in (:dispatch,:feasibility) || throw(ArgumentError("unknown common-frequency objective policy"))
    _frequency_contract(case,plants,responses,frequency_bounds,branch_angle_bounds)
    isfinite(initial_frequency_hz) && initial_frequency_hz>0 || throw(ArgumentError("initial frequency must be positive and finite"))
    bounds=(Float64(frequency_bounds[1]),Float64(frequency_bounds[2]))
    angles=Dict(Int(k)=>(Float64(v[1]),Float64(v[2])) for (k,v) in branch_angle_bounds)
    model,v=_build_acopf_model(case;voltage_epsilon=1e-4,reactive_relative_epsilon=1e-4,
        reactive_epsilon=nothing,silent,optimizer_factory,initial_state)
    f=@variable(model,lower_bound=bounds[1],upper_bound=bounds[2],
        start=clamp(initial_frequency_hz,bounds...),base_name="common_frequency_hz")
    add_static_inverter_constraints!(model,case,v,plants;frequency_hz=f)
    for r in responses
        gi=findfirst(g->g.id==r.generator_id,case.generators);g=case.generators[gi]
        g.available || continue # Native builder fixes unavailable generation to zero.
        pg=v.pg[gi];pref=r.p_ref;k=r.gain_pu_per_hz;fref=r.f_ref_hz;lo,hi=_active_response_bounds(case,gi)
        if k==0 || lo==hi
            fix(pg,clamp(pref,lo,hi);force=true)
        else
            @NLconstraint(model,pg==min(hi,max(lo,pref+k*(fref-f))))
        end
    end
    bm=Dict(b.id=>i for (i,b) in enumerate(case.network.buses))
    for b in case.network.branches
        b.available && haskey(angles,b.id) || continue
        lo,hi=angles[b.id];vf=v.va[bm[b.from_bus]];vt=v.va[bm[b.to_bus]]
        @constraint(model,lo<=vf-vt<=hi)
    end
    objective_policy==:feasibility && @objective(model,Min,0.)
    for (key,val) in optimizer_attributes;set_optimizer_attribute(model,key,val);end
    optimize!(model)
    state=has_values(model) ? ACState(value.(v.vm),value.(v.va),value.(v.pg),value.(v.qg)) : nothing
    opf=ACOPFResult{Float64}(state,has_values(model) ? objective_value(model) : NaN,
        Symbol(string(termination_status(model))),Symbol(string(primal_status(model))),1e-4,1e-4,nothing)
    CommonFrequencyResult(opf,collect(plants),collect(responses),has_values(model) ? value(f) : NaN,bounds,angles)
end

"""Replay AC physics, frequency bounds, all active laws and inverter capability.

`frequency_sensitive` diagnoses nonzero local response at fixed solved voltage.
False means the reported frequency may lie on a saturated flat response interval;
true is not a proof of uniqueness of the coupled nonlinear AC equilibrium.
"""
function validate_common_frequency(case::Case,r::CommonFrequencyResult;tolerance::Real=1e-6)
    isfinite(tolerance) && tolerance>=0 || throw(ArgumentError("invalid frequency replay tolerance"))
    _frequency_contract(case,r.plants,r.responses,r.frequency_bounds,r.branch_angle_bounds)
    converged=r.opf.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
    f=r.frequency_hz;state=r.opf.state
    if isnothing(state) || !isfinite(f) || f<=0
        return (;valid=false,converged,ac=nothing,inverters=nothing,response_residuals=Float64[],
            frequency_sensitive=false,frequency_valid=false,angles_valid=false)
    end
    frequency_valid=r.frequency_bounds[1]-tolerance<=f<=r.frequency_bounds[2]+tolerance
    ac=validate_equilibrium(case,r.opf)
    inv=validate_static_inverters(case,state,r.plants;frequency_hz=f,tolerance)
    residuals=Float64[];sensitivity=0.0;h=min(1e-5,f/2)
    for law in r.responses
        gi=findfirst(g->g.id==law.generator_id,case.generators);g=case.generators[gi]
        push!(residuals,state.pg[gi]-_frequency_power(case,law,f))
        sensitivity+=abs(_frequency_power(case,law,f-h)-_frequency_power(case,law,f+h))/(2h)
    end
    for plant in r.plants
        inv.valid || break # Invalid voltage/controller states are already rejected; do not evaluate a sensitivity there.
        c=_inverter_context(case,plant)
        response(ff)=inverter_response(case,plant,state.vm[c.terminal];regulated_voltage=state.vm[c.regulated],frequency_hz=ff).p
        sensitivity+=abs(response(f-h)-response(f+h))/(2h)
    end
    bm=Dict(b.id=>i for (i,b) in enumerate(case.network.buses))
    angles_valid=all(!b.available || !haskey(r.branch_angle_bounds,b.id) ||
        r.branch_angle_bounds[b.id][1]-tolerance<=state.va[bm[b.from_bus]]-state.va[bm[b.to_bus]]<=r.branch_angle_bounds[b.id][2]+tolerance
        for b in case.network.branches)
    (;valid=converged && ac.valid && inv.valid && frequency_valid && angles_valid && all(x->isfinite(x)&&abs(x)<=tolerance,residuals),
        converged,ac,inverters=inv,response_residuals=residuals,frequency_sensitive=sensitivity>1e-8,frequency_valid,angles_valid)
end

_json_data(x::GeneratorFrequencyResponse)=Dict(string(k)=>_json_data(getfield(x,k)) for k in fieldnames(GeneratorFrequencyResponse))
function materialize_operating_point(case::Case,r::CommonFrequencyResult)
    report=validate_common_frequency(case,r)
    report.valid || throw(ArgumentError("common-frequency result failed replay"))
    context=Dict("origin"=>"CommonFrequencyResult","frequency_hz"=>r.frequency_hz,
        "frequency_bounds"=>collect(r.frequency_bounds),"frequency_sensitive"=>report.frequency_sensitive,
        "branch_angle_bounds"=>Dict(string(k)=>collect(v) for (k,v) in r.branch_angle_bounds),
        "inverters"=>model_data(r.plants),"frequency_responses"=>model_data(r.responses),
        "dynamic_qualification"=>"not_assessed")
    _materialized_point(case,r.opf.state,nothing,context)
end
