# Avoid exact Hessian sparsity construction for an explicitly limited-memory solve.
# This adapter changes derivative preparation, never the objective or constraints.
using JuMP
const P2MOI=JuMP.MOI
struct P2FirstOrderEvaluator{E<:P2MOI.AbstractNLPEvaluator} <: P2MOI.AbstractNLPEvaluator
    inner::E
end
P2MOI.features_available(e::P2FirstOrderEvaluator)=filter(x->x in (:Grad,:Jac),P2MOI.features_available(e.inner))
function P2MOI.initialize(e::P2FirstOrderEvaluator,features)
    all(x->x in (:Grad,:Jac),features)||error("First-order evaluator does not supply Hessians")
    P2MOI.initialize(e.inner,features)
end
P2MOI.eval_objective(e::P2FirstOrderEvaluator,x)=P2MOI.eval_objective(e.inner,x)
P2MOI.eval_objective_gradient(e::P2FirstOrderEvaluator,g,x)=P2MOI.eval_objective_gradient(e.inner,g,x)
P2MOI.eval_constraint(e::P2FirstOrderEvaluator,g,x)=P2MOI.eval_constraint(e.inner,g,x)
P2MOI.jacobian_structure(e::P2FirstOrderEvaluator)=P2MOI.jacobian_structure(e.inner)
P2MOI.eval_constraint_jacobian(e::P2FirstOrderEvaluator,J,x)=P2MOI.eval_constraint_jacobian(e.inner,J,x)
function p2_first_order_hook!(model)
    set_optimizer_attribute(model,"hessian_approximation","limited-memory")
    hook=function(m)
        data=P2MOI.get(m,P2MOI.NLPBlock())
        data===nothing&&error("Expected a legacy nonlinear block")
        evaluator=data.evaluator isa P2FirstOrderEvaluator ? data.evaluator : P2FirstOrderEvaluator(data.evaluator)
        P2MOI.set(m,P2MOI.NLPBlock(),P2MOI.NLPBlockData(data.constraint_bounds,evaluator,data.has_objective))
        P2MOI.optimize!(backend(m))
        # The hook owns the optimize call and must update JuMP's result cache state.
        m.is_model_dirty=false
        nothing
    end
    set_optimize_hook(model,hook)
    model
end
