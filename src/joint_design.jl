"""Independent bounds for the existing M3 droop family; omitted fields stay fixed."""
struct DroopControl
    control_id::Int
    bounds::NamedTuple
    initial::Union{Nothing,DroopSettings{Float64}}
    function DroopControl(id::Integer;slope_bounds=nothing,v_ref_bounds=nothing,
        deadband_low_bounds=nothing,deadband_high_bounds=nothing,initial=nothing)
        id>0 || throw(ArgumentError("control ID must be positive"))
        bounds=(slope=slope_bounds,v_ref=v_ref_bounds,deadband_low=deadband_low_bounds,deadband_high=deadband_high_bounds)
        normalized=map(x->isnothing(x) ? nothing : Tuple(Float64.(x)),bounds)
        start=isnothing(initial) ? nothing : DroopSettings{Float64}(Float64(initial.slope),Float64(initial.v_ref),Float64(initial.deadband_low),Float64(initial.deadband_high))
        new(Int(id),normalized,start)
    end
end

struct JointDesignResult
    opf::ACOPFResult{Float64}
    taps::Dict{Int,Float64}
    susceptances::Dict{Int,Float64}
    droops::Dict{Int,DroopSettings{Float64}}
    tap_controls::Vector{TapControl}
    shunt_controls::Vector{ShuntControl}
    droop_controls::Vector{DroopControl}
    encoding::Symbol
    complementarity_residual_max::Union{Nothing,Float64}
end

JointDesignResult(opf, taps, susceptances, droops, tap_controls, shunt_controls,
    droop_controls) = JointDesignResult(opf, taps, susceptances, droops,
    tap_controls, shunt_controls, droop_controls, :smooth, nothing)

function _joint_droop_policy(case,c)
    1<=c.control_id<=length(case.controls) || throw(ArgumentError("unknown droop control"))
    any(a->a.control_id==c.control_id && any(g->g.id==a.generator_id && g.available,case.generators),case.attachments) || throw(ArgumentError("selected droop must have an available attached generator"))
    reference=DroopSettings(case.controls[c.control_id])
    names=keys(c.bounds)
    ranges=NamedTuple{names}(Tuple(_droop_parameter_bounds(getfield(c.bounds,k),getfield(reference,k),string(k);positive=k in (:slope,:v_ref)) for k in names))
    ranges.v_ref[1]-ranges.deadband_low[2]>0 || throw(ArgumentError("bounds permit a nonpositive lower deadband edge"))
    ranges.deadband_low[1]+ranges.deadband_high[1]>0 || throw(ArgumentError("bounds permit zero total deadband"))
    initial=isnothing(c.initial) ? reference : c.initial
    all(getfield(ranges,k)[1]<=getfield(initial,k)<=getfield(ranges,k)[2] for k in names) || throw(ArgumentError("droop initial settings must lie in bounds"))
    (ranges=ranges,initial=initial)
end

"""Optimize joint base-case controls; `control_normalization=:bounds` optionally uses
unit-interval affine coordinates for free settings. `droop_q_bounds=:implied`
omits generator-Q bounds already implied in exact arithmetic by the smoothed
droop saturation and nested control capability. `droop_q_formulation=:reduced`
substitutes that response into balance and objective expressions, eliminating
the controlled-generator Q variable and droop equality. These options preserve
the physical equations, objective and returned settings; their defaults preserve
the original formulation.
"""
function optimize_joint_design(case::Case;tap_controls=TapControl[],shunt_controls=ShuntControl[],
    droop_controls=DroopControl[],initial_state=nothing,smooth_epsilon=1e-5,control_normalization=:none,
    droop_q_bounds=:explicit,droop_q_formulation=:explicit,
    encoding=:smooth, optimizer_factory=Ipopt.Optimizer,silent=true,
    optimizer_attributes=Dict(),_measurement_hook=nothing)
    encoding in (:smooth, :complementarity) || throw(ArgumentError("encoding must be :smooth or :complementarity"))
    control_normalization in (:none,:bounds) || throw(ArgumentError("control_normalization must be :none or :bounds"))
    droop_q_bounds in (:explicit,:implied) || throw(ArgumentError("droop_q_bounds must be :explicit or :implied"))
    droop_q_formulation in (:explicit,:reduced) || throw(ArgumentError("droop_q_formulation must be :explicit or :reduced"))
    droop_q_formulation==:reduced && droop_q_bounds!=:explicit &&
        throw(ArgumentError("reduced droop Q has no separate Q bound; use droop_q_bounds=:explicit"))
    normalize_controls=control_normalization==:bounds
    validate_case(case);_check_tap_controls(case,tap_controls);_check_shunt_controls(case,shunt_controls)
    length(unique(c.control_id for c in droop_controls))==length(droop_controls) || throw(ArgumentError("duplicate droop controls"))
    isfinite(smooth_epsilon) && smooth_epsilon>0 || throw(ArgumentError("invalid smoothing"))
    if encoding == :complementarity
        droop_q_bounds == :explicit || throw(ArgumentError(
            "droop_q_bounds is a smooth-formulation option; use :explicit with exact joint design"))
        droop_q_formulation == :explicit || throw(ArgumentError(
            "droop_q_formulation is a smooth-formulation option; use :explicit with exact joint design"))
        optimizer_factory === Ipopt.Optimizer || throw(ArgumentError(
            "encoding=:complementarity uses CCOpt; omit optimizer_factory"))
    end
    model = encoding == :complementarity ? Model(CCOpt.Optimizer) : Model(optimizer_factory)
    encoding == :complementarity && MathOptComplements.Bridges.add_all_bridges(model)
    parameters=Dict{Int,NamedTuple}()
    for c in droop_controls
        p=_joint_droop_policy(case,c); names=keys(p.ranges)
        parameters[c.control_id]=NamedTuple{names}(Tuple(_droop_design_variable(model,"design_$(c.control_id)_$k",getfield(p.ranges,k),getfield(p.initial,k);normalize=normalize_controls) for k in names))
    end
    _,v = if encoding == :smooth
        _build_acopf_model(case;voltage_epsilon=smooth_epsilon,reactive_relative_epsilon=smooth_epsilon,
            reactive_epsilon=nothing,silent,optimizer_factory,initial_state,shared_model=model,
            tap_controls,shunt_controls,droop_parameter_variables=parameters,normalize_controls,
            droop_q_bounds,droop_q_formulation)
    else
        _build_complementarity_opf_model(case;silent,initial_state,shared_model=model,
            tap_controls,shunt_controls,normalize_controls,
            droop_parameter_variables=parameters)
    end
    for (k,x) in optimizer_attributes
        set_optimizer_attribute(model,k,x)
    end
    isnothing(_measurement_hook) || _measurement_hook(:built,model)
    optimize!(model)
    isnothing(_measurement_hook) || _measurement_hook(:solved,model)
    present=has_values(model)
    state=present ? ACState(value.(v.vm),value.(v.va),value.(v.pg),value.(v.qg)) : nothing
    epsilon = encoding == :smooth ? Float64(smooth_epsilon) : nothing
    opf=ACOPFResult{Float64}(state,present ? objective_value(model) : NaN,Symbol(string(termination_status(model))),Symbol(string(primal_status(model))),epsilon,epsilon,nothing)
    taps=present ? Dict(b.id=>Float64(haskey(v.taps,b.id) ? value(v.taps[b.id]) : b.tap_ratio) for b in case.network.branches) : Dict{Int,Float64}()
    shunts=present ? Dict{Int,Float64}(id=>value(x) for (id,x) in v.shunts) : Dict{Int,Float64}()
    droops=Dict{Int,DroopSettings{Float64}}()
    if present
        for (id,p) in parameters
            droops[id]=DroopSettings((_droop_design_value(getfield(p,k)) for k in keys(p))...)
        end
    end
    residual = present && encoding == :complementarity ? _complementarity_residual(v) : nothing
    result=JointDesignResult(opf,taps,shunts,droops,collect(tap_controls),collect(shunt_controls),collect(droop_controls),encoding,residual)
    isnothing(_measurement_hook) || _measurement_hook(:extracted,model)
    result
end
optimize_joint_design(::Study;kwargs...)=throw(ArgumentError("joint equipment SCOPF belongs to M9; supply a base Case"))

function _joint_droop_case(case,result)
    c=case
    for (id,settings) in result.droops
        c=with_droop_settings(Study(c),id,settings).case
    end
    c
end
"""Reconstruct all physical settings for independent joint-design replay."""
function with_joint_settings(case::Case,result::JointDesignResult)
    with_shunt_settings(with_tap_settings(_joint_droop_case(case,result),result.taps),result.susceptances)
end

function validate_joint_design(case::Case,result::JointDesignResult;setting_tolerance=1e-6,kwargs...)
    isfinite(setting_tolerance) && setting_tolerance>=0 || throw(ArgumentError("invalid setting tolerance"))
    length(unique(c.control_id for c in result.droop_controls))==length(result.droop_controls) || throw(ArgumentError("duplicate droop controls"))
    droop_policy=Set(keys(result.droops))==Set(c.control_id for c in result.droop_controls)
    for c in result.droop_controls
        p=_joint_droop_policy(case,c);s=get(result.droops,c.control_id,nothing)
        droop_policy &= !isnothing(s) && all(getfield(p.ranges,k)[1]-setting_tolerance<=getfield(s,k)<=getfield(p.ranges,k)[2]+setting_tolerance for k in keys(p.ranges))
    end
    # Reuse independent equipment policy checks; evaluate physics only after all families are reconstructed.
    empty_opf=ACOPFResult{Float64}(nothing,result.opf.objective,result.opf.termination_status,result.opf.primal_status,result.opf.smooth_epsilon,result.opf.smooth_reactive_relative_epsilon,result.opf.smooth_reactive_epsilon)
    tap=validate_tap_design(case,TapOPFResult(empty_opf,result.taps,result.tap_controls);tap_tolerance=setting_tolerance)
    shunt=validate_shunt_design(case,ShuntOPFResult(empty_opf,result.susceptances,result.shunt_controls);setting_tolerance)
    policy=droop_policy && tap.policy_valid && shunt.policy_valid
    physical=nothing
    reconstructable=all(isfinite(x) && x>0 for x in values(result.taps)) && all(isfinite(x) && x/only(_simple_bank(case,id).step_susceptances)>=0 for (id,x) in result.susceptances)
    if policy && reconstructable && !isnothing(result.opf.state)
        physical=validate_equilibrium(with_joint_settings(case,result),result.opf;kwargs...)
    end
    solver=result.opf.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
    (valid=solver && policy && !isnothing(physical) && physical.valid,solver_valid=solver,
        policy_valid=policy,droop_policy_valid=droop_policy,tap_policy_valid=tap.policy_valid,
        shunt_policy_valid=shunt.policy_valid,physical=physical,continuous_relaxation=true)
end

"""Independently audit each controlled generator against its exact physical droop curve.

For a complementarity result this is an extraction check, not a second solve:
it compares returned ``qg`` values with direct evaluation of the exact PWL curve
after applying any optimized tap, shunt, and droop settings.
"""
function exact_droop_audit(case::Case,result::JointDesignResult;droop_tolerance=1e-5)
    isfinite(droop_tolerance) && droop_tolerance>=0 || throw(ArgumentError("invalid droop tolerance"))
    state=result.opf.state
    isnothing(state) && return Dict{String,Any}(
        "tolerance_pu"=>Float64(droop_tolerance),"max_residual_pu"=>nothing,
        "max_ratio_to_tolerance"=>nothing,"worst"=>nothing,"controllers"=>Any[])
    physical=with_joint_settings(case,result)
    bus_indices=_bus_indices(physical.network)
    generator_indices=Dict(g.id=>i for (i,g) in enumerate(physical.generators))
    rows=Dict{String,Any}[]
    for attachment in physical.attachments
        generator_index=generator_indices[attachment.generator_id]
        physical.generators[generator_index].available || continue
        bus_index=bus_indices[attachment.location.bus_id]
        control=physical.controls[attachment.control_id]
        expected=clamp(evaluate(droop_curve(control),state.vm[bus_index]),
            control.capability.q_min,control.capability.q_max)
        signed=state.qg[generator_index]-expected
        residual=abs(signed)
        ratio=droop_tolerance==0 ? (residual==0 ? 0.0 : Inf) : residual/droop_tolerance
        push!(rows,Dict{String,Any}(
            "generator_id"=>attachment.generator_id,"control_id"=>attachment.control_id,
            "regulated_bus_id"=>attachment.location.bus_id,"voltage_pu"=>state.vm[bus_index],
            "reactive_power_pu"=>state.qg[generator_index],"exact_reactive_power_pu"=>expected,
            "signed_residual_pu"=>signed,"residual_pu"=>residual,
            "ratio_to_tolerance"=>ratio,"within_tolerance"=>residual<=droop_tolerance))
    end
    sort!(rows;by=row->-row["residual_pu"])
    worst=isempty(rows) ? nothing : first(rows)
    Dict{String,Any}(
        "tolerance_pu"=>Float64(droop_tolerance),
        "max_residual_pu"=>isnothing(worst) ? 0.0 : worst["residual_pu"],
        "max_ratio_to_tolerance"=>isnothing(worst) ? 0.0 : worst["ratio_to_tolerance"],
        "worst"=>worst,"controllers"=>rows)
end

function joint_design_metrics(case::Case,result::JointDesignResult)
    s=result.opf.state;isnothing(s) && throw(ArgumentError("metrics require a state"))
    physical=with_joint_settings(case,result);f=branch_flows(physical.network,s)
    active=sum((s.pg[i]-g.initial_p)^2 for (i,g) in enumerate(case.generators))
    reactive=1e-3*sum((s.qg[i]-g.initial_q)^2 for (i,g) in enumerate(case.generators))
    (active_dispatch_component=active,reactive_dispatch_component=reactive,design_penalty=0.,
        objective_recomputed=active+reactive,branch_active_loss=real(sum(f.from)+sum(f.to)),
        shunt_active_consumption=real(sum(shunt_powers(physical.network,s))+sum(bank_powers(physical.network,s))),
        taps=tap_design_metrics(case,TapOPFResult(result.opf,result.taps,result.tap_controls)).settings,
        shunts=shunt_design_metrics(case,ShuntOPFResult(result.opf,result.susceptances,result.shunt_controls)).settings,
        droops=[(control_id=id,supplied=DroopSettings(case.controls[id]),solved=x) for (id,x) in sort(collect(result.droops);by=first)])
end

function write_joint_design(path,r::JointDesignResult)
    fields(cs,T)=[Dict(string(k)=>_json_data(getfield(c,k)) for k in fieldnames(T)) for c in cs]
    d=Dict("schema_version"=>1,"kind"=>"DroopOPF.JointDesignResult","continuous_relaxation"=>true,
        "encoding"=>String(r.encoding),"complementarity_residual_max"=>r.complementarity_residual_max,
        "opf"=>_json_data(r.opf),"taps"=>_json_data(r.taps),"susceptances"=>_json_data(r.susceptances),"droops"=>_json_data(r.droops),
        "tap_controls"=>fields(r.tap_controls,TapControl),"shunt_controls"=>fields(r.shunt_controls,ShuntControl),"droop_controls"=>fields(r.droop_controls,DroopControl))
    write(path,JSON.json(d;pretty=true)*"\n");path
end
function read_joint_design(path)
    d=JSON.parsefile(path)
    d["schema_version"]==1 && d["kind"]=="DroopOPF.JointDesignResult" && d["continuous_relaxation"]===true || throw(ArgumentError("unsupported joint result"))
    o=d["opf"];s=o["state"]
    state=isnothing(s) ? nothing : ACState(Float64.(s["vm"]),Float64.(s["va"]),Float64.(s["pg"]),Float64.(s["qg"]))
    opf=ACOPFResult{Float64}(state,isnothing(o["objective"]) ? NaN : o["objective"],Symbol(o["termination_status"]),Symbol(o["primal_status"]),o["smooth_epsilon"],o["smooth_reactive_relative_epsilon"],o["smooth_reactive_epsilon"])
    taps=TapControl[TapControl(c["branch_id"];lower=c["lower"],upper=c["upper"],initial=c["initial"],nominal=c["nominal"]) for c in d["tap_controls"]]
    shunts=ShuntControl[ShuntControl(c["bank_id"];lower=c["lower"],upper=c["upper"],initial=c["initial"],nominal=c["nominal"]) for c in d["shunt_controls"]]
    droops=DroopControl[DroopControl(c["control_id"];slope_bounds=c["bounds"]["slope"],v_ref_bounds=c["bounds"]["v_ref"],deadband_low_bounds=c["bounds"]["deadband_low"],deadband_high_bounds=c["bounds"]["deadband_high"],initial=isnothing(c["initial"]) ? nothing : _droop_settings_from_data(c["initial"])) for c in d["droop_controls"]]
    JointDesignResult(opf,Dict{Int,Float64}(parse(Int,k)=>v for (k,v) in d["taps"]),Dict{Int,Float64}(parse(Int,k)=>v for (k,v) in d["susceptances"]),Dict{Int,DroopSettings{Float64}}(parse(Int,k)=>_droop_settings_from_data(v) for (k,v) in d["droops"]),taps,shunts,droops,
        Symbol(get(d,"encoding","smooth")),get(d,"complementarity_residual_max",nothing))
end
