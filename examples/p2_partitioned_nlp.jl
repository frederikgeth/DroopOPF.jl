# Scenario-partitioned derivative evaluation for one unchanged coupled NLP.
# Shared variables are gathered/scattered; no scenario constraints are omitted.
isdefined(@__MODULE__,:P2FirstOrderEvaluator) || include("p2_first_order_nlp.jl")
mutable struct P2PartitionedEvaluator <: P2MOI.AbstractNLPEvaluator
    blocks::Vector{Any}
    nvariables::Int
    nconstraints::Int
    jacobian::Vector{Tuple{Int,Int}}
    initialization_seconds::Float64
end
function P2PartitionedEvaluator(original,variables)
    N=P2MOI.Nonlinear;source=original.model
    positions=Dict(index(v).value=>i for (i,v) in enumerate(variables))
    groups=Dict(index(v).value=>begin
        match_group=match(r"^(f\d+_s\d+)_",name(v))
        isnothing(match_group) ? nothing : match_group.captures[1]
    end for v in variables)
    owners=Dict{Int,Union{Nothing,String}}()
    function expression_owner(expr)
        for node in expr.nodes
            if node.type==N.NODE_MOI_VARIABLE
                group=get(groups,node.index,nothing);isnothing(group)||return group
            elseif node.type==N.NODE_SUBEXPRESSION
                group=get!(owners,node.index) do
                    expression_owner(source.expressions[node.index])
                end
                isnothing(group)||return group
            end
        end
        nothing
    end
    constraints=collect(values(source.constraints));members=Dict{String,Vector{Int}}()
    for (i,c) in enumerate(constraints)
        group=something(expression_owner(c.expression),"other")
        push!(get!(members,group,Int[]),i)
    end
    blocks=Any[]
    function add_block(rows;objective=false)
        needed=Set{Int}();variable_ids=Set{Int}()
        function visit(expr)
            for node in expr.nodes
                if node.type==N.NODE_SUBEXPRESSION
                    if !(node.index in needed)
                        push!(needed,node.index);visit(source.expressions[node.index])
                    end
                elseif node.type==N.NODE_MOI_VARIABLE
                    push!(variable_ids,node.index)
                elseif node.type==N.NODE_VARIABLE
                    error("Expected uninitialized nonlinear expression nodes")
                end
            end
        end
        objective && visit(source.objective)
        for i in rows;visit(constraints[i].expression);end
        expressions=sort!(collect(needed));mapping=Dict(old=>new for (new,old) in enumerate(expressions))
        function clone(expr)
            copy=N.Expression()
            append!(copy.nodes,[N.Node(node.type,node.type==N.NODE_SUBEXPRESSION ? mapping[node.index] : node.index,node.parent) for node in expr.nodes])
            append!(copy.values,expr.values);copy
        end
        local_model=N.Model();local_model.operators=source.operators
        local_model.parameters=source.parameters
        append!(local_model.expressions,[clone(source.expressions[i]) for i in expressions])
        for (j,i) in enumerate(rows)
            c=constraints[i];local_model.constraints[N.ConstraintIndex(j)]=N.Constraint(clone(c.expression),c.set)
        end
        local_model.last_constraint_index=length(rows)
        objective && (local_model.objective=clone(source.objective))
        ids=sort!(collect(variable_ids));columns=[positions[i] for i in ids]
        evaluator=N.Evaluator(local_model,N.SparseReverseMode(),P2MOI.VariableIndex.(ids))
        push!(blocks,(;evaluator,rows,columns,objective,g=zeros(length(rows)),gradient=zeros(length(columns)),jac=Float64[]))
    end
    for group in sort!(collect(keys(members)));add_block(members[group]);end
    isnothing(source.objective)||add_block(Int[];objective=true)
    @assert sum(length(b.rows) for b in blocks)==length(constraints)
    P2PartitionedEvaluator(blocks,length(variables),length(constraints),Tuple{Int,Int}[],0.)
end
P2MOI.features_available(::P2PartitionedEvaluator)=[:Grad,:Jac]
function P2MOI.initialize(e::P2PartitionedEvaluator,features)
    all(f->f in (:Grad,:Jac),features)||error("Partitioned evaluator supplies first derivatives only")
    started=time();empty!(e.jacobian)
    for b in e.blocks
        P2MOI.initialize(b.evaluator,copy(features))
        structure=P2MOI.jacobian_structure(b.evaluator)
        resize!(b.jac,length(structure))
        append!(e.jacobian,[(b.rows[r],b.columns[c]) for (r,c) in structure])
    end
    e.initialization_seconds=time()-started
end
function P2MOI.eval_objective(e::P2PartitionedEvaluator,x)
    sum((P2MOI.eval_objective(b.evaluator,x[b.columns]) for b in e.blocks if b.objective);init=0.)
end
function P2MOI.eval_objective_gradient(e::P2PartitionedEvaluator,g,x)
    fill!(g,0.)
    for b in e.blocks
        b.objective||continue
        P2MOI.eval_objective_gradient(b.evaluator,b.gradient,x[b.columns])
        for (i,j) in enumerate(b.columns);g[j]+=b.gradient[i];end
    end
end
function P2MOI.eval_constraint(e::P2PartitionedEvaluator,g,x)
    for b in e.blocks
        isempty(b.rows)&&continue
        P2MOI.eval_constraint(b.evaluator,b.g,x[b.columns])
        for (i,j) in enumerate(b.rows);g[j]=b.g[i];end
    end
end
P2MOI.jacobian_structure(e::P2PartitionedEvaluator)=e.jacobian
function P2MOI.eval_constraint_jacobian(e::P2PartitionedEvaluator,J,x)
    offset=0
    for b in e.blocks
        P2MOI.eval_constraint_jacobian(b.evaluator,b.jac,x[b.columns])
        copyto!(J,offset+1,b.jac,1,length(b.jac));offset+=length(b.jac)
    end
end
function p2_partitioned_hook!(model;diagnostics=nothing)
    set_optimizer_attribute(model,"hessian_approximation","limited-memory")
    hook=function(m)
        data=P2MOI.get(m,P2MOI.NLPBlock());started=time()
        evaluator=P2PartitionedEvaluator(data.evaluator,all_variables(m))
        P2MOI.set(m,P2MOI.NLPBlock(),P2MOI.NLPBlockData(data.constraint_bounds,evaluator,data.has_objective))
        m.ext[:p2_partitioned_evaluator]=evaluator
        m.ext[:p2_partition_seconds]=time()-started
        P2MOI.optimize!(backend(m));m.is_model_dirty=false
        nothing
    end
    set_optimize_hook(model,hook);model
end
