# Optional global escalation. No global solver is a mandatory package dependency.
# Models are sparse in network edges; there is no dense nbus-by-nbus SDP matrix.

function _global_angle_radii(p,lower,upper)
    c=p.case;net=c.network;idx=_bus_indices(net);n=length(net.buses)
    adjacency=[Tuple{Int,Float64}[] for _ in 1:n]
    for b in net.branches
        b.available || continue
        i,j=idx[b.from_bus],idx[b.to_bus];tau=b.tap_ratio
        s=b.thermal_limit+p.tolerances.limit_tolerance
        # Bound |Vf/tau - Vt| using each terminal's current limit and charging.
        dist=hypot(b.resistance,b.reactance)*min(tau*s/lower[i]+abs(b.charging)*upper[i]/(2tau),
            s/lower[j]+abs(b.charging)*upper[j]/2)
        ratio=dist/(2min(lower[i]/tau,lower[j]))
        angle=ratio>=1 ? pi : 2asin(clamp(ratio,0.,1.))
        angle=min(pi,angle+abs(rem2pi(b.phase_shift,RoundNearest))+1e-8)
        if haskey(p.angle_limits,b.id)
            lo,hi=p.angle_limits[b.id]
            angle=min(angle,max(abs(lo),abs(hi))+p.tolerances.angle_tolerance+1e-8)
        end
        push!(adjacency[i],(j,angle));push!(adjacency[j],(i,angle))
    end
    radii=fill(Inf,n)
    for ids in _feasibility_components(c)
        refs=[b.id for b in net.buses if b.reference && b.id in ids]
        radii[idx[isempty(refs) ? first(ids) : first(refs)]]=0.
    end
    visited=falses(n)
    for _ in 1:n
        i=argmin([visited[k] ? Inf : radii[k] for k in 1:n]);visited[i]=true
        for (j,a) in adjacency[i]
            radii[j]=min(radii[j],radii[i]+a)
        end
    end
    min.(radii,pi)
end

function _global_curve_knots(control,lo,hi)
    curve=droop_curve(control)
    xs=sort!(unique([lo;[x for x in curve.breakpoints if lo<x<hi];hi]))
    ys=[clamp(evaluate(curve,x),control.capability.q_min,control.capability.q_max) for x in xs]
    xs,ys
end

"""Build a bounded voltage-restoration model for a frozen fixed-equipment problem.

`mode=:global` uses rectangular AC voltages and exact SOS2 droop regions.
`mode=:soc` uses sparse edge-product SOC envelopes and droop graph convex hulls.
Only `target_bus` may exceed its original upper voltage bound, by `delta` in
`[0,max_relaxation]`. Frozen feasibility tolerances are included in both models.
The SOC model is an outer relaxation, never a feasible-point certificate.
Angle windows outside (-pi/2,pi/2) are explicitly omitted (an outer relaxation).
Pass an optional global/conic solver factory; no optimization occurs here.
"""
function build_global_feasibility_model(p::FeasibilityProblem;target_bus::Integer,
    max_relaxation=.05,mode=:global,optimizer_factory=nothing,voltage_bound_result=nothing)
    feasibility_fingerprint(p)
    any(g->!isnothing(g.s_rated),p.case.generators) && throw(ArgumentError(
        "global droop graph escalation does not yet support apparent-power circles"))
    isempty(p.tap_controls) && isempty(p.shunt_controls) || throw(ArgumentError(
        "global escalation currently supports fixed equipment only; do not freeze selected controls silently"))
    mode in (:global,:soc) || throw(ArgumentError("mode must be :global or :soc"))
    isfinite(max_relaxation) && max_relaxation>=0 || throw(ArgumentError("invalid relaxation cap"))
    c=p.case;net=c.network;idx=_bus_indices(net);t=p.tolerances
    haskey(idx,target_bus) || throw(ArgumentError("unknown target bus"))
    n=length(net.buses);ng=length(c.generators);edges=[b for b in net.branches if b.available]
    ne=length(edges);target=idx[target_bus]
    lower=[b.v_min-t.limit_tolerance for b in net.buses]
    all(>(0),lower) || throw(ArgumentError("global angle bounds require strictly positive tolerated voltage lower bounds"))
    upper=[b.v_max+t.limit_tolerance+(b.id==target_bus ? max_relaxation : 0.) for b in net.buses]
    if !isnothing(voltage_bound_result)
        max_relaxation==0 || throw(ArgumentError("strict-case voltage proofs require max_relaxation=0"))
        bounds=verified_feasibility_voltage_bounds(p,voltage_bound_result)
        for (i,b) in enumerate(net.buses)
            lower[i]=max(lower[i],bounds[b.id][1]);upper[i]=min(upper[i],bounds[b.id][2])
        end
    end
    model=isnothing(optimizer_factory) ? Model() : Model(optimizer_factory)
    @variable(model,0<=delta<=max_relaxation)
    @variable(model,lower[i]<=v[i=1:n]<=upper[i])
    @variable(model,lower[i]^2<=w[i=1:n]<=upper[i]^2)
    @constraint(model,v[target]<=net.buses[target].v_max+t.limit_tolerance+delta)
    @objective(model,Min,delta)
    pbound=[Float64.(_feasibility_p_interval(p,g)) for g in c.generators]
    qbound=[g.available ? (g.q_min-t.limit_tolerance,g.q_max+t.limit_tolerance) :
        (-t.unavailable_tolerance,t.unavailable_tolerance) for g in c.generators]
    @variable(model,pbound[i][1]<=pg[i=1:ng]<=pbound[i][2])
    @variable(model,qbound[i][1]<=qg[i=1:ng]<=qbound[i][2])
    e=f=nothing;angle_radii=_global_angle_radii(p,lower,upper)
    if mode==:global
        @variable(model,-upper[i]<=er[i=1:n]<=upper[i])
        @variable(model,-upper[i]<=ei[i=1:n]<=upper[i])
        e=er;f=ei
        for i in 1:n
            cosine=cos(angle_radii[i]);sine=angle_radii[i]>=pi/2 ? 1. : sin(angle_radii[i])
            set_lower_bound(e[i],max(-upper[i],(cosine>=0 ? lower[i] : upper[i])*cosine-1e-8))
            set_lower_bound(f[i],max(-upper[i],-upper[i]*sine-1e-8))
            set_upper_bound(f[i],min(upper[i],upper[i]*sine+1e-8))
            @constraint(model,w[i]==e[i]^2+f[i]^2)
            @constraint(model,w[i]==v[i]^2)
        end
        # One gauge per island. Other reference-angle requirements remain in
        # independent replay; omitting them only enlarges the search domain.
        for ids in _feasibility_components(c)
            refs=[b.id for b in net.buses if b.reference && b.id in ids]
            i=idx[isempty(refs) ? first(ids) : first(refs)]
            fix(f[i],0.;force=true);set_lower_bound(e[i],lower[i])
        end
    else
        for i in 1:n
            @constraint(model,v[i]^2<=w[i])
            @constraint(model,w[i]<=(lower[i]+upper[i])*v[i]-lower[i]*upper[i])
        end
    end
    edge_bounds=[upper[idx[b.from_bus]]*upper[idx[b.to_bus]] for b in edges]
    @variable(model,-edge_bounds[k]<=wr[k=1:ne]<=edge_bounds[k])
    @variable(model,-edge_bounds[k]<=wi[k=1:ne]<=edge_bounds[k])
    rates=[b.thermal_limit+t.limit_tolerance for b in edges]
    @variable(model,-rates[k]<=pf[k=1:ne]<=rates[k])
    @variable(model,-rates[k]<=qf[k=1:ne]<=rates[k])
    @variable(model,-rates[k]<=pt[k=1:ne]<=rates[k])
    @variable(model,-rates[k]<=qt[k=1:ne]<=rates[k])
    omitted_angles=Int[]
    for (k,b) in enumerate(edges)
        i,j=idx[b.from_bus],idx[b.to_bus]
        if mode==:global
            @constraint(model,wr[k]==e[i]*e[j]+f[i]*f[j])
            @constraint(model,wi[k]==f[i]*e[j]-e[i]*f[j])
        else
            # Rotated SOC, written quadratically for global QC solvers. Both
            # diagonal terms have strictly positive bounds.
            @constraint(model,wr[k]^2+wi[k]^2<=w[i]*w[j])
        end
        yff,yft,ytf,ytt=_branch_admittances(b)
        @constraint(model,pf[k]==real(yff)*w[i]+real(yft)*wr[k]+imag(yft)*wi[k])
        @constraint(model,qf[k]==-imag(yff)*w[i]-imag(yft)*wr[k]+real(yft)*wi[k])
        @constraint(model,pt[k]==real(ytt)*w[j]+real(ytf)*wr[k]-imag(ytf)*wi[k])
        @constraint(model,qt[k]==-imag(ytt)*w[j]-imag(ytf)*wr[k]-real(ytf)*wi[k])
        @constraint(model,pf[k]^2+qf[k]^2<=rates[k]^2)
        @constraint(model,pt[k]^2+qt[k]^2<=rates[k]^2)
        if haskey(p.angle_limits,b.id)
            lo,hi=p.angle_limits[b.id];lo-=t.angle_tolerance;hi+=t.angle_tolerance
            if -pi/2<lo<=hi<pi/2
                @constraint(model,wr[k]>=0)
                @constraint(model,wi[k]>=tan(lo)*wr[k])
                @constraint(model,wi[k]<=tan(hi)*wr[k])
            else
                push!(omitted_angles,b.id)
            end
        end
    end
    for (i,bus) in enumerate(net.buses)
        gens=[k for (k,g) in enumerate(c.generators) if g.bus_id==bus.id]
        from=[k for (k,b) in enumerate(edges) if b.from_bus==bus.id]
        to=[k for (k,b) in enumerate(edges) if b.to_bus==bus.id]
        pd=sum((l.p for l in c.loads if l.bus_id==bus.id);init=0.)
        qd=sum((l.q for l in c.loads if l.bus_id==bus.id);init=0.)
        shunt=sum((complex(s.conductance,s.susceptance) for s in net.shunts if s.available && s.bus_id==bus.id);init=0im)
        shunt+=sum((bank_admittance(b) for b in net.banks if b.bus_id==bus.id);init=0im)
        @constraint(model,-t.power_tolerance<=sum(pg[k] for k in gens)-pd-
            sum(pf[k] for k in from)-sum(pt[k] for k in to)-real(shunt)*w[i]<=t.power_tolerance)
        @constraint(model,-t.power_tolerance<=sum(qg[k] for k in gens)-qd-
            sum(qf[k] for k in from)-sum(qt[k] for k in to)+imag(shunt)*w[i]<=t.power_tolerance)
    end
    curves=Any[];gi=Dict(g.id=>i for (i,g) in enumerate(c.generators))
    for a in c.attachments
        g=gi[a.generator_id];c.generators[g].available || continue
        i=idx[a.location.bus_id];control=c.controls[a.control_id]
        xs,ys=_global_curve_knots(control,lower[i],upper[i])
        lambda=@variable(model,[1:length(xs)],lower_bound=0,upper_bound=1,
            base_name="droop_$(a.control_id)_lambda")
        @constraint(model,sum(lambda)==1)
        @constraint(model,v[i]==sum(xs[k]*lambda[k] for k in eachindex(xs)))
        @constraint(model,-t.droop_tolerance<=qg[g]-sum(ys[k]*lambda[k] for k in eachindex(xs))<=t.droop_tolerance)
        mode==:global && length(xs)>1 && @constraint(model,lambda in SOS2(xs))
        push!(curves,(bus=i,generator=g,xs=xs,ys=ys,lambda=lambda))
    end
    vars=(delta=delta,v=v,w=w,e=e,f=f,pg=pg,qg=qg,wr=wr,wi=wi,pf=pf,qf=qf,pt=pt,qt=qt,curves=curves)
    metadata=Dict{String,Any}("fingerprint"=>p.fingerprint,"mode"=>string(mode),
        "target_bus"=>target_bus,"max_relaxation"=>max_relaxation,
        "variables"=>num_variables(model),"active_edges"=>ne,"omitted_angle_windows"=>omitted_angles,
        "angle_radius_max_rad"=>maximum(angle_radii),"angle_bounds"=>"thermal-current and supplied-angle path bounds; numerical outward padding",
        "verified_voltage_bounds_used"=>!isnothing(voltage_bound_result),
        "droop_regions"=>"all regions, including saturation",
        "angle_representation"=>"periodic edge windows; original unwrapped angles rechecked on witnesses",
        "bound_kind"=>"numerical solver bound; requires independent verification before gate certification")
    (model=model,variables=vars,metadata=metadata,problem=p,edges=edges)
end

"""Map an AC point to every lifted variable and SOS2 weight, without changing the problem."""
function seed_global_feasibility!(built,state::ACState)
    p=built.problem;c=p.case;idx=_bus_indices(c.network);x=built.variables
    length(state.vm)==length(x.v) && length(state.pg)==length(x.pg) || throw(ArgumentError("seed dimensions differ"))
    target=idx[built.metadata["target_bus"]]
    delta=max(0.,state.vm[target]-c.network.buses[target].v_max-p.tolerances.limit_tolerance)
    set_start_value(x.delta,delta)
    angles=copy(state.va)
    for ids in _feasibility_components(c)
        refs=[b.id for b in c.network.buses if b.reference && b.id in ids]
        origin=idx[isempty(refs) ? first(ids) : first(refs)]
        shift=angles[origin]
        for id in ids
            angles[idx[id]]-=shift
        end
    end
    for i in eachindex(x.v)
        set_start_value(x.v[i],state.vm[i]);set_start_value(x.w[i],state.vm[i]^2)
        if !isnothing(x.e)
            set_start_value(x.e[i],state.vm[i]*cos(angles[i]))
            set_start_value(x.f[i],state.vm[i]*sin(angles[i]))
        end
    end
    for i in eachindex(x.pg)
        set_start_value(x.pg[i],state.pg[i]);set_start_value(x.qg[i],state.qg[i])
    end
    flows=branch_flows(c.network,state);branchidx=Dict(b.id=>i for (i,b) in enumerate(c.network.branches))
    for (k,b) in enumerate(built.edges)
        i,j=idx[b.from_bus],idx[b.to_bus];a=angles[i]-angles[j]
        set_start_value(x.wr[k],state.vm[i]*state.vm[j]*cos(a))
        set_start_value(x.wi[k],state.vm[i]*state.vm[j]*sin(a))
        sf=flows.from[branchidx[b.id]];st=flows.to[branchidx[b.id]]
        set_start_value(x.pf[k],real(sf));set_start_value(x.qf[k],imag(sf))
        set_start_value(x.pt[k],real(st));set_start_value(x.qt[k],imag(st))
    end
    for curve in x.curves
        foreach(z->set_start_value(z,0.),curve.lambda)
        voltage=state.vm[curve.bus];xs=curve.xs
        if length(xs)==1
            set_start_value(only(curve.lambda),1.);continue
        end
        k=clamp(searchsortedlast(xs,voltage),1,length(xs)-1)
        alpha=(voltage-xs[k])/(xs[k+1]-xs[k])
        set_start_value(curve.lambda[k],1-alpha);set_start_value(curve.lambda[k+1],alpha)
    end
    point=Dict(z=>start_value(z) for z in all_variables(built.model))
    violations=primal_feasibility_report(built.model,point;atol=1e-7)
    (max_violation=maximum(values(violations);init=0.),violations=length(violations),delta=delta)
end

"""Run one explicitly budgeted global/SOC escalation and return its gate result and ledger.

Only independently replayed AC points can upgrade the gate here. Floating-point
solver bounds are retained as `solver_reported_infeasibility` evidence, not
promoted to independently verified certificates. This distinction also holds
at time limits and when the solver reports OPTIMAL/INFEASIBLE.
"""
function solve_global_feasibility(p::FeasibilityProblem;target_bus::Integer,
    optimizer_factory,mode=:global,max_relaxation=.05,initial_state=nothing,
    time_limit=60.,optimizer_attributes=Dict(),silent=true,voltage_bound_result=nothing)
    isfinite(time_limit) && time_limit>0 || throw(ArgumentError("time limit must be positive and finite"))
    built=build_global_feasibility_model(p;target_bus,max_relaxation,mode,optimizer_factory,voltage_bound_result)
    model=built.model;silent && set_silent(model)
    for (k,v) in optimizer_attributes
        set_optimizer_attribute(model,k,v)
    end
    set_time_limit_sec(model,time_limit)
    ledger=copy(built.metadata);ledger["stage"]="global_escalation"
    ledger["time_limit_seconds"]=time_limit;ledger["optimizer"]=string(optimizer_factory)
    ledger["optimizer_attributes"]=_json_data(optimizer_attributes)
    ledger["seed_audit"]=isnothing(initial_state) ? nothing : _json_data(seed_global_feasibility!(built,initial_state))
    start=time();optimize!(model);ledger["elapsed_seconds"]=time()-start
    ledger["termination_status"]=string(termination_status(model))
    bound=try objective_bound(model) catch;NaN end
    ledger["objective_bound_pu"]=_json_data(bound)
    ledger["objective_value_pu"]=has_values(model) ? _json_data(objective_value(model)) : nothing
    ledger["solver_reported_infeasibility"]=termination_status(model)==JuMP.MOI.INFEASIBLE || (isfinite(bound) && bound>0.)
    witness=nothing
    if mode==:global && has_values(model)
        x=built.variables
        state=ACState(value.(x.v),atan.(value.(x.f),value.(x.e)),value.(x.pg),value.(x.qg))
        w=FeasibilityWitness(state;label="global search operating point")
        ledger["point"]=_json_data(w)
        ledger["original_checks"]=validate_feasibility_witness(p,w)
        ledger["original_checks"]["valid"] && (witness=w)
    end
    feasibility_fingerprint(p)
    r=isnothing(witness) ? FeasibilityResult(p.fingerprint,:unresolved,nothing,nothing,[ledger],
        "global escalation has no independently verified original witness or infeasibility certificate") :
        FeasibilityResult(p.fingerprint,:feasible,witness,nothing,[ledger],"global search found an independently validated original operating point")
    (result=r,ledger=ledger)
end
