include("s1_diagnostics.jl")
using MadNLP, SHA
include("s1_failure_details.jl")

struct S1MadRecorder <: MadNLP.AbstractUserCallback
    trace::Vector
    deadline_ns::Union{Nothing,UInt64}
end
S1MadRecorder(trace::Vector)=S1MadRecorder(trace,nothing)
function (cb::S1MadRecorder)(solver::MadNLP.AbstractMadNLPSolver, mode)
    push!(cb.trace,Dict("iteration"=>solver.cnt.k,"mode"=>string(mode),
        "native_primal"=>MadNLP.get_inf_pr(solver),"native_dual"=>MadNLP.get_inf_du(solver),
        "native_complementarity"=>MadNLP.get_inf_compl(solver),"mu"=>MadNLP.get_mu(solver)))
    isnothing(cb.deadline_ns) || time_ns()<cb.deadline_ns
end

"""Persist each attempt, including failures; solver-native KKT scales are labelled."""
function s1_attempt(out,name,case,start;policies=NamedTuple(),solver=:ipopt,epsilon=1e-6,
    options=Dict{String,Any}(),tags=Dict{String,Any}(),experiment_hook=nothing,deadline_ns=nothing,
    control_normalization=:none,droop_q_bounds=:explicit,droop_q_formulation=:explicit)
    solver in (:ipopt,:madnlp) || error("unknown solver")
    mkpath(out);trace=[];bounds=[];metadata=Dict{String,Any}();phases=Dict{Symbol,UInt64}()
    settings=solver==:ipopt ?
        Dict{String,Any}("tol"=>1e-8,"max_iter"=>1000,"max_cpu_time"=>60.,"bound_relax_factor"=>0.,"mu_strategy"=>"adaptive") :
        Dict{String,Any}("tol"=>1e-8,"max_iter"=>1000,"max_wall_time"=>60.,"bound_relax_factor"=>0.)
    merge!(settings,options)
    row=Dict{String,Any}("name"=>name,"solver"=>string(solver),"options"=>settings,
        "epsilon"=>epsilon,"control_normalization"=>string(control_normalization),
        "droop_q_bounds"=>string(droop_q_bounds),
        "droop_q_formulation"=>string(droop_q_formulation),
        "tags"=>tags,"buses"=>length(case.network.buses),"valid"=>false,
        "residual_convention"=>solver==:ipopt ? "Ipopt callback and explicitly labelled native unscaled residuals" : "MadNLP native solver-scaled residuals; not directly comparable to Ipopt unscaled values",
        "free_counts"=>Dict("tap"=>length(get(policies,:tap_controls,[])),
            "shunt"=>length(get(policies,:shunt_controls,[])),"droop"=>length(get(policies,:droop_controls,[]))))
    recorder=s1_recorder(trace,bounds,metadata;deadline_ns)
    function hook(phase,model)
        phases[phase]=time_ns()
        if phase==:built
            metadata["control_coordinate_maps"]=[Dict("physical_name"=>a.name,"coordinate"=>JuMP.name(a.coordinate),
                "lower"=>a.lower,"width"=>a.width,"coordinate_start"=>start_value(a.coordinate))
                for a in get(model.ext,:control_normalization_maps,[])]
            metadata["droop_q_formulation"]=string(get(model.ext,:droop_q_formulation,:explicit))
            metadata["reduced_droop_q_generator_ids"]=get(model.ext,:reduced_droop_q_generator_ids,Int[])
        end
        if solver==:ipopt
            recorder(phase,model)
        elseif phase==:built
            metadata["variables"]=num_variables(model)
            metadata["constraints"]=num_constraints(model;count_variable_in_set_constraints=true)
            metadata["nonlinear_derivative_features"]=string.(JuMP.MOI.features_available(JuMP.NLPEvaluator(model)))
            set_optimizer_attribute(model,"intermediate_callback",S1MadRecorder(trace,deadline_ns))
        elseif phase==:solved
            recorder(phase,model)
            backend=JuMP.unsafe_backend(model)
            if !isnothing(backend.result)
                r=backend.result
                metadata["final_native"]=Dict("iterations"=>r.iter,"primal"=>r.primal_feas,
                    "dual"=>r.dual_feas,"complementarity"=>MadNLP.get_inf_compl(backend.solver))
            end
        end
        isnothing(experiment_hook) || experiment_hook(phase,model)
    end
    result=nothing
    write(joinpath(out,name*"-start.json"),JSON.json(Dict("state"=>DroopOPF._json_data(start),
        "policies"=>Dict(string(k)=>[Dict(string(f)=>DroopOPF._json_data(getfield(p,f)) for f in fieldnames(typeof(p))) for p in v] for (k,v) in pairs(policies)));pretty=true))
    try
        t0=time_ns()
        measured=@timed optimize_joint_design(case;initial_state=start,smooth_epsilon=epsilon,policies...,
            optimizer_factory=solver==:ipopt ? Ipopt.Optimizer : MadNLP.Optimizer,
            optimizer_attributes=settings,_measurement_hook=hook,control_normalization,
            droop_q_bounds,droop_q_formulation)
        result=measured.value
        write_joint_design(joinpath(out,name*"-design.json"),result)
        checked=@timed validate_joint_design(case,result)
        check=checked.value
        row["physical_check_status"]=isnothing(check.physical) ? "not_evaluated" : "evaluated"
        row["physical_failures"]=isnothing(check.physical) ? nothing :
            s1_failure_details(with_joint_settings(case,result),result.opf.state)
        merge!(row,Dict("status"=>string(result.opf.termination_status),"valid"=>check.valid,
            "physical_valid"=>!isnothing(check.physical) && check.physical.valid,
            "policy_valid"=>check.policy_valid,"solver_valid"=>check.solver_valid,
            "objective"=>isfinite(result.opf.objective) ? result.opf.objective : nothing,
            "iterations"=>solver==:ipopt ? (isempty(trace) ? nothing : trace[end]["iteration"]) : get(get(metadata,"final_native",Dict()),"iterations",nothing),
            "build_seconds"=>(phases[:built]-t0)/1e9,"solve_seconds"=>(phases[:solved]-phases[:built])/1e9,
            "extract_seconds"=>(phases[:extracted]-phases[:solved])/1e9,"validate_seconds"=>checked.time,
            "elapsed_seconds"=>measured.time,"julia_allocated_bytes"=>measured.bytes,
            "process_lifetime_peak_rss_bytes"=>Sys.maxrss(),
            "physical"=>isnothing(check.physical) ? nothing : DroopOPF._json_data(check.physical)))
    catch err
        row["error"]=sprint(showerror,err)
    end
    row["model"]=metadata;row["trace"]=trace;row["bounds"]=bounds
    write(joinpath(out,name*"-diagnostics.json"),JSON.json(row;pretty=true))
    println(name,": ",get(row,"status",get(row,"error","unknown"))," valid=",row["valid"]);flush(stdout)
    return row,result
end

function s1_reseed(case,p;fraction=nothing,result=nothing)
    taps=[TapControl(c.branch_id;lower=c.lower,upper=c.upper,nominal=c.nominal,
        initial=isnothing(fraction) ? get(result.taps,c.branch_id,only(b.tap_ratio for b in case.network.branches if b.id==c.branch_id)) : c.lower+fraction*(c.upper-c.lower)) for c in p.tap_controls]
    shunts=ShuntControl[]
    for c in p.shunt_controls
        q=DroopOPF._shunt_policy(case,c)
        initial=isnothing(fraction) ? get(result.susceptances,c.bank_id,q.initial) : q.lower+fraction*(q.upper-q.lower)
        push!(shunts,ShuntControl(c.bank_id;lower=c.lower,upper=c.upper,nominal=c.nominal,initial))
    end
    droops=DroopControl[]
    for c in p.droop_controls
        q=DroopOPF._joint_droop_policy(case,c)
        initial=isnothing(fraction) ? get(result.droops,c.control_id,q.initial) :
            DroopSettings((lo+fraction*(hi-lo) for (lo,hi) in values(q.ranges))...)
        push!(droops,DroopControl(c.control_id;slope_bounds=c.bounds.slope,v_ref_bounds=c.bounds.v_ref,
            deadband_low_bounds=c.bounds.deadband_low,deadband_high_bounds=c.bounds.deadband_high,initial))
    end
    (tap_controls=taps,shunt_controls=shunts,droop_controls=droops)
end

s1_flat(case)=ACState([clamp(1.,b.v_min,b.v_max) for b in case.network.buses],
    zeros(length(case.network.buses)),[g.initial_p for g in case.generators],[g.initial_q for g in case.generators])
function s1_load(case,factor)
    Case(case.id*"-load-"*string(factor);base_power=case.base_power,base_frequency=case.base_frequency,
        network=case.network,generators=case.generators,controls=case.controls,attachments=case.attachments,
        loads=[Load(l.id,l.bus_id;p=factor*l.p,q=factor*l.q) for l in case.loads])
end
function s1_summary(out,rows)
    write(joinpath(out,"summary.json"),JSON.json([Dict(k=>v for (k,v) in r if k ∉ ("trace","bounds")) for r in rows];pretty=true))
end
