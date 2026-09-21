isdefined(@__MODULE__,:s1_attempt) || include("s1_public_recovery.jl")
using LinearAlgebra, SparseArrays

function s1_polynomial_gradient(f,variables,x)
    positions=Dict(v=>i for (i,v) in enumerate(variables));g=zeros(length(x))
    if f isa JuMP.VariableRef
        g[positions[f]]=1.
    elseif f isa JuMP.GenericAffExpr || f isa JuMP.GenericQuadExpr
        for (a,v) in linear_terms(f);g[positions[v]]+=a;end
        if f isa JuMP.GenericQuadExpr
            for (a,u,v) in quad_terms(f)
                i,j=positions[u],positions[v];g[i]+=a*x[j];g[j]+=a*x[i]
            end
        end
    elseif !(f isa Number)
        throw(ArgumentError("unsupported polynomial expression"))
    end
    g
end
function s1_set_diagnostics(set,value,multiplier)
    if set isa JuMP.MOI.EqualTo
        return (violation=abs(value-set.value),slack=abs(value-set.value),complementarity=0.,dual_sign_violation=0.,equality=true)
    elseif set isa JuMP.MOI.LessThan
        slack=set.upper-value
        return (violation=max(-slack,0.),slack=slack,complementarity=abs(multiplier*slack),dual_sign_violation=max(multiplier,0.),equality=false)
    elseif set isa JuMP.MOI.GreaterThan
        slack=value-set.lower
        return (violation=max(-slack,0.),slack=slack,complementarity=abs(multiplier*slack),dual_sign_violation=max(-multiplier,0.),equality=false)
    end
    throw(ArgumentError("unsupported constraint set"))
end

"""Read-only physical-coordinate KKT decomposition; never an acceptance override."""
function s1_kkt_snapshot(model;at_start=false,row_scales=nothing)
    objective_sense(model)==JuMP.MOI.MIN_SENSE || throw(ArgumentError("minimization required"))
    variables=all_variables(model);x=at_start ? Float64[start_value(v) for v in variables] : value.(variables)
    all(isfinite,x) || throw(ArgumentError("nonfinite primal point"))
    evaluator=JuMP.NLPEvaluator(model);JuMP.MOI.initialize(evaluator,[:Jac])
    nl=all_nonlinear_constraints(model);structure=JuMP.MOI.jacobian_structure(evaluator)
    jv=zeros(length(structure));JuMP.MOI.eval_constraint_jacobian(evaluator,jv,x)
    values=zeros(length(nl));JuMP.MOI.eval_constraint(evaluator,values,x)
    J=sparse(first.(structure),last.(structure),jv,length(nl),length(x))
    rownorm=[maximum(abs,J[i,:];init=0.) for i in eachindex(nl)]
    columnnorm=[maximum(abs,J[:,i];init=0.) for i in eachindex(x)]
    scales=isnothing(row_scales) ? 1 ./ max.(rownorm,1.) : row_scales
    length(scales)==length(nl) && all(s->isfinite(s) && s>0,scales) || throw(ArgumentError("invalid row scales"))
    dual_available=!at_start && has_duals(model)
    lambda=dual_available ? dual.(nl) : zeros(length(nl))
    all(isfinite,lambda) || throw(ArgumentError("nonfinite nonlinear dual"))
    objective=s1_polynomial_gradient(objective_function(model),variables,x)
    nlterm=J'*lambda;regularterm=zeros(length(x));rows=Dict{String,Any}[]
    for (i,c) in enumerate(nl)
        set=JuMP.nonlinear_model(model).constraints[index(c)].set
        d=s1_set_diagnostics(set,values[i],lambda[i])
        push!(rows,Dict("row"=>i,"value"=>values[i],"set"=>string(set),
            "jacobian_max"=>rownorm[i],"scale"=>scales[i],"scaled_jacobian_max"=>scales[i]*rownorm[i],
            "dual"=>dual_available ? lambda[i] : nothing,"violation"=>d.violation,"slack"=>d.slack,
            "scaled_violation"=>scales[i]*d.violation,"complementarity"=>dual_available ? d.complementarity : nothing,
            "dual_sign_violation"=>dual_available ? d.dual_sign_violation : nothing,"equality"=>d.equality))
    end
    nlset=Set(nl);regular=[];getvalue=v->x[findfirst(==(v),variables)]
    for c in all_constraints(model;include_variable_in_set_constraints=true)
        c in nlset && continue
        obj=constraint_object(c);y=dual_available ? dual(c) : 0.
        isfinite(y) || throw(ArgumentError("nonfinite regular dual"))
        f=value(getvalue,obj.func);d=s1_set_diagnostics(obj.set,f,y)
        regularterm .+= y.*s1_polynomial_gradient(obj.func,variables,x)
        push!(regular,Dict("constraint"=>string(c),"dual"=>dual_available ? y : nothing,
            "violation"=>d.violation,"slack"=>d.slack,"equality"=>d.equality,
            "complementarity"=>dual_available ? d.complementarity : nothing,
            "dual_sign_violation"=>dual_available ? d.dual_sign_violation : nothing))
    end
    stationarity=objective-nlterm-regularterm
    free=[i for (i,v) in enumerate(variables) if !is_fixed(v) && !(has_lower_bound(v) && has_upper_bound(v) && lower_bound(v)==upper_bound(v))]
    variable_rows=[begin
        lo=is_fixed(v) ? fix_value(v) : has_lower_bound(v) ? lower_bound(v) : nothing
        hi=is_fixed(v) ? fix_value(v) : has_upper_bound(v) ? upper_bound(v) : nothing
        Dict("name"=>name(v),"value"=>x[i],"lower"=>lo,"upper"=>hi,"fixed"=>!(i in free),
            "near_bound"=>(!isnothing(lo) && abs(x[i]-lo)<=1e-6)||(!isnothing(hi) && abs(x[i]-hi)<=1e-6),
            "jacobian_column_max"=>columnnorm[i],"objective_gradient"=>objective[i],
            "nonlinear_dual_term"=>dual_available ? nlterm[i] : nothing,
            "regular_dual_term"=>dual_available ? regularterm[i] : nothing,
            "stationarity"=>dual_available ? stationarity[i] : nothing)
    end for (i,v) in enumerate(variables)]
    Dict("at_start"=>at_start,"dual_available"=>dual_available,"variables"=>variable_rows,"nonlinear_rows"=>rows,"regular_rows"=>regular,
        "stationarity_max"=>dual_available ? maximum(abs,stationarity;init=0.) : nothing,
        "free_stationarity_max"=>dual_available ? maximum(abs,stationarity[free];init=0.) : nothing,
        "complementarity_max"=>dual_available ? maximum(r["complementarity"] for r in vcat(rows,regular);init=0.) : nothing,
        "dual_sign_violation_max"=>dual_available ? maximum(r["dual_sign_violation"] for r in vcat(rows,regular);init=0.) : nothing,
        "constraint_violation_max"=>maximum(r["violation"] for r in vcat(rows,regular);init=0.),
        "rescaling_stationarity_difference"=>dual_available ? maximum(abs,(Diagonal(scales)*J)'*(lambda./scales)-nlterm;init=0.) : nothing,
        "convention"=>"Minimization: gradient(f) - J_nonlinear' * dual_nonlinear - J_regular' * dual_regular. JuMP/MOI duals; all terms in original physical coordinates. Fixed coordinates reported separately.",
        "scope"=>"Read-only derivative and KKT diagnostics, not proof of optimality or an independent acceptance rule. Row scale = 1/max(initial row infinity norm,1); no scaling is applied to the solve. Norm ranges are not condition numbers.")
end
