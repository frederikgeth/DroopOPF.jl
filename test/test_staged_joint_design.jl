using Test, DroopOPF
isdefined(@__MODULE__,:m72_case)||include(joinpath(@__DIR__,"../examples/m7_2_case.jl"))
@testset "Strict staged joint design and complete primal transfer" begin
    c=m72_case();ids=[g.id for g in c.generators if g.available && g.q_max>g.q_min]
    opts=(reserve_generator_ids=ids,droop_controls=[DroopControl(2;slope_bounds=(.04,.1))],
      tap_controls=[TapControl(11;lower=.95,upper=1.05)],shunt_controls=[ShuntControl(201)],
      initial_state=m5_initial_state(c))
    r=optimize_staged_joint_design(c;opts...)
    @test r.accepted
    @test validate_staged_joint_design(c,r).valid
    @test !validate_staged_joint_design(c,merge(r,(reserve_floor=r.reserve_floor+.01,))).valid
    corrupted=deepcopy(r);key=first(k for k in keys(corrupted.stages[3].start) if k!="staged_reactive_reserve")
    corrupted.stages[3].start[key]+=.01
    @test !validate_staged_joint_design(c,corrupted).valid
    @test getproperty.(r.stages,:stage)==[:feasibility,:initialization,:design_feasibility,:design]
    @test r.reserve_floor==max(0.,r.stages[2].reserve-1e-8)
    for (i,s) in enumerate(r.stages)
        @test s.accepted && s.replay.valid
        @test s.final_max_violation<=1e-10
        @test !haskey(s.actual_first_iterate,:capture_error)
        @test s.actual_first_iterate.iteration==0
        @test s.solver_numerics["bound_relax_factor"]==0
        @test s.solver_numerics["acceptable_iter"]==0
        @test s.solver_numerics["bound_push"]==1e-9
        if i>1
            for (key,val) in r.stages[i-1].point
                key=="staged_reactive_reserve"&&continue
                @test s.start[key]==val
            end
        end
        i>=3&&(@test s.reserve>=r.reserve_floor-1e-8)
    end
    @test validate_joint_design(c,r.result).valid
    @test r.result.taps[22]==1.
    @test c.network.banks[1].state==(1,)
    bad=deepcopy(r.result);bad.opf.state.pg[1]+=.05
    @test !validate_joint_design(c,bad).valid
    stopped=optimize_staged_joint_design(c;opts...,initialization_max_iterations=1)
    @test !stopped.accepted
    @test length(stopped.stages)==1
    @test last(stopped.stages).stage==:feasibility
    @test_throws ArgumentError optimize_staged_joint_design(c;reserve_generator_ids=Int[])
    @test_throws ArgumentError optimize_staged_joint_design(c;reserve_generator_ids=[999])
    @test_throws ArgumentError optimize_staged_joint_design(c;opts...,max_iterations=0)
    @test_throws ArgumentError optimize_staged_joint_design(c;opts...,optimizer_attributes=Dict("tol"=>1.))
end

using JuMP
@testset "Core log1pexp saturation retains finite exact derivatives" begin
    for x0 in (-.51,-4.15868348091486e-9,0.,.51)
        m=Model();@variable(m,x,start=x0)
        JuMP.register(m,:stable_softplus,1,z->DroopOPF._smooth_positive(z,1e-8);autodiff=true)
        @NLconstraint(m,stable_softplus(x)==0.)
        e=JuMP.NLPEvaluator(m);JuMP.MOI.initialize(e,[:Jac,:Hess])
        jac=zeros(length(JuMP.MOI.jacobian_structure(e)))
        hess=zeros(length(JuMP.MOI.hessian_lagrangian_structure(e)))
        JuMP.MOI.eval_constraint_jacobian(e,jac,[x0])
        JuMP.MOI.eval_hessian_lagrangian(e,hess,[x0],0.,[1.])
        @test all(isfinite,jac)
        @test all(isfinite,hess)
        expected=x0>=0 ? 1/(1+exp(-x0/1e-8)) : exp(x0/1e-8)/(1+exp(x0/1e-8))
        @test only(jac)≈expected atol=1e-14
    end
end
