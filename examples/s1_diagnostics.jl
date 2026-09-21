using DroopOPF, JuMP, Ipopt, JSON

"""Ipopt iteration recorder with an optional cooperative deadline; no model edits."""
function s1_recorder(trace,bounds,metadata=Dict{String,Any}();deadline_ns=nothing)
    function hook(phase,model)
        if phase==:built
            metadata["variables"]=num_variables(model)
            metadata["constraints"]=num_constraints(model;count_variable_in_set_constraints=true)
            metadata["nonlinear_derivative_features"]=string.(JuMP.MOI.features_available(JuMP.NLPEvaluator(model)))
            callback=function(mode,iteration,objective,primal,dual,mu,step,regularization,alpha_dual,alpha_primal,trials)
                row=Dict{String,Any}("iteration"=>iteration,"restoration"=>mode==1,"objective"=>objective,
                    "inf_pr"=>primal,"inf_du"=>dual,"mu"=>mu,"step_norm"=>step,
                    "hessian_regularization"=>regularization,"alpha_pr"=>alpha_primal,"alpha_du"=>alpha_dual,"line_search_trials"=>trials)
                try
                    inner=JuMP.unsafe_backend(model).inner
                    n,m=inner.n,inner.m
                    xl,xu,cl,cu,grad=zeros(n),zeros(n),zeros(n),zeros(n),zeros(n)
                    cons,cg=zeros(m),zeros(m)
                    Ipopt.GetIpoptCurrentViolations(inner,false,n,xl,xu,cl,cu,grad,m,cons,cg)
                    row["unscaled_stationarity"]=maximum(abs,grad;init=0.)
                    row["unscaled_complementarity"]=maximum(abs,vcat(cl,cu,cg);init=0.)
                    row["unscaled_constraint_violation"]=maximum(abs,cons;init=0.)
                    row["unscaled_bound_violation"]=maximum(abs,vcat(xl,xu);init=0.)
                catch err
                    row["violation_query_error"]=sprint(showerror,err)
                end
                push!(trace,row)
                isnothing(deadline_ns) || time_ns()<deadline_ns
            end
            set_attribute(model,Ipopt.CallbackFunction(),callback)
        elseif phase==:solved && has_values(model)
            for x in all_variables(model)
                value_x=value(x)
                lo=is_fixed(x) ? fix_value(x) : has_lower_bound(x) ? lower_bound(x) : nothing
                hi=is_fixed(x) ? fix_value(x) : has_upper_bound(x) ? upper_bound(x) : nothing
                push!(bounds,Dict("name"=>name(x),"value"=>value_x,"lower"=>lo,"upper"=>hi,
                    "near_lower"=>!isnothing(lo) && abs(value_x-lo)<1e-6,"near_upper"=>!isnothing(hi) && abs(value_x-hi)<1e-6))
            end
        end
    end
    hook
end

function s1_solve(out,name,case,start;policies=NamedTuple(),options=Dict{String,Any}(),epsilon=1e-6,silent=true)
    mkpath(out);trace=[];bounds=[];metadata=Dict{String,Any}()
    settings=merge(Dict{String,Any}("max_iter"=>1000,"max_cpu_time"=>60.,"bound_relax_factor"=>0.,"mu_strategy"=>"adaptive","tol"=>1e-8),options)
    row=Dict{String,Any}("name"=>name,"buses"=>length(case.network.buses),"options"=>settings,"epsilon"=>epsilon,"valid"=>false)
    try
        measured=@timed optimize_joint_design(case;initial_state=start,smooth_epsilon=epsilon,policies...,
            silent,optimizer_attributes=settings,_measurement_hook=s1_recorder(trace,bounds,metadata))
        r=measured.value;check=validate_joint_design(case,r)
        write_joint_design(joinpath(out,name*"-design.json"),r)
        merge!(row,Dict("status"=>string(r.opf.termination_status),"valid"=>check.valid,"solver_valid"=>check.solver_valid,
            "physical_valid"=>!isnothing(check.physical) && check.physical.valid,"policy_valid"=>check.policy_valid,
            "objective"=>isfinite(r.opf.objective) ? r.opf.objective : nothing,"elapsed_seconds"=>measured.time,"julia_allocated_bytes"=>measured.bytes,
            "iterations"=>isempty(trace) ? nothing : trace[end]["iteration"],
            "physical"=>isnothing(check.physical) ? nothing : DroopOPF._json_data(check.physical)))
    catch err
        row["error"]=sprint(showerror,err)
    end
    row["trace"]=trace;row["bounds"]=bounds;row["model"]=metadata
    write(joinpath(out,name*"-diagnostics.json"),JSON.json(row;pretty=true))
    println(name,": ",get(row,"status",get(row,"error","unknown"))," valid=",row["valid"]);flush(stdout)
    row
end
