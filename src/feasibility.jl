import SHA

# A version change invalidates old qualifications when the mathematical contract
# or its independent checker changes. Search objectives are not part of feasibility.
const _FEASIBILITY_VERSION = 1

function _feasibility_canonical(x)
    x isa AbstractDict && return "{" * join((JSON.json(string(k)) * ":" *
        _feasibility_canonical(x[k]) for k in sort!(collect(keys(x)); by=string)), ",") * "}"
    x isa AbstractVector && return "[" * join(_feasibility_canonical.(x), ",") * "]"
    return JSON.json(x)
end
_feasibility_hash(x) = bytes2hex(SHA.sha256(_feasibility_canonical(_json_data(x))))
_feasibility_curves(c) = [Dict("breakpoints"=>copy(droop_curve(d).breakpoints),
    "values"=>copy(droop_curve(d).values),"extrapolation"=>string(droop_curve(d).extrapolation)) for d in c.controls]
_feasibility_case_hash(c) = _feasibility_hash(Dict("case"=>_json_data(c),"curves"=>_feasibility_curves(c)))

"""A frozen, base-case feasibility contract. Omitted taps/banks remain fixed.

Selected banks are continuous susceptances within their specified envelope.
`angle_limits` maps branch IDs to (minimum, maximum) bus-angle differences in
radians. All physical checks use exact PWL droops, regardless of search encoding.
The constructor copies the inputs; subsequent mutation of the snapshot is rejected.
This is not a coupled SCOPF contract.
"""
struct FeasibilityProblem
    case::Case
    tap_controls::Vector{TapControl}
    shunt_controls::Vector{ShuntControl}
    angle_limits::Dict{Int,Tuple{Float64,Float64}}
    tolerances::NamedTuple
    fingerprint::String
end

function _feasibility_payload(case, taps, shunts, angles, tolerances)
    Dict("checker_version" => _FEASIBILITY_VERSION, "case" => _json_data(case),
        "exact_droop_curves" => _feasibility_curves(case),
        "tap_controls" => _json_data(taps), "shunt_controls" => _json_data(shunts),
        "angle_limits_rad" => _json_data(angles), "tolerances" => _json_data(tolerances),
        "scope" => "single AC equilibrium; fixed candidate droops; continuous selected banks")
end
function FeasibilityProblem(case::Case; tap_controls=TapControl[], shunt_controls=ShuntControl[],
    angle_limits=Dict(), power_tolerance=1e-6, droop_tolerance=1e-5,
    limit_tolerance=1e-6, unavailable_tolerance=1e-8, setting_tolerance=1e-8,
    angle_tolerance=1e-6)
    isnothing(case.network) && throw(ArgumentError("feasibility requires an AC network"))
    validate_case(case)
    any(g->!isnothing(g.s_rated),case.generators) && throw(ArgumentError(
        "frozen feasibility certificates do not yet support P-dependent apparent-power capability"))
    for d in case.controls
        expected=VoltVarDroop(d.schedule,d.slope,d.q_at_deadband,d.capability)
        _feasibility_curves((;controls=[d]))==_feasibility_curves((;controls=[expected])) ||
            throw(ArgumentError("droop knots differ from their physical parameters"))
    end
    _check_tap_controls(case,tap_controls); _check_shunt_controls(case,shunt_controls)
    ts = (; power_tolerance=Float64(power_tolerance), droop_tolerance=Float64(droop_tolerance),
        limit_tolerance=Float64(limit_tolerance), unavailable_tolerance=Float64(unavailable_tolerance),
        setting_tolerance=Float64(setting_tolerance), angle_tolerance=Float64(angle_tolerance))
    all(x -> isfinite(x) && x >= 0, ts) || throw(ArgumentError("invalid feasibility tolerances"))
    angles = Dict{Int,Tuple{Float64,Float64}}()
    for (id, bounds) in angle_limits
        any(b -> b.id==id,case.network.branches) || throw(ArgumentError("unknown angle-limit branch"))
        length(bounds)==2 || throw(ArgumentError("angle limits must have two endpoints"))
        lo,hi = Float64.(bounds)
        isfinite(lo) && isfinite(hi) && lo<=hi || throw(ArgumentError("invalid angle limits"))
        angles[id]=(lo,hi)
    end
    c=deepcopy(case)
    taps=sort!(deepcopy(collect(tap_controls));by=x->x.branch_id)
    shunts=sort!(deepcopy(collect(shunt_controls));by=x->x.bank_id)
    fp=_feasibility_hash(_feasibility_payload(c,taps,shunts,angles,ts))
    FeasibilityProblem(c,taps,shunts,angles,ts,fp)
end
"""Return the scope SHA-256, rejecting mutation of any frozen physical data."""
function feasibility_fingerprint(p::FeasibilityProblem)
    any(g->!isnothing(g.s_rated),p.case.generators) && throw(ArgumentError(
        "frozen feasibility certificates do not yet support P-dependent apparent-power capability"))
    actual=_feasibility_hash(_feasibility_payload(p.case,p.tap_controls,p.shunt_controls,
        p.angle_limits,p.tolerances))
    actual==p.fingerprint || throw(ArgumentError("feasibility snapshot was mutated; create a new problem"))
    actual
end

"""An AC state and the actual equipment settings at that state; no solver claim."""
struct FeasibilityWitness
    state::ACState
    taps::Dict{Int,Float64}
    susceptances::Dict{Int,Float64}
    label::String
end
FeasibilityWitness(state::ACState; taps=Dict(),susceptances=Dict(),label="supplied") =
    FeasibilityWitness(deepcopy(state),Dict{Int,Float64}(taps),
        Dict{Int,Float64}(susceptances),String(label))
function FeasibilityWitness(r::JointDesignResult; label="joint-design result")
    isnothing(r.opf.state) && throw(ArgumentError("result has no operating point"))
    isempty(r.droops) || throw(ArgumentError("freeze optimized droops as a candidate before qualification"))
    isnothing(r.reactive_assignments) || throw(ArgumentError("explicit reactive modes are outside this gate's droop contract"))
    FeasibilityWitness(r.opf.state;taps=r.taps,susceptances=r.susceptances,label)
end

function _feasibility_physical_case(p,w)
    c=p.case; tol=p.tolerances.setting_tolerance
    allowed=Dict(t.branch_id=>t for t in p.tap_controls)
    known=Set(b.id for b in c.network.branches)
    all(id->id in known,keys(w.taps)) || throw(ArgumentError("unknown witness tap"))
    for b in c.network.branches
        x=get(w.taps,b.id,b.tap_ratio)
        isfinite(x) && x>0 || throw(ArgumentError("invalid witness tap"))
        if haskey(allowed,b.id)
            t=allowed[b.id]
            t.lower-tol<=x<=t.upper+tol || throw(ArgumentError("tap outside selected bounds"))
        else
            # Fixed means the supplied ratio, exactly. A tolerance must not
            # permit a witness from a different equipment configuration.
            x==b.tap_ratio || throw(ArgumentError("witness moves a fixed tap"))
        end
    end
    allowed_b=Dict(s.bank_id=>s for s in p.shunt_controls)
    all(id->haskey(allowed_b,id),keys(w.susceptances)) || throw(ArgumentError("witness moves an unselected bank"))
    settings=Dict{Int,Float64}()
    for (id,s) in allowed_b
        policy=_shunt_policy(c,s); x=get(w.susceptances,id,policy.supplied)
        isfinite(x) && policy.lower-tol<=x<=policy.upper+tol ||
            throw(ArgumentError("bank outside selected bounds"))
        settings[id]=x
    end
    with_shunt_settings(with_tap_settings(c,w.taps),settings)
end

"""Independently replay a witness against its frozen scope. Optimizer status is irrelevant."""
function validate_feasibility_witness(p::FeasibilityProblem,w::FeasibilityWitness)
    feasibility_fingerprint(p)
    try
        s=w.state; c=p.case; t=p.tolerances
        length(s.vm)==length(s.va)==length(c.network.buses) &&
            length(s.pg)==length(s.qg)==length(c.generators) ||
            throw(ArgumentError("witness dimensions differ from the frozen case"))
        all(isfinite,vcat(s.vm,s.va,s.pg,s.qg)) && all(>(0),s.vm) ||
            throw(ArgumentError("nonfinite or nonpositive witness state"))
        physical=_feasibility_physical_case(p,w)
        report=validate_equilibrium(physical,s;power_tolerance=t.power_tolerance,
            droop_tolerance=t.droop_tolerance,limit_tolerance=t.limit_tolerance,
            unavailable_tolerance=t.unavailable_tolerance)
        indices=_bus_indices(physical.network)
        angle_margin=Inf
        for b in physical.network.branches
            b.available && haskey(p.angle_limits,b.id) || continue
            lo,hi=p.angle_limits[b.id]; delta=s.va[indices[b.from_bus]]-s.va[indices[b.to_bus]]
            angle_margin=min(angle_margin,delta-lo,hi-delta)
        end
        reference_error=maximum((abs(s.va[i]) for (i,b) in enumerate(c.network.buses) if b.reference);init=0.)
        ok=report.valid && angle_margin >= -t.angle_tolerance && reference_error<=t.angle_tolerance
        Dict{String,Any}("valid"=>ok,"policy_valid"=>true,"physical"=>_json_data(report),
            "angle_min_margin_rad"=>_json_data(angle_margin),"reference_angle_error_rad"=>reference_error)
    catch e
        e isa InterruptException && rethrow()
        Dict{String,Any}("valid"=>false,"error"=>sprint(showerror,e))
    end
end

# These necessary-condition certificates use exact rational arithmetic on the
# stored binary numbers. They are conservative outer bounds, not local optima.
_fq(x::Real)=Rational{BigInt}(x)
function _feasibility_curve_value(control,v)
    curve=droop_curve(control); xs=_fq.(curve.breakpoints); ys=_fq.(curve.values)
    v<=first(xs) && return first(ys)
    v>=last(xs) && return last(ys)
    i=searchsortedlast(xs,v)
    ys[i]+(v-xs[i])*(ys[i+1]-ys[i])/(xs[i+1]-xs[i])
end
function _feasibility_q_interval(p,g)
    t=p.tolerances
    g.available || return (-_fq(t.unavailable_tolerance),_fq(t.unavailable_tolerance))
    lo,hi=_fq(g.q_min)-_fq(t.limit_tolerance),_fq(g.q_max)+_fq(t.limit_tolerance)
    a=findfirst(a->a.generator_id==g.id,p.case.attachments)
    if !isnothing(a)
        attachment=p.case.attachments[a]; control=p.case.controls[attachment.control_id]
        bus=only(b for b in p.case.network.buses if b.id==attachment.location.bus_id)
        vlo=max(_fq(0),_fq(bus.v_min)-_fq(t.limit_tolerance))
        vhi=_fq(bus.v_max)+_fq(t.limit_tolerance)
        lo=max(lo,_feasibility_curve_value(control,vhi)-_fq(t.droop_tolerance))
        hi=min(hi,_feasibility_curve_value(control,vlo)+_fq(t.droop_tolerance))
    end
    lo,hi
end
function _feasibility_p_interval(p,g)
    t=p.tolerances
    g.available || return (-_fq(t.unavailable_tolerance),_fq(t.unavailable_tolerance))
    lo,hi=_fq(g.p_min),_fq(g.p_max)
    for a in p.case.attachments
        a.generator_id==g.id || continue
        cap=p.case.controls[a.control_id].capability
        lo=max(lo,_fq(cap.p_min)); hi=min(hi,_fq(cap.p_max))
    end
    lo-_fq(t.limit_tolerance),hi+_fq(t.limit_tolerance)
end
function _feasibility_components(c)
    remaining=Set(b.id for b in c.network.buses); parts=Vector{Int}[]
    while !isempty(remaining)
        component=Set([minimum(remaining)]); pending=collect(component)
        while !isempty(pending)
            id=pop!(pending)
            for b in c.network.branches
                b.available || continue
                other=b.from_bus==id ? b.to_bus : b.to_bus==id ? b.from_bus : nothing
                isnothing(other) || other in component || (push!(component,other);push!(pending,other))
            end
        end
        push!(parts,sort!(collect(component))); setdiff!(remaining,component)
    end
    parts
end
function _feasibility_certificate(kind,ids,lower,upper)
    Dict{String,Any}("method"=>kind,"ids"=>ids,"arithmetic"=>"exact rational on stored inputs",
        "necessary_lower_exact"=>string(lower),"necessary_upper_exact"=>string(upper),
        "strict_gap_exact"=>string(lower-upper),"strict_gap_pu"=>Float64(lower-upper))
end

function _feasibility_analytic_certificate(p)
    c=p.case; t=p.tolerances; zeroq=_fq(0)
    # Every available branch has R >= 0 and every shunt has G >= 0.
    # Hence total active generation in each island must cover its net demand.
    # Ignoring all losses/shunt consumption only enlarges the feasible set.
    for ids in _feasibility_components(c)
        demand=sum((_fq(l.p) for l in c.loads if l.bus_id in ids);init=zeroq)
        cap=sum((last(_feasibility_p_interval(p,g)) for g in c.generators if g.bus_id in ids);init=zeroq)
        lower=demand-length(ids)*_fq(t.power_tolerance)
        lower>cap && return _feasibility_certificate("island_active_capacity",ids,lower,cap)
    end
    for g in c.generators
        lo,hi=_feasibility_q_interval(p,g)
        lo>hi && return _feasibility_certificate("droop_reachable_q",[g.id],lo,hi)
    end
    # Necessary nodal Q balance: each incident terminal satisfies |Q| <= Smax.
    # Droop Q intervals and shunt B*V^2 intervals retain all feasible states,
    # including every permitted selected tap and continuous bank setting.
    for bus in c.network.buses
        qlo=qhi=zeroq
        for g in c.generators
            g.bus_id==bus.id || continue
            lo,hi=_feasibility_q_interval(p,g);qlo+=lo;qhi+=hi
        end
        demand=sum((_fq(l.q) for l in c.loads if l.bus_id==bus.id);init=zeroq)
        blo=bhi=sum((_fq(s.susceptance) for s in c.network.shunts if s.available && s.bus_id==bus.id);init=zeroq)
        for bank in c.network.banks
            bank.available && bank.bus_id==bus.id || continue
            selected=findfirst(s->s.bank_id==bank.id,p.shunt_controls)
            if isnothing(selected)
                b=sum((_fq(n)*_fq(step) for (n,step) in zip(bank.state,bank.step_susceptances));init=zeroq)
                blo+=b;bhi+=b
            else
                policy=_shunt_policy(c,p.shunt_controls[selected])
                blo+=_fq(policy.lower)-_fq(t.setting_tolerance)
                bhi+=_fq(policy.upper)+_fq(t.setting_tolerance)
            end
        end
        vlo=max(zeroq,_fq(bus.v_min)-_fq(t.limit_tolerance));vhi=_fq(bus.v_max)+_fq(t.limit_tolerance)
        shuntlo,shunthi=extrema((blo*vlo^2,blo*vhi^2,bhi*vlo^2,bhi*vhi^2))
        qlo+=shuntlo-demand; qhi+=shunthi-demand
        capacity=sum((_fq(b.thermal_limit)+_fq(t.limit_tolerance) for b in c.network.branches
            if b.available && (b.from_bus==bus.id || b.to_bus==bus.id));init=zeroq)+_fq(t.power_tolerance)
        qlo>capacity && return _feasibility_certificate("bus_reactive_export",[bus.id],qlo,capacity)
        -capacity>qhi && return _feasibility_certificate("bus_reactive_import",[bus.id],-capacity,qhi)
    end
    nothing
end

"""Tri-state decision and its witness or replayable certificate, with a search ledger."""
struct FeasibilityResult
    fingerprint::String
    status::Symbol
    witness::Union{Nothing,FeasibilityWitness}
    certificate::Union{Nothing,Dict{String,Any}}
    attempts::Vector{Dict{String,Any}}
    reason::String
end

"""Replay seeds, check global necessary conditions, then optionally search locally.

A local failure, positive local restoration objective, or absence of a witness
returns `:unresolved`. `:certified_infeasible` requires an independently replayed
certificate. Optional `lp_options` and `global_options` select bounded escalation
backends; neither runs by default. Solver-reported global bounds alone do not
upgrade the gate. Inconclusive certificates or unsupported backends are unresolved.
"""
function check_feasibility(p::FeasibilityProblem; witnesses=FeasibilityWitness[],
    initial_states=ACState[], solve_missing=true, smooth_epsilon=1e-6,
    optimizer_factory=Ipopt.Optimizer,
    optimizer_attributes=Dict("max_iter"=>1000,"max_cpu_time"=>30.,"tol"=>1e-9),
    lp_options=nothing,global_options=nothing,_search=nothing)
    fp=feasibility_fingerprint(p); attempts=Dict{String,Any}[]
    supplied=collect(witnesses)
    append!(supplied,[FeasibilityWitness(s;label="initial state $i") for (i,s) in enumerate(initial_states)])
    for w in supplied
        check=validate_feasibility_witness(p,w)
        push!(attempts,Dict("stage"=>"replay","label"=>w.label,"point"=>_json_data(w),"checks"=>check))
        if check["valid"]
            return FeasibilityResult(fp,:feasible,deepcopy(w),nothing,attempts,"independently validated operating point")
        end
    end
    certificate=_feasibility_analytic_certificate(p)
    if !isnothing(certificate)
        return FeasibilityResult(fp,:certified_infeasible,nothing,certificate,attempts,
            "global necessary condition contradicted by exact bounds")
    end
    if solve_missing
        starts=isempty(initial_states) ? [nothing] : collect(initial_states)
        for (i,start) in enumerate(starts)
            record=Dict{String,Any}("stage"=>"local_search","start"=>i,
                "initial_state"=>_json_data(start),
                "optimizer"=>string(optimizer_factory),"attributes"=>_json_data(optimizer_attributes),
                "objective"=>"constant zero","smooth_epsilon"=>smooth_epsilon)
            push!(attempts,record)
            try
                hook=function (phase,model)
                    phase==:built || return
                    @objective(model,Min,0.)
                    indices=_bus_indices(p.case.network)
                    for b in p.case.network.branches
                        b.available && haskey(p.angle_limits,b.id) || continue
                        lo,hi=p.angle_limits[b.id]
                        vf=variable_by_name(model,"va[$(indices[b.from_bus])]")
                        vt=variable_by_name(model,"va[$(indices[b.to_bus])]")
                        @constraint(model,lo<=vf-vt<=hi)
                    end
                end
                r=isnothing(_search) ? optimize_joint_design(p.case;
                    tap_controls=p.tap_controls,shunt_controls=p.shunt_controls,
                    initial_state=start,smooth_epsilon,optimizer_factory,optimizer_attributes,
                    _measurement_hook=hook) : _search(p,start)
                feasibility_fingerprint(p)
                record["termination_status"]=string(r.opf.termination_status)
                record["primal_status"]=string(r.opf.primal_status)
                if !isnothing(r.opf.state)
                    w=FeasibilityWitness(r;label="local search $i")
                    record["point"]=_json_data(w)
                    check=validate_feasibility_witness(p,w);record["checks"]=check
                    if check["valid"]
                        return FeasibilityResult(fp,:feasible,w,nothing,attempts,
                            "independently validated operating point; optimizer status not used as proof")
                    end
                end
            catch e
                e isa InterruptException && rethrow()
                record["error"]=sprint(showerror,e)
            end
        end
    end
    feasibility_fingerprint(p)
    if !isnothing(lp_options)
        try
            r=certify_feasibility_lp(p;lp_options...)
            append!(attempts,r.attempts)
            r.status==:certified_infeasible && return FeasibilityResult(fp,r.status,nothing,r.certificate,attempts,r.reason)
        catch e
            e isa InterruptException && rethrow()
            push!(attempts,Dict("stage"=>"verified_outer_lp","error"=>sprint(showerror,e)))
        end
    end
    if !isnothing(global_options)
        try
            global_result=solve_global_feasibility(p;global_options...).result
            append!(attempts,global_result.attempts)
            global_result.status==:feasible && return FeasibilityResult(fp,:feasible,global_result.witness,nothing,attempts,global_result.reason)
        catch e
            e isa InterruptException && rethrow()
            push!(attempts,Dict("stage"=>"global_escalation","error"=>sprint(showerror,e)))
        end
    end
    feasibility_fingerprint(p)
    FeasibilityResult(fp,:unresolved,nothing,nothing,attempts,
        "no validated witness or independently verified certificate; solver failures do not prove infeasibility")
end

"""Revalidate evidence and scope instead of trusting a stored status or fingerprint alone."""
function verify_feasibility_result(p::FeasibilityProblem,r::FeasibilityResult)
    feasibility_fingerprint(p)==r.fingerprint || return false
    if r.status==:feasible
        return !isnothing(r.witness) && isnothing(r.certificate) &&
            validate_feasibility_witness(p,r.witness)["valid"]
    elseif r.status==:certified_infeasible
        if !isnothing(r.certificate) && get(r.certificate,"method",nothing)=="rational_sparse_outer_lp"
            return isnothing(r.witness) && _verify_feasibility_lp_certificate(p,r.certificate)
        end
        certificate=_feasibility_analytic_certificate(p)
        return isnothing(r.witness) && !isnothing(certificate) &&
            _feasibility_canonical(certificate)==_feasibility_canonical(r.certificate)
    elseif r.status==:unresolved
        return isnothing(r.witness) && isnothing(r.certificate)
    end
    false
end
function _json_data(w::FeasibilityWitness)
    Dict("state"=>_json_data(w.state),"taps"=>_json_data(w.taps),
        "susceptances"=>_json_data(w.susceptances),"label"=>w.label)
end
function _json_data(r::FeasibilityResult)
    Dict("fingerprint"=>r.fingerprint,"status"=>string(r.status),"witness"=>_json_data(r.witness),
        "certificate"=>r.certificate,"attempts"=>r.attempts,"reason"=>r.reason)
end
function _feasibility_record(p,r)
    verify_feasibility_result(p,r) || throw(ArgumentError("invalid or stale feasibility evidence"))
    Dict("problem"=>_feasibility_payload(p.case,p.tap_controls,p.shunt_controls,p.angle_limits,p.tolerances),
        "result"=>_json_data(r))
end
"""Save the full frozen problem, independently checked evidence and search attempts."""
function write_feasibility_result(path,p::FeasibilityProblem,r::FeasibilityResult)
    _write_scopf_json(path,"DroopOPF.FeasibilityResult",_feasibility_record(p,r))
end

"""Load cached evidence only for an explicitly supplied matching problem, and replay it."""
function read_feasibility_result(path,p::FeasibilityProblem)
    data=_read_scopf_json(path,"DroopOPF.FeasibilityResult")
    _feasibility_hash(data["problem"])==feasibility_fingerprint(p) ||
        throw(ArgumentError("cached feasibility problem differs from the requested scope"))
    d=data["result"];wdata=d["witness"]
    w=if isnothing(wdata)
        nothing
    else
        s=wdata["state"]
        FeasibilityWitness(ACState(Float64.(s["vm"]),Float64.(s["va"]),Float64.(s["pg"]),Float64.(s["qg"]));
            taps=Dict(parse(Int,k)=>Float64(v) for (k,v) in wdata["taps"]),
            susceptances=Dict(parse(Int,k)=>Float64(v) for (k,v) in wdata["susceptances"]),label=wdata["label"])
    end
    certificate=isnothing(d["certificate"]) ? nothing : Dict{String,Any}(d["certificate"])
    r=FeasibilityResult(d["fingerprint"],Symbol(d["status"]),w,certificate,
        Dict{String,Any}[Dict{String,Any}(a) for a in d["attempts"]],d["reason"])
    verify_feasibility_result(p,r) || throw(ArgumentError("cached feasibility evidence failed independent replay"))
    r
end

"""Candidate droops and all required calibration/demand feasibility decisions."""
struct DroopQualification
    candidate::Case
    candidate_fingerprint::String
    labels::Tuple
    problems::Tuple
    results::Tuple
end
function _feasibility_scaled_case(c,factor)
    Case(c.id;base_power=c.base_power,base_frequency=c.base_frequency,network=c.network,
        generators=c.generators,controls=c.controls,attachments=c.attachments,
        loads=[Load(l.id,l.bus_id;p=factor*l.p,q=factor*l.q) for l in c.loads])
end

"""Qualify a proposed droop replacement before accepting it for S1 analysis.

The source calibration point must replay both before and after replacement;
optimization cannot repair a failed calibration check. Then both the original
and replacement cases must have a witness at every required demand factor.
All candidate curves are tested together. This does not certify shared SCOPF
dispatch or preventive equipment settings across scenarios.
"""
function qualify_droop_replacement(reference::Case,candidate::Case;
    calibration_state::ACState,load_factors=(1.,.9),witnesses=Dict(),
    initial_states=[calibration_state],problem_options=(;),search_options=(;))
    isempty(load_factors) && throw(ArgumentError("at least one demand condition is required"))
    all(x->isfinite(x) && x>=0,load_factors) || throw(ArgumentError("invalid demand factors"))
    length(unique(load_factors))==length(load_factors) || throw(ArgumentError("duplicate demand factors"))
    before=_json_data(reference);after=_json_data(candidate)
    for field in ("id","controls","attachments")
        delete!(before,field);delete!(after,field)
    end
    _feasibility_canonical(before)==_feasibility_canonical(after) ||
        throw(ArgumentError("droop replacement must preserve demand, network and generator data"))
    labels=String[];problems=FeasibilityProblem[];results=FeasibilityResult[]
    for (label,c) in (("calibration/source",reference),("calibration/candidate",candidate))
        p=FeasibilityProblem(c;problem_options...)
        r=check_feasibility(p;witnesses=[FeasibilityWitness(calibration_state;label="calibration")],solve_missing=false)
        push!(labels,label);push!(problems,p);push!(results,r)
    end
    for factor in load_factors, (name,c) in (("source",reference),("candidate",candidate))
        label="$name/$(Float64(factor))";p=FeasibilityProblem(_feasibility_scaled_case(c,factor);problem_options...)
        r=check_feasibility(p;witnesses=get(witnesses,label,FeasibilityWitness[]),initial_states,
            search_options...)
        push!(labels,label);push!(problems,p);push!(results,r)
    end
    DroopQualification(deepcopy(candidate),_feasibility_case_hash(candidate),Tuple(labels),Tuple(problems),Tuple(results))
end

"""Return the candidate only after every required condition has a revalidated witness."""
function require_qualified_replacement(q::DroopQualification)
    _feasibility_case_hash(q.candidate)==q.candidate_fingerprint || throw(ArgumentError("candidate changed since qualification"))
    length(q.results)==length(q.problems)==length(q.labels) && length(q.results)>=4 ||
        throw(ArgumentError("incomplete droop qualification"))
    failed=[label for (label,p,r) in zip(q.labels,q.problems,q.results)
        if r.status!=:feasible || !verify_feasibility_result(p,r)]
    isempty(failed) || throw(ArgumentError("droop replacement is not qualified: "*join(failed,", ")))
    deepcopy(q.candidate)
end
"""Save the complete precursor qualification, including blocked conditions."""
function write_droop_qualification(path,q::DroopQualification)
    _feasibility_case_hash(q.candidate)==q.candidate_fingerprint || throw(ArgumentError("candidate changed since qualification"))
    accepted=all(r.status==:feasible && verify_feasibility_result(p,r) for (p,r) in zip(q.problems,q.results))
    payload=Dict("candidate_fingerprint"=>q.candidate_fingerprint,"accepted"=>accepted,
        "scope"=>"independent S1 demand conditions; not coupled SCOPF feasibility",
        "conditions"=>Dict(label=>_feasibility_record(p,r) for (label,p,r) in zip(q.labels,q.problems,q.results)))
    _write_scopf_json(path,"DroopOPF.DroopQualification",payload)
end
