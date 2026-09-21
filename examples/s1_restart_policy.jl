isdefined(@__MODULE__,:s1_attempt) || include("s1_public_recovery.jl")
isdefined(@__MODULE__,:s1_seed_layout) || include("s1_warm_start.jl")

# Canonical serialized physical data, declared policies, smoothing and backend identity.
s1_canonical(x::AbstractDict)="{"*join([JSON.json(string(k))*":"*s1_canonical(x[k]) for k in sort(collect(keys(x));by=string)],",")*"}"
s1_canonical(x::AbstractVector)="["*join(s1_canonical.(x),",")*"]"
s1_canonical(x)=JSON.json(x)
function s1_policy_context(case,p,epsilon,solver;control_normalization=:none,
    droop_q_bounds=:explicit,droop_q_formulation=:explicit)
    policies=Dict(string(k)=>[Dict(string(f)=>DroopOPF._json_data(getfield(c,f)) for f in fieldnames(typeof(c))) for c in cs] for (k,cs) in pairs(p))
    data=Dict("case"=>DroopOPF._json_data(case),"policies"=>policies,"epsilon"=>epsilon,
        "solver"=>string(solver),"solver_version"=>string(Base.pkgversion(solver==:ipopt ? Ipopt : MadNLP)),
        "adapter"=>"s1-reset-v1","control_normalization"=>string(control_normalization),
        "droop_q_bounds"=>string(droop_q_bounds),
        "droop_q_formulation"=>string(droop_q_formulation))
    bytes2hex(sha256(s1_canonical(data)))
end
function s1_policy_seed(model,context,solver)
    has_values(model) || return nothing
    primal=value.(all_variables(model))
    all(isfinite,primal) || return nothing
    Dict("schema_version"=>1,"context"=>context,"solver"=>string(solver),
        "signature"=>s1_seed_layout(model,context).signature,"primal"=>primal,
        "kind"=>"finite primal iterate for multiplier-reset recovery, not a validated physical solution")
end
function s1_apply_reset!(model,seed,context,solver)
    layout=s1_seed_layout(model,context)
    seed["schema_version"]==1 && seed["context"]==context && seed["solver"]==string(solver) &&
        seed["signature"]==layout.signature || throw(ArgumentError("incompatible restart seed"))
    length(seed["primal"])==length(layout.variables) && all(isfinite,seed["primal"]) || throw(ArgumentError("invalid primal seed"))
    solver in (:ipopt,:madnlp) || throw(ArgumentError("unsupported backend"))
    for (x,v) in zip(layout.variables,seed["primal"]);set_start_value(x,v);end
    # MadNLP's MOI adapter has no variable-bound dual-start interface.
    for c in layout.regular
        isbound=constraint_object(c).func isa JuMP.VariableRef
        (solver==:madnlp && isbound) || set_dual_start_value(c,0.)
    end
    set_nonlinear_dual_start_value(model,zeros(length(layout.nonlinear)))
    nothing
end
function s1_reset_options(solver)
    solver==:ipopt && return Dict{String,Any}("warm_start_init_point"=>"yes",
        "warm_start_bound_push"=>1e-8,"warm_start_bound_frac"=>1e-8,
        "warm_start_slack_bound_push"=>1e-8,"warm_start_slack_bound_frac"=>1e-8,"warm_start_mult_bound_push"=>1e-8)
    solver==:madnlp && return Dict{String,Any}("dual_initialized"=>true)
    throw(ArgumentError("unsupported backend"))
end
function s1_restart_decision(row,seed_available;iterations_left,seconds_left)
    get(row,"valid",false) && return "accept"
    get(row,"solver_valid",false) && return "diagnose_validation_failure"
    haskey(row,"error") && return "attempt_error"
    iterations_left>0 && seconds_left>0 || return "budget_exhausted"
    seed_available || return "no_compatible_finite_seed"
    get(row,"status","") in ("ITERATION_LIMIT","TIME_LIMIT","SLOW_PROGRESS","INTERRUPTED") || return "termination_not_retryable"
    "reset_multipliers"
end

"""Experimental bounded runner: accept first validated result, otherwise at most one reset."""
function s1_run_policy(out,name,case,start;policies=NamedTuple(),solver=:ipopt,epsilon=1e-6,
    control_normalization=:none,droop_q_bounds=:explicit,total_iterations=2000,attempt_iterations=1000,
    droop_q_formulation=:explicit,total_seconds=120.,attempt_seconds=60.,outer_deadline_ns=nothing,
    tags=Dict{String,Any}())
    solver in (:ipopt,:madnlp) || throw(ArgumentError("unsupported backend"))
    total_iterations>0 && attempt_iterations>0 && isfinite(total_seconds) && total_seconds>0 &&
        isfinite(attempt_seconds) && attempt_seconds>0 || throw(ArgumentError("invalid budget"))
    mkpath(out);context=s1_policy_context(case,policies,epsilon,solver;
        control_normalization,droop_q_bounds,droop_q_formulation)
    started=time_ns();deadline=started+UInt64(round(total_seconds*1e9))
    isnothing(outer_deadline_ns) || (deadline=min(deadline,outer_deadline_ns))
    rows=[];events=[];used=0;selected=nothing;result=nothing;seed=Ref{Any}(nothing)
    for attempt in 1:2
        remaining=(Float64(deadline)-Float64(time_ns()))/1e9
        remaining>0 && used<total_iterations || (push!(events,"budget_exhausted");break)
        iter_limit=min(attempt_iterations,total_iterations-used)
        seconds=min(attempt_seconds,remaining)
        attempt_deadline=min(deadline,time_ns()+UInt64(round(seconds*1e9)))
        options=Dict{String,Any}("bound_push"=>1e-8,"bound_frac"=>1e-8,"max_iter"=>iter_limit,
            (solver==:ipopt ? "max_cpu_time" : "max_wall_time")=>seconds)
        attempt==2 && merge!(options,s1_reset_options(solver))
        source_seed=seed[];seed[]=nothing
        metadata=Dict{String,Any}("policy"=>"one-reset-v1","attempt"=>attempt,"context"=>context,
            "load_factor"=>get(tags,"load_factor",1.),"start"=>get(tags,"start","supplied"),
            "builder_start_overridden"=>attempt==2,
            "dual_reset"=>attempt==1 ? "none; solver default initialization" : solver==:ipopt ? "constraint and bound dual starts zero; warm initialization" : "constraint duals zero; bound multipliers use MadNLP native initialization")
        merge!(metadata,tags)
        if attempt==2
            seedpath=joinpath(out,name*"-recovery-seed.json")
            write(seedpath,JSON.json(source_seed;pretty=true));source_seed=JSON.parsefile(seedpath)
            metadata["seed_file"]=basename(seedpath)
        end
        function hook(phase,model)
            if phase==:built && attempt==2
                s1_apply_reset!(model,source_seed,context,solver)
            elseif phase==:solved
                try
                    seed[]=s1_policy_seed(model,context,solver)
                catch err
                    metadata["seed_capture_error"]=sprint(showerror,err)
                end
            end
        end
        row,result=s1_attempt(out,name*"-attempt$attempt",case,start;policies,solver,epsilon,
            options,tags=metadata,experiment_hook=hook,deadline_ns=attempt_deadline,
            control_normalization,droop_q_bounds,droop_q_formulation)
        push!(rows,row)
        # Missing iteration evidence cannot be used to claim remaining budget.
        used+=isnothing(get(row,"iterations",nothing)) ? iter_limit : row["iterations"]
        decision=s1_restart_decision(row,!isnothing(seed[]);iterations_left=total_iterations-used,
            seconds_left=(Float64(deadline)-Float64(time_ns()))/1e9)
        push!(events,decision)
        if decision=="accept";selected=row["name"];break;end
        decision=="reset_multipliers" && attempt==1 || break
    end
    isnothing(selected) && !isempty(events) && events[end]=="reset_multipliers" && push!(events,"retry_limit_reached")
    summary=Dict("name"=>name,"control_normalization"=>string(control_normalization),
        "droop_q_bounds"=>string(droop_q_bounds),"solver"=>string(solver),"buses"=>length(case.network.buses),"tags"=>tags,
        "droop_q_formulation"=>string(droop_q_formulation),
        "valid"=>!isnothing(selected),"selected"=>selected,"events"=>events,
        "iterations"=>used,"elapsed_seconds"=>(time_ns()-started)/1e9,
        "budget_exceeded"=>Dict("iterations"=>used>total_iterations,"wall"=>(time_ns()-started)/1e9>total_seconds),
        "budget"=>Dict("total_iterations"=>total_iterations,"attempt_iterations"=>attempt_iterations,
            "total_seconds"=>total_seconds,"attempt_seconds"=>attempt_seconds,
            "clock"=>"wall deadline checked cooperatively at iteration callbacks; construction/validation cannot be preempted"),
        "attempts"=>[Dict(k=>v for (k,v) in row if k ∉ ("trace","bounds")) for row in rows])
    write(joinpath(out,name*"-policy.json"),JSON.json(summary;pretty=true))
    summary,isnothing(selected) ? nothing : result
end
