"""Select a simple bank for continuous B optimization (pu); omitted bounds use its legal-count envelope."""
struct ShuntControl
    bank_id::Int
    lower::Union{Nothing,Float64}
    upper::Union{Nothing,Float64}
    initial::Union{Nothing,Float64}
    nominal::Union{Nothing,Float64}
    function ShuntControl(id::Integer;lower=nothing,upper=nothing,initial=nothing,nominal=nothing)
        id>0 || throw(ArgumentError("bank ID must be positive"))
        all(x->isnothing(x) || (x isa Real && isfinite(x)),(lower,upper,initial,nominal)) || throw(ArgumentError("shunt settings must be finite"))
        isnothing(lower) || isnothing(upper) || lower<=upper || throw(ArgumentError("reversed shunt bounds"))
        new(Int(id),map(x->isnothing(x) ? nothing : Float64(x),(lower,upper,initial,nominal))...)
    end
end

struct ShuntOPFResult
    opf::ACOPFResult{Float64}
    susceptances::Dict{Int,Float64}
    controls::Vector{ShuntControl}
    encoding::Symbol
    complementarity_residual_max::Union{Nothing,Float64}
end

ShuntOPFResult(opf,susceptances,controls)=ShuntOPFResult(opf,susceptances,controls,:smooth,nothing)

function _simple_bank(case,id)
    isnothing(case.network) && throw(ArgumentError("shunt optimization requires a network"))
    i=findfirst(b->b.id==id,case.network.banks)
    isnothing(i) && throw(ArgumentError("unknown bank ID; fixed shunts are not adjustable banks"))
    bank=case.network.banks[i]
    length(bank.step_susceptances)==1 && !iszero(only(bank.step_susceptances)) || throw(ArgumentError("M7.2 supports one nonzero capacitor/reactor step type only"))
    bank
end

function _shunt_policy(case,c)
    b=_simple_bank(case,c.bank_id)
    b.available || throw(ArgumentError("unavailable bank cannot be optimized"))
    step=only(b.step_susceptances)
    lo,hi=extrema(only(s)*step for s in b.legal_states)
    lower=isnothing(c.lower) ? lo : c.lower; upper=isnothing(c.upper) ? hi : c.upper
    lo<=lower<=upper<=hi || throw(ArgumentError("bounds must lie in the legal-count envelope"))
    supplied=only(b.state)*step
    initial=isnothing(c.initial) ? supplied : c.initial
    lower<=initial<=upper || throw(ArgumentError("initial B must lie within bounds; provide an explicit start"))
    nominal=isnothing(c.nominal) ? only(b.nominal_state)*step : c.nominal
    lo<=nominal<=hi || throw(ArgumentError("nominal B must lie in the physical envelope"))
    (bank=b,lower=lower,upper=upper,initial=initial,nominal=nominal,supplied=supplied)
end

function _check_shunt_controls(case,controls)
    length(unique(c.bank_id for c in controls))==length(controls) || throw(ArgumentError("duplicate shunt controls"))
    foreach(c->_shunt_policy(case,c),controls)
end

"""Physical replay of relaxed banks as equivalent fixed admittances; original bank metadata remain in the input case."""
function with_shunt_settings(case::Case,susceptances::AbstractDict)
    net=case.network
    isnothing(net) && throw(ArgumentError("shunt settings require a network"))
    shunts=FixedShunt[s for s in net.shunts]
    for (id,B) in susceptances
        bank=_simple_bank(case,id)
        isfinite(B) || throw(ArgumentError("nonfinite susceptance"))
        count=B/only(bank.step_susceptances)
        count>=0 || throw(ArgumentError("susceptance has wrong capacitor/reactor sign"))
        G=count*only(bank.step_conductances)
        push!(shunts,FixedShunt(id,bank.bus_id;conductance=G,susceptance=B,available=bank.available))
    end
    banks=ShuntBank[b for b in net.banks if !haskey(susceptances,b.id)]
    Case(case.id;base_power=case.base_power,base_frequency=case.base_frequency,
        network=ACNetwork(net.buses,net.branches;shunts,banks),loads=case.loads,
        generators=case.generators,controls=case.controls,attachments=case.attachments)
end

# Remove selected supplied admittances before inserting variable G(B), B.
function _shunt_variables!(model,case,controls,Y;normalize_controls=false)
    vars=Dict{Int,Union{VariableRef,AffExpr}}(); indices=_bus_indices(case.network)
    for c in controls
        p=_shunt_policy(case,c); bank=p.bank; i=indices[bank.bus_id]
        if normalize_controls && p.lower<p.upper
            x=_normalized_control_variable(model,"shunt_B_$(c.bank_id)",p.lower,p.upper,p.initial)
        else
            x=@variable(model,base_name="shunt_B_$(c.bank_id)")
            p.lower==p.upper ? fix(x,p.lower;force=true) : _set_bound!(x,p.lower,p.upper)
            set_start_value(x,p.initial)
        end
        vars[c.bank_id]=x
        isnothing(Y) || (Y[i,i]-=bank_admittance(bank))
    end
    vars
end

"""Optimize simple capacitor/reactor banks in base-case OPF; taps and droops stay fixed."""
function optimize_shunts(case::Case,controls::AbstractVector{ShuntControl};smooth_epsilon=1e-5,
    encoding=:smooth,initial_state=nothing,optimizer_factory=Ipopt.Optimizer,
    silent=true,optimizer_attributes=Dict())
    validate_case(case); _check_shunt_controls(case,controls)
    encoding in (:smooth,:complementarity) || throw(ArgumentError("encoding must be :smooth or :complementarity"))
    isfinite(smooth_epsilon) && smooth_epsilon>0 || throw(ArgumentError("invalid smoothing epsilon"))
    encoding==:complementarity && optimizer_factory !== Ipopt.Optimizer &&
        throw(ArgumentError("encoding=:complementarity uses CCOpt; omit optimizer_factory"))
    model,v = if encoding==:smooth
        _build_acopf_model(case;voltage_epsilon=smooth_epsilon,reactive_relative_epsilon=smooth_epsilon,
            reactive_epsilon=nothing,silent,optimizer_factory,initial_state,shunt_controls=controls)
    else
        _build_complementarity_opf_model(case;silent,initial_state,shunt_controls=controls)
    end
    for (k,x) in optimizer_attributes
        set_optimizer_attribute(model,k,x)
    end
    optimize!(model); present=has_values(model)
    state=present ? ACState(value.(v.vm),value.(v.va),value.(v.pg),value.(v.qg)) : nothing
    epsilon=encoding==:smooth ? Float64(smooth_epsilon) : nothing
    opf=ACOPFResult{Float64}(state,present ? objective_value(model) : NaN,
        Symbol(string(termination_status(model))),Symbol(string(primal_status(model))),epsilon,epsilon,nothing)
    settings=present ? Dict(id=>Float64(value(x)) for (id,x) in v.shunts) : Dict{Int,Float64}()
    residual=present && encoding==:complementarity ? _complementarity_residual(v) : nothing
    ShuntOPFResult(opf,settings,collect(controls),encoding,residual)
end
optimize_shunts(::Study,args...;kwargs...)=throw(ArgumentError("optimized equipment SCOPF is reserved for M9; supply a base Case"))

function validate_shunt_design(case::Case,result::ShuntOPFResult;setting_tolerance=1e-6,kwargs...)
    isfinite(setting_tolerance) && setting_tolerance>=0 || throw(ArgumentError("invalid setting tolerance"))
    _check_shunt_controls(case,result.controls)
    complete=Set(keys(result.susceptances))==Set(c.bank_id for c in result.controls)
    policy=complete
    for c in result.controls
        p=_shunt_policy(case,c); x=get(result.susceptances,c.bank_id,NaN)
        policy &= isfinite(x) && p.lower-setting_tolerance<=x<=p.upper+setting_tolerance
    end
    physical=nothing
    reconstructable=complete && all(isfinite,values(result.susceptances)) &&
        all(B/only(_simple_bank(case,id).step_susceptances)>=0 for (id,B) in result.susceptances)
    if reconstructable && !isnothing(result.opf.state)
        physical=validate_equilibrium(with_shunt_settings(case,result.susceptances),result.opf;kwargs...)
    end
    solver=result.opf.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
    (valid=solver && policy && !isnothing(physical) && physical.valid,solver_valid=solver,
        policy_valid=policy,physical=physical,continuous_relaxation=true)
end

function shunt_design_metrics(case::Case,result::ShuntOPFResult)
    isnothing(result.opf.state) && throw(ArgumentError("metrics require a solved state"))
    physical=with_shunt_settings(case,result.susceptances); s=result.opf.state
    f=branch_flows(physical.network,s); indices=_bus_indices(case.network)
    settings=[begin
        p=_shunt_policy(case,c); b=p.bank; B=result.susceptances[c.bank_id]
        count=B/only(b.step_susceptances); G=count*only(b.step_conductances)
        v=s.vm[indices[b.bus_id]]
        (bank_id=b.id,supplied=p.supplied,nominal=p.nominal,solved=B,conductance=G,
            fractional_count=count,lower=p.lower,upper=p.upper,
            deviation_from_supplied=B-p.supplied,deviation_from_nominal=B-p.nominal,
            active_consumption=G*v^2,reactive_injection=B*v^2)
    end for c in result.controls]
    (settings=settings,branch_active_loss=real(sum(f.from)+sum(f.to)),
        shunt_active_consumption=real(sum(shunt_powers(physical.network,s))+sum(bank_powers(physical.network,s))))
end

function write_shunt_design(path,result::ShuntOPFResult)
    d=Dict("schema_version"=>1,"kind"=>"DroopOPF.ShuntOPFResult","continuous_relaxation"=>true,
        "encoding"=>String(result.encoding),"complementarity_residual_max"=>result.complementarity_residual_max,
        "opf"=>_json_data(result.opf),"susceptances"=>_json_data(result.susceptances),
        "controls"=>[Dict(string(k)=>getfield(c,k) for k in fieldnames(ShuntControl)) for c in result.controls])
    write(path,JSON.json(d;pretty=true)*"\n"); path
end
function read_shunt_design(path)
    d=JSON.parsefile(path)
    d["schema_version"]==1 && d["kind"]=="DroopOPF.ShuntOPFResult" && d["continuous_relaxation"]===true || throw(ArgumentError("unsupported shunt result"))
    o=d["opf"]; s=o["state"]
    state=isnothing(s) ? nothing : ACState(Float64.(s["vm"]),Float64.(s["va"]),Float64.(s["pg"]),Float64.(s["qg"]))
    opf=ACOPFResult{Float64}(state,isnothing(o["objective"]) ? NaN : o["objective"],Symbol(o["termination_status"]),Symbol(o["primal_status"]),o["smooth_epsilon"],o["smooth_reactive_relative_epsilon"],o["smooth_reactive_epsilon"])
    controls=ShuntControl[ShuntControl(c["bank_id"];lower=c["lower"],upper=c["upper"],initial=c["initial"],nominal=c["nominal"]) for c in d["controls"]]
    ShuntOPFResult(opf,Dict{Int,Float64}(parse(Int,k)=>Float64(v) for (k,v) in d["susceptances"]),controls,
        Symbol(get(d,"encoding","smooth")),get(d,"complementarity_residual_max",nothing))
end
