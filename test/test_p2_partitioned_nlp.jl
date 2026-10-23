include(joinpath(@__DIR__,"..","examples","p2_partitioned_nlp.jl"))
using SparseArrays
@testset "Scenario derivative blocks preserve shared variables and expressions" begin
    m=Model(Ipopt.Optimizer);set_silent(m)
    @variable(m,shared>=.1,start=1.)
    @variable(m,f1_s1_x>=.1,start=.8);@variable(m,f1_s2_x>=.1,start=1.2)
    @NLparameter(m,p==2.)
    @NLexpression(m,common,shared^2+p)
    @NLexpression(m,left,common*f1_s1_x)
    @NLconstraint(m,left+f1_s1_x^2>=1.)
    @NLconstraint(m,common*f1_s2_x>=1.)
    @NLconstraint(m,f1_s1_x*f1_s2_x<=4.)
    @NLobjective(m,Min,shared^2+f1_s1_x^2+f1_s2_x^2)
    standard=JuMP.NLPEvaluator(m)
    blocks=P2PartitionedEvaluator(standard,all_variables(m))
    @test length(blocks.blocks)>=3
    @test !(:Hess in P2MOI.features_available(blocks))
    @test_throws ErrorException P2MOI.initialize(blocks,[:Hess])
    P2MOI.initialize(standard,[:Grad,:Jac]);P2MOI.initialize(blocks,[:Grad,:Jac])
    x=[1.1,.8,1.2];g0=zeros(3);g1=zeros(3)
    P2MOI.eval_constraint(standard,g0,x);P2MOI.eval_constraint(blocks,g1,x)
    @test g0≈g1
    @test P2MOI.eval_objective(standard,x)≈P2MOI.eval_objective(blocks,x)
    P2MOI.eval_objective_gradient(standard,g0,x);P2MOI.eval_objective_gradient(blocks,g1,x)
    @test g0≈g1
    function jac(e,x)
        s=P2MOI.jacobian_structure(e);v=zeros(length(s));P2MOI.eval_constraint_jacobian(e,v,x)
        Matrix(sparse(first.(s),last.(s),v,3,3))
    end
    J=jac(blocks,x);@test J≈jac(standard,x)
    for j in 1:3
        plus=copy(x);minus=copy(x);plus[j]+=1e-6;minus[j]-=1e-6
        P2MOI.eval_constraint(blocks,g0,plus);P2MOI.eval_constraint(blocks,g1,minus)
        @test J[:,j]≈(g0-g1)/2e-6 atol=1e-8
    end
end
@testset "Scenario derivative blocks preserve the coupled optimum" begin
    function build()
        m=Model(Ipopt.Optimizer);set_silent(m)
        @variable(m,.1<=shared<=3.,start=1.)
        @variable(m,.1<=f1_s1_x<=3.,start=1.)
        @variable(m,.1<=f1_s2_x<=3.,start=1.)
        @NLconstraint(m,f1_s1_x*shared>=1.)
        @NLconstraint(m,f1_s2_x*shared>=1.)
        @objective(m,Min,f1_s1_x+f1_s2_x+shared)
        m
    end
    a=build();optimize!(a)
    b=build();p2_partitioned_hook!(b);optimize!(b)
    @test termination_status(b) in (P2MOI.LOCALLY_SOLVED,P2MOI.ALMOST_LOCALLY_SOLVED)
    @test objective_value(b)≈2sqrt(2.) atol=1e-6
    @test objective_value(b)≈objective_value(a) atol=1e-6
    @test all(isapprox(value(b[v]),value(a[v]);atol=1e-5) for v in (:shared,:f1_s1_x,:f1_s2_x))
end
