"""Explicit continuous tap policy. Omitted branches remain fixed at supplied ratios."""
struct TapControl
    branch_id::Int
    lower::Float64
    upper::Float64
    initial::Union{Nothing,Float64}
    nominal::Union{Nothing,Float64}
    function TapControl(id::Integer; lower::Real, upper::Real, initial=nothing, nominal=nothing)
        id > 0 || throw(ArgumentError("branch ID must be positive"))
        isfinite(lower) && isfinite(upper) && 0 < lower <= upper || throw(ArgumentError("tap bounds must be finite, positive and ordered"))
        isnothing(initial) || (isfinite(initial) && lower <= initial <= upper) || throw(ArgumentError("initial tap must lie within bounds"))
        isnothing(nominal) || (isfinite(nominal) && nominal > 0) || throw(ArgumentError("nominal tap must be finite and positive"))
        new(Int(id),Float64(lower),Float64(upper),isnothing(initial) ? nothing : Float64(initial),isnothing(nominal) ? nothing : Float64(nominal))
    end
end

struct TapOPFResult
    opf::ACOPFResult{Float64}
    taps::Dict{Int,Float64}
    controls::Vector{TapControl}
    encoding::Symbol
    complementarity_residual_max::Union{Nothing,Float64}
end

TapOPFResult(opf,taps,controls)=TapOPFResult(opf,taps,controls,:smooth,nothing)

function _check_tap_controls(case,controls)
    isnothing(case.network) && throw(ArgumentError("tap optimization requires a network"))
    length(unique(c.branch_id for c in controls)) == length(controls) || throw(ArgumentError("duplicate tap controls"))
    for c in controls
        i=findfirst(b->b.id==c.branch_id,case.network.branches)
        isnothing(i) && throw(ArgumentError("unknown controlled branch"))
        b=case.network.branches[i]
        b.available || throw(ArgumentError("unavailable branch cannot have an optimized tap"))
        start=isnothing(c.initial) ? b.tap_ratio : c.initial
        c.lower <= start <= c.upper || throw(ArgumentError("supplied tap lies outside bounds; provide an explicit initial tap"))
    end
end

"""Reconstruct physical data at explicitly supplied ratios without changing the input."""
function with_tap_settings(case::Case,taps::AbstractDict)
    net=case.network
    isnothing(net) && throw(ArgumentError("tap settings require a network"))
    all(id->any(b->b.id==id,net.branches),keys(taps)) || throw(ArgumentError("unknown tap branch ID"))
    branches=[Branch(b.id,b.from_bus,b.to_bus;resistance=b.resistance,reactance=b.reactance,
        charging=b.charging,thermal_limit=b.thermal_limit,available=b.available,
        phase_shift=b.phase_shift,tap_ratio=get(taps,b.id,b.tap_ratio)) for b in net.branches]
    Case(case.id;base_power=case.base_power,base_frequency=case.base_frequency,
        network=ACNetwork(net.buses,branches;shunts=net.shunts,banks=net.banks),
        generators=case.generators,loads=case.loads,controls=case.controls,attachments=case.attachments)
end

# Terminal powers depend on tau inside the NLP; phase shift stays fixed.
function _add_tap_network!(model,case,vm,va,pg,qg,generators_at_bus,load_p,load_q,controls,shunt_controls=nothing;normalize_controls=false)
    net=case.network; indices=_bus_indices(net); n=length(net.buses)
    taps=Dict{Int,Union{VariableRef,AffExpr}}()
    for c in controls
        b=only(filter(b->b.id==c.branch_id,net.branches))
        initial=isnothing(c.initial) ? b.tap_ratio : c.initial
        if normalize_controls && c.lower<c.upper
            x=_normalized_control_variable(model,"tap_$(c.branch_id)",c.lower,c.upper,initial)
        else
            x=@variable(model,base_name="tap_$(c.branch_id)")
            c.lower==c.upper ? fix(x,c.lower;force=true) : _set_bound!(x,c.lower,c.upper)
            set_start_value(x,initial)
        end
        taps[c.branch_id]=x
    end
    ps=[Any[] for _ in 1:n]; qs=[Any[] for _ in 1:n]
    for b in net.branches
        b.available || continue
        f,t=indices[b.from_bus],indices[b.to_bus]
        tau=get(taps,b.id,b.tap_ratio)
        yff,yft,ytf,ytt=_branch_admittances(b)
        # Remove the supplied ratio from coefficients, retaining its phase.
        for (i,j,self,mutual,from) in ((f,t,yff*b.tap_ratio^2,yft*b.tap_ratio,true),(t,f,ytt,ytf*b.tap_ratio,false))
            gs,bs,gm,bm=real(self),imag(self),real(mutual),imag(mutual)
            scale=from ? @NLexpression(model,1/tau^2) : 1.0
            p=@NLexpression(model,vm[i]^2*gs*scale+vm[i]*vm[j]/tau*(gm*cos(va[i]-va[j])+bm*sin(va[i]-va[j])))
            q=@NLexpression(model,-vm[i]^2*bs*scale+vm[i]*vm[j]/tau*(gm*sin(va[i]-va[j])-bm*cos(va[i]-va[j])))
            push!(ps[i],p); push!(qs[i],q)
            @NLconstraint(model,p^2+q^2 <= b.thermal_limit^2)
        end
    end
    shunt_vars=isnothing(shunt_controls) ? Dict{Int,VariableRef}() : _shunt_variables!(model,case,shunt_controls,nothing;normalize_controls)
    shunt=zeros(ComplexF64,n)
    for s in net.shunts
        s.available && (shunt[indices[s.bus_id]]+=complex(s.conductance,s.susceptance))
    end
    for b in net.banks
        haskey(shunt_vars,b.id) || (shunt[indices[b.bus_id]]+=bank_admittance(b))
    end
    for i in 1:n
        pgen=sum(pg[k] for k in generators_at_bus[i];init=0.)
        qgen=sum(qg[k] for k in generators_at_bus[i];init=0.)
        pp,qq=ps[i],qs[i]; g,b=real(shunt[i]),imag(shunt[i])
        selected=[bank for bank in net.banks if haskey(shunt_vars,bank.id) && indices[bank.bus_id]==i]
        gv=sum(only(bank.step_conductances)/only(bank.step_susceptances)*shunt_vars[bank.id] for bank in selected;init=0.)
        bv=sum(shunt_vars[bank.id] for bank in selected;init=0.)
        @NLconstraint(model,pgen-load_p[i] == sum(pp[k] for k in eachindex(pp))+(g+gv)*vm[i]^2)
        @NLconstraint(model,qgen-load_q[i] == sum(qq[k] for k in eachindex(qq))-(b+bv)*vm[i]^2)
    end
    taps,shunt_vars
end

"""Base-case AC OPF with explicitly selected continuous tap ratios."""
function optimize_taps(case::Case,controls::AbstractVector{TapControl};smooth_epsilon=1e-5,
    encoding=:smooth,initial_state=nothing,optimizer_factory=Ipopt.Optimizer,
    silent=true,optimizer_attributes=Dict())
    validate_case(case); _check_tap_controls(case,controls)
    encoding in (:smooth,:complementarity) || throw(ArgumentError("encoding must be :smooth or :complementarity"))
    isfinite(smooth_epsilon) && smooth_epsilon>0 || throw(ArgumentError("invalid smoothing epsilon"))
    encoding==:complementarity && optimizer_factory !== Ipopt.Optimizer &&
        throw(ArgumentError("encoding=:complementarity uses CCOpt; omit optimizer_factory"))
    model,v = if encoding==:smooth
        _build_acopf_model(case;voltage_epsilon=smooth_epsilon,reactive_relative_epsilon=smooth_epsilon,
            reactive_epsilon=nothing,silent,optimizer_factory,initial_state,tap_controls=controls)
    else
        _build_complementarity_opf_model(case;silent,initial_state,tap_controls=controls)
    end
    for (k,x) in optimizer_attributes
        set_optimizer_attribute(model,k,x)
    end
    optimize!(model)
    present=has_values(model)
    state=present ? ACState(value.(v.vm),value.(v.va),value.(v.pg),value.(v.qg)) : nothing
    epsilon=encoding==:smooth ? Float64(smooth_epsilon) : nothing
    opf=ACOPFResult{Float64}(state,present ? objective_value(model) : NaN,
        Symbol(string(termination_status(model))),Symbol(string(primal_status(model))),epsilon,epsilon,nothing)
    taps=present ? Dict(b.id=>Float64(haskey(v.taps,b.id) ? value(v.taps[b.id]) : b.tap_ratio) for b in case.network.branches) : Dict{Int,Float64}()
    residual=present && encoding==:complementarity ? _complementarity_residual(v) : nothing
    TapOPFResult(opf,taps,collect(controls),encoding,residual)
end
optimize_taps(::Study,args...;kwargs...)=throw(ArgumentError("optimized equipment SCOPF is reserved for M9; supply a base Case"))

"""Separately report numerical termination, physical validity and tap-policy compliance."""
function validate_tap_design(case::Case,result::TapOPFResult;tap_tolerance=1e-6,kwargs...)
    isfinite(tap_tolerance) && tap_tolerance>=0 || throw(ArgumentError("invalid tap tolerance"))
    _check_tap_controls(case,result.controls)
    policy=Set(keys(result.taps))==Set(b.id for b in case.network.branches)
    selected=Dict(c.branch_id=>c for c in result.controls)
    for b in case.network.branches
        x=get(result.taps,b.id,NaN); c=get(selected,b.id,nothing)
        policy &= isfinite(x) && x>0 && (isnothing(c) ? abs(x-b.tap_ratio)<=tap_tolerance : c.lower-tap_tolerance<=x<=c.upper+tap_tolerance)
    end
    physical=nothing
    reconstructable=Set(keys(result.taps))==Set(b.id for b in case.network.branches) && all(x->isfinite(x) && x>0,values(result.taps))
    if reconstructable && !isnothing(result.opf.state)
        physical=validate_equilibrium(with_tap_settings(case,result.taps),result.opf;kwargs...)
    end
    solver=result.opf.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
    (valid=solver && policy && !isnothing(physical) && physical.valid,solver_valid=solver,
        policy_valid=policy,physical=physical,continuous_relaxation=true)
end

function write_tap_design(path,result::TapOPFResult)
    data=Dict("schema_version"=>1,"kind"=>"DroopOPF.TapOPFResult","continuous_relaxation"=>true,
        "encoding"=>String(result.encoding),"complementarity_residual_max"=>result.complementarity_residual_max,
        "opf"=>_json_data(result.opf),"taps"=>_json_data(result.taps),
        "controls"=>[Dict(string(k)=>getfield(c,k) for k in fieldnames(TapControl)) for c in result.controls])
    write(path,JSON.json(data;pretty=true)*"\n"); path
end
function read_tap_design(path)
    d=JSON.parsefile(path)
    d["schema_version"]==1 && d["kind"]=="DroopOPF.TapOPFResult" && d["continuous_relaxation"]===true || throw(ArgumentError("unsupported tap result"))
    o=d["opf"]; s=o["state"]
    state=isnothing(s) ? nothing : ACState(Float64.(s["vm"]),Float64.(s["va"]),Float64.(s["pg"]),Float64.(s["qg"]))
    opf=ACOPFResult{Float64}(state,isnothing(o["objective"]) ? NaN : o["objective"],Symbol(o["termination_status"]),Symbol(o["primal_status"]),o["smooth_epsilon"],o["smooth_reactive_relative_epsilon"],o["smooth_reactive_epsilon"])
    controls=[TapControl(c["branch_id"];lower=c["lower"],upper=c["upper"],initial=c["initial"],nominal=c["nominal"]) for c in d["controls"]]
    TapOPFResult(opf,Dict(parse(Int,k)=>Float64(v) for (k,v) in d["taps"]),controls,
        Symbol(get(d,"encoding","smooth")),get(d,"complementarity_residual_max",nothing))
end

"""Raw physical and setting metrics; none implicitly adds an objective term."""
function tap_design_metrics(case::Case,result::TapOPFResult)
    isnothing(result.opf.state) && throw(ArgumentError("tap metrics require a solved state"))
    physical=with_tap_settings(case,result.taps)
    flows=branch_flows(physical.network,result.opf.state)
    controls=Dict(c.branch_id=>c for c in result.controls)
    settings=[begin
        c=get(controls,b.id,nothing)
        nominal=isnothing(c) || isnothing(c.nominal) ? b.tap_ratio : c.nominal
        (branch_id=b.id,supplied=b.tap_ratio,nominal=nominal,solved=result.taps[b.id],
            deviation_from_supplied=result.taps[b.id]-b.tap_ratio,
            deviation_from_nominal=result.taps[b.id]-nominal,
            optimized=!isnothing(c),lower=isnothing(c) ? b.tap_ratio : c.lower,
            upper=isnothing(c) ? b.tap_ratio : c.upper)
    end for b in case.network.branches]
    (settings=settings,branch_active_loss=real(sum(flows.from)+sum(flows.to)),
        shunt_active_consumption=real(sum(shunt_powers(physical.network,result.opf.state))+sum(bank_powers(physical.network,result.opf.state))))
end
