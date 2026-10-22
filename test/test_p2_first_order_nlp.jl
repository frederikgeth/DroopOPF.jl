include(joinpath(@__DIR__,"..","examples","p2_first_order_nlp.jl"))
@testset "First-order nonlinear evaluator preserves derivatives and solution" begin
    m=Model(Ipopt.Optimizer);set_silent(m)
    @variable(m,x,start=.8);@variable(m,y,start=1.2)
    @NLconstraint(m,x*y>=1.)
    @NLobjective(m,Min,x^2+y^2)
    original=JuMP.NLPEvaluator(m);first_order=P2FirstOrderEvaluator(original)
    @test :Hess in P2MOI.features_available(original)
    @test !(:Hess in P2MOI.features_available(first_order))
    @test_throws ErrorException P2MOI.initialize(first_order,[:Hess])
    P2MOI.initialize(first_order,[:Grad,:Jac])
    p=[.8,1.2];g=zeros(2);P2MOI.eval_objective_gradient(first_order,g,p)
    @test g≈2p
    J=zeros(length(P2MOI.jacobian_structure(first_order)))
    P2MOI.eval_constraint_jacobian(first_order,J,p)
    @test J≈[1.2,.8]
    for j in 1:2
        plus=copy(p);minus=copy(p);plus[j]+=1e-6;minus[j]-=1e-6
        fd=(P2MOI.eval_objective(first_order,plus)-P2MOI.eval_objective(first_order,minus))/2e-6
        @test g[j]≈fd atol=1e-8
    end
    p2_first_order_hook!(m);optimize!(m)
    @test termination_status(m) in (P2MOI.LOCALLY_SOLVED,P2MOI.ALMOST_LOCALLY_SOLVED)
    @test objective_value(m)≈2. atol=1e-6
    @test value(x)*value(y)>=1-1e-7
    # A second solve must rebuild/wrap the new nonlinear evaluator correctly.
    solved_x,solved_y=value(x),value(y)
    set_start_value(x,solved_x);set_start_value(y,solved_y);optimize!(m)
    @test objective_value(m)≈2. atol=1e-6
end

@testset "First-order adapter preserves a linear objective with nonlinear constraints" begin
    m=Model(Ipopt.Optimizer);set_silent(m)
    @variable(m,x>=.1,start=.8);@variable(m,y>=.1,start=1.2)
    @NLconstraint(m,x*y>=1.)
    @objective(m,Min,x+y)
    p2_first_order_hook!(m);optimize!(m)
    @test termination_status(m) in (P2MOI.LOCALLY_SOLVED,P2MOI.ALMOST_LOCALLY_SOLVED)
    @test objective_value(m)≈2. atol=1e-6
    @test value(x)*value(y)>=1-1e-7
end
