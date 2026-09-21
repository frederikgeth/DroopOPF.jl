using Test, DroopOPF, JuMP, Ipopt
include(joinpath(@__DIR__,"..","examples","s1_kkt.jl"))
@testset "Physical-coordinate KKT signs and row scaling" begin
    for solver in (Ipopt.Optimizer,MadNLP.Optimizer)
        model=Model(solver);set_silent(model)
        @variable(model,x>=1,start=1.5)
        @variable(model,y>=0,start=.5)
        q=@NLexpression(model,1000*(x+y))
        @NLconstraint(model,q==2000)
        @NLconstraint(model,y^2<=4)
        @objective(model,Min,x^2+3y^2)
        initial=s1_kkt_snapshot(model;at_start=true)
        @test initial["nonlinear_rows"][1]["scale"]≈.001
        optimize!(model)
        report=s1_kkt_snapshot(model;row_scales=[r["scale"] for r in initial["nonlinear_rows"]])
        @test report["dual_available"]
        @test report["free_stationarity_max"]<1e-5
        @test report["constraint_violation_max"]<1e-5
        @test report["complementarity_max"]<1e-5
        @test report["dual_sign_violation_max"]<1e-5
        @test report["rescaling_stationarity_difference"]<1e-12
        @test value(x)≈1.5 atol=1e-5
        @test value(y)≈.5 atol=1e-5
        @test isnothing(initial["stationarity_max"])
        @test_throws ArgumentError s1_kkt_snapshot(model;row_scales=[0.,1.])
        g=s1_polynomial_gradient(x*y+2x^2+3y,[x,y],[2.,4.])
        @test g≈[12.,5.]
    end
end
@testset "KKT active multipliers and rejected stationarity" begin
    for solver in (Ipopt.Optimizer,MadNLP.Optimizer),active in (:bound,:nonlinear)
        model=Model(solver);set_silent(model)
        @variable(model,x>=1,start=1.5)
        @variable(model,y>=0,start=.5)
        @NLconstraint(model,x+y==2)
        limit=active==:bound ? 4. : .16
        c=@NLconstraint(model,y^2<=limit)
        active==:bound ? @objective(model,Min,3x^2+y^2) : @objective(model,Min,x^2+3y^2)
        optimize!(model)
        r=s1_kkt_snapshot(model)
        @test r["free_stationarity_max"]<1e-5
        @test r["complementarity_max"]<1e-5
        @test r["dual_sign_violation_max"]<1e-5
        if active==:bound
            @test dual(LowerBoundRef(x))>1.
            @test r["variables"][1]["near_bound"]
        else
            @test dual(c)<-.1
            @test value(y)≈.4 atol=1e-5
        end
    end
    @test s1_set_diagnostics(JuMP.MOI.LessThan(1.),.5,2.).dual_sign_violation==2.
    @test s1_set_diagnostics(JuMP.MOI.GreaterThan(1.),2.,-2.).dual_sign_violation==2.
end
