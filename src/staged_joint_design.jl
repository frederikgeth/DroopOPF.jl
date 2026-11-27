"""
Opt-in single-snapshot cold feasibility, reactive-reserve initialization, design
feasibility and active-loss design. Transfers every primal variable by identity.
Each stage requires strict model residual <=1e-10 and independent replay.
Returns (accepted, stages, result, reserve_floor); failure stops the sequence.
Reserve uses explicitly selected source Q boxes; circle constraints remain active
but do not define the reserve metric. AVR targets retain supplied assignments.
Existing optimize_joint_design behavior and smoothing remain unchanged.
"""
function optimize_staged_joint_design(case::Case;
    reserve_generator_ids, hessian="exact",max_iterations=3000,max_seconds=1200.,
    initialization_max_iterations=max_iterations,initialization_max_seconds=max_seconds,
    kwargs...)
    hessian in ("exact","limited-memory") || throw(ArgumentError("invalid Hessian"))
    for (n,t) in ((max_iterations,max_seconds),(initialization_max_iterations,initialization_max_seconds))
        n isa Integer && !(n isa Bool) && n>0 && isfinite(t) && t>0 ||
            throw(ArgumentError("invalid stage budget"))
    end
    any(haskey(kwargs,k) for k in (:optimizer_factory,:optimizer_attributes,:encoding,:_solve_sequence,:droop_q_formulation)) &&
        throw(ArgumentError("staged design fixes Ipopt, smooth explicit-Q encoding and strict numerical options"))
    ids=collect(reserve_generator_ids)
    !isempty(ids) && length(unique(ids))==length(ids) || throw(ArgumentError("reserve IDs must be nonempty and unique"))
    indices=Int[]
    for id in ids
        i=findfirst(g->g.id==id,case.generators)
        isnothing(i) && throw(ArgumentError("unknown reserve generator"))
        g=case.generators[i]
        g.available && g.q_max>g.q_min || throw(ArgumentError("reserve generator must be available with nonzero Q range"))
        push!(indices,i)
    end
    stages=NamedTuple[];floor=Ref(0.);accepted=Ref(false)
    strict=Dict{String,Any}("tol"=>1e-8,"constr_viol_tol"=>1e-10,
        "bound_relax_factor"=>0.,"acceptable_iter"=>0,"hessian_approximation"=>hessian,
        "bound_push"=>1e-9,"bound_frac"=>1e-9,"slack_bound_push"=>1e-9,"slack_bound_frac"=>1e-9)
    sequence=function(model,v,extract)
        function transfer!()
            point=Dict(x=>value(x) for x in all_variables(model))
            all(isfinite,values(point)) || error("nonfinite accepted stage handoff")
            for (x,y) in point;set_start_value(x,y);end
        end
        residual(point)=begin
            all(isfinite,values(point)) || return Inf
            report=JuMP.primal_feasibility_report(x->point[x],model)
            isempty(report) ? 0. : maximum(values(report))
        end
        function attempt(label;initialization=false)
            for (k,x) in strict;set_optimizer_attribute(model,k,x);end
            set_optimizer_attribute(model,"max_iter",initialization ? initialization_max_iterations : max_iterations)
            set_optimizer_attribute(model,"max_cpu_time",initialization ? initialization_max_seconds : max_seconds)
            start=Dict(x=>something(start_value(x),0.) for x in all_variables(model))
            requested=residual(start)
            actual=Ref{Any}(nothing)
            function capture_first(mode,iteration,args...)
                if actual[]===nothing
                    try
                        problem=JuMP.unsafe_backend(model).inner
                        x=zeros(problem.n);zl=similar(x);zu=similar(x)
                        g=zeros(problem.m);lambda=similar(g)
                        Ipopt.GetIpoptCurrentIterate(problem,false,problem.n,x,zl,zu,problem.m,g,lambda)
                        point=Dict(w=>x[JuMP.optimizer_index(w).value] for w in all_variables(model))
                        actual[]=(iteration=Int(iteration),max_violation=residual(point))
                    catch err
                        actual[]=(capture_error=sprint(showerror,err),)
                    end
                end
                true
            end
            JuMP.MOI.set(model,Ipopt.CallbackFunction(),capture_first)
            optimize!(model)
            result=extract()
            native=termination_status(model) in (JuMP.MOI.LOCALLY_SOLVED,JuMP.MOI.OPTIMAL) &&
                primal_status(model)==JuMP.MOI.FEASIBLE_POINT
            point=has_values(model) ? Dict(x=>value(x) for x in all_variables(model)) : Dict{JuMP.VariableRef,Float64}()
            violation=isempty(point) ? Inf : residual(point)
            replay=validate_joint_design(case,result)
            reserve=isempty(point) ? -Inf : minimum(min(value(v.qg[i])-case.generators[i].q_min,
                case.generators[i].q_max-value(v.qg[i]))/(case.generators[i].q_max-case.generators[i].q_min) for i in indices)
            passed=native && violation<=1e-10 && replay.valid &&
                (label in (:design_feasibility,:design) ? reserve>=floor[]-1e-8 : true)
            push!(stages,(stage=label,accepted=passed,result,replay,
                requested_max_violation=requested,actual_first_iterate=actual[],final_max_violation=violation,
                reserve,reserve_floor=floor[],solver_numerics=copy(strict),
                loss_mw=isnothing(result.opf.state) ? NaN :
                    case.base_power*(sum(result.opf.state.pg)-sum(l.p for l in case.loads)),
                start=Dict(string(x)=>y for (x,y) in start),
                point=Dict(string(x)=>y for (x,y) in point)))
            passed
        end
        @objective(model,Min,0.)
        attempt(:feasibility;initialization=true) || return
        transfer!()
        rho=@variable(model,lower_bound=0.,upper_bound=.5,start=0.,base_name="staged_reactive_reserve")
        rows=JuMP.ConstraintRef[]
        for i in indices
            g=case.generators[i];span=g.q_max-g.q_min
            push!(rows,@constraint(model,v.qg[i]>=g.q_min+rho*span))
            push!(rows,@constraint(model,v.qg[i]<=g.q_max-rho*span))
        end
        @objective(model,Max,rho)
        attempt(:initialization;initialization=true) || return
        floor[]=max(0.,last(stages).reserve-1e-8)
        transfer!()
        for row in rows;delete(model,row);end
        fix(rho,0.;force=true);set_start_value(rho,0.)
        if floor[]>0
            for i in indices
                g=case.generators[i];span=g.q_max-g.q_min
                @constraint(model,v.qg[i]>=g.q_min+floor[]*span)
                @constraint(model,v.qg[i]<=g.q_max-floor[]*span)
            end
        end
        @objective(model,Min,0.)
        attempt(:design_feasibility) || return
        transfer!()
        @objective(model,Min,sum(v.pg))
        accepted[]=attempt(:design)
    end
    result=optimize_joint_design(case;kwargs...,_solve_sequence=sequence)
    (;accepted=accepted[],stages,result,reserve_floor=floor[],reserve_generator_ids=copy(ids),reserve_metric=:source_q_box,objective_policy=:active_loss)
end

"""Recheck each saved native stage, reserve floor and complete primal handoff."""
function validate_staged_joint_design(case::Case,r)
    r.accepted && r.reserve_metric==:source_q_box && r.objective_policy==:active_loss ||
        return (;valid=false,reason=:unqualified)
    getproperty.(r.stages,:stage)==[:feasibility,:initialization,:design_feasibility,:design] ||
        return (;valid=false,reason=:sequence)
    indices=[findfirst(g->g.id==id,case.generators) for id in r.reserve_generator_ids]
    if isempty(indices)||any(isnothing,indices)||length(unique(indices))!=length(indices)
        return (;valid=false,reason=:selection)
    end
    all(case.generators[i].available&&case.generators[i].q_max>case.generators[i].q_min for i in indices) ||
        return (;valid=false,reason=:selection)
    validate_joint_design(case,r.result).valid || return (;valid=false,reason=:final_replay)
    floor=0.
    hessian=first(r.stages).solver_numerics["hessian_approximation"]
    hessian in ("exact","limited-memory") || return (;valid=false,reason=:numerics)
    expected=Dict{String,Any}("tol"=>1e-8,"constr_viol_tol"=>1e-10,
        "bound_relax_factor"=>0.,"acceptable_iter"=>0,"hessian_approximation"=>hessian,
        "bound_push"=>1e-9,"bound_frac"=>1e-9,"slack_bound_push"=>1e-9,"slack_bound_frac"=>1e-9)
    for (n,s) in enumerate(r.stages)
        s.solver_numerics==expected && s.accepted && s.result.opf.termination_status in (:LOCALLY_SOLVED,:OPTIMAL) &&
            s.result.opf.primal_status==:FEASIBLE_POINT &&
            isfinite(s.final_max_violation) && s.final_max_violation<=1e-10 &&
            validate_joint_design(case,s.result).valid ||
            return (;valid=false,reason=:stage)
        q=s.result.opf.state.qg
        reserve=minimum(min(q[i]-case.generators[i].q_min,case.generators[i].q_max-q[i])/
            (case.generators[i].q_max-case.generators[i].q_min) for i in indices)
        abs(reserve-s.reserve)<=1e-8 || return (;valid=false,reason=:reserve_metric)
        if n>1
            previous=r.stages[n-1].point
            all(haskey(s.start,k)&&s.start[k]==v for (k,v) in previous if k!="staged_reactive_reserve") ||
                return (;valid=false,reason=:handoff)
        end
        n>=3 && !(s.reserve_floor==floor && reserve>=floor-1e-8) &&
            return (;valid=false,reason=:floor)
        n==2 && (floor=max(0.,reserve-1e-8))
    end
    r.reserve_floor==floor || return (;valid=false,reason=:floor)
    r.result.opf.state.vm==last(r.stages).result.opf.state.vm &&
        r.result.opf.state.va==last(r.stages).result.opf.state.va &&
        r.result.opf.state.pg==last(r.stages).result.opf.state.pg &&
        r.result.opf.state.qg==last(r.stages).result.opf.state.qg &&
        r.result.taps==last(r.stages).result.taps &&
        r.result.susceptances==last(r.stages).result.susceptances &&
        r.result.droops==last(r.stages).result.droops || return (;valid=false,reason=:final_result)
    (;valid=true,reason=:qualified)
end
