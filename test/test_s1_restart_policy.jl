include(joinpath(@__DIR__,"..","examples","s1_restart_policy.jl"))
struct S1MadInitialProbe <: MadNLP.AbstractUserCallback
    rows::Vector
end
function (probe::S1MadInitialProbe)(solver::MadNLP.AbstractMadNLPSolver,mode)
    isempty(probe.rows) && push!(probe.rows,(y=copy(MadNLP.get_y(solver)),zl=copy(MadNLP.get_zl_r(solver)),zu=copy(MadNLP.get_zu_r(solver))))
    true
end
@testset "S1 bounded policy decisions and budgets" begin
    decision(r,seed=true;iterations_left=10,seconds_left=10.)=s1_restart_decision(r,seed;iterations_left,seconds_left)
    @test decision(Dict("valid"=>true);iterations_left=0)=="accept"
    @test decision(Dict("solver_valid"=>true,"physical_valid"=>false))=="diagnose_validation_failure"
    @test decision(Dict("error"=>"failed"))=="attempt_error"
    @test decision(Dict("status"=>"ITERATION_LIMIT"))=="reset_multipliers"
    @test decision(Dict("status"=>"SLOW_PROGRESS"))=="reset_multipliers"
    @test decision(Dict("status"=>"TIME_LIMIT");seconds_left=0.)=="budget_exhausted"
    @test decision(Dict("status"=>"ITERATION_LIMIT"),false)=="no_compatible_finite_seed"
    @test decision(Dict("status"=>"LOCALLY_INFEASIBLE"))=="termination_not_retryable"
    case=load_matpower_case(joinpath(@__DIR__,"data","droop2.m"))
    context=s1_policy_context(case,NamedTuple(),1e-6,:ipopt)
    @test context==s1_policy_context(case,NamedTuple(),1e-6,:ipopt)
    @test context!=s1_policy_context(case,NamedTuple(),1e-5,:ipopt)
    @test context!=s1_policy_context(case,NamedTuple(),1e-6,:madnlp)
    @test context!=s1_policy_context(s1_load(case,1.05),NamedTuple(),1e-6,:ipopt)
    @test context!=s1_policy_context(case,NamedTuple(),1e-6,:ipopt;droop_q_bounds=:implied)
    @test context!=s1_policy_context(case,NamedTuple(),1e-6,:ipopt;droop_q_formulation=:reduced)
    mktempdir() do out
        @test_throws ArgumentError s1_run_policy(out,"bad",case,s1_flat(case);total_iterations=0)
        good,r=s1_run_policy(out,"good",case,s1_flat(case))
        @test good["valid"] && length(good["attempts"])==1
        @test good["events"]==["accept"]
        @test validate_joint_design(case,r).valid
        limited,r=s1_run_policy(out,"limited-policy",case,s1_flat(case);total_iterations=2,attempt_iterations=1)
        @test !limited["valid"] && isnothing(r)
        @test length(limited["attempts"])==2
        @test limited["iterations"]<=2
        @test limited["events"][end]=="budget_exhausted"
        @test isfile(joinpath(out,"limited-policy-recovery-seed.json"))
        expired,r=s1_run_policy(out,"expired",case,s1_flat(case);total_seconds=1e-12)
        @test isempty(expired["attempts"]) && !expired["valid"] && isnothing(r)
        for solver in (:ipopt,:madnlp)
            stopped,_=s1_attempt(out,"deadline-$solver",case,s1_flat(case);solver,deadline_ns=UInt64(0))
            @test !stopped["valid"]
            @test stopped["iterations"]<=1
        end
    end
end
@testset "S1 MadNLP native reset adapter" begin
    function fixture()
        model=Model(MadNLP.Optimizer);set_silent(model)
        @variable(model,x>=0,start=1.5)
        @variable(model,0<=y<=2,start=.5)
        @NLconstraint(model,x^2+y>=4.)
        @objective(model,Min,x^2+3y)
        model
    end
    model=fixture();optimize!(model)
    seed=s1_policy_seed(model,"madfixture",:madnlp)
    target=fixture()
    @test_throws ArgumentError s1_apply_reset!(target,seed,"madfixture",:ipopt)
    @test_throws ArgumentError s1_apply_reset!(target,seed,"changed",:madnlp)
    bad=deepcopy(seed);bad["primal"][1]=NaN
    @test_throws ArgumentError s1_apply_reset!(target,bad,"madfixture",:madnlp)
    @test start_value.(all_variables(target))==[1.5,.5]
    s1_apply_reset!(target,seed,"madfixture",:madnlp)
    @test all(iszero,nonlinear_dual_start_value(target))
    for (k,v) in s1_reset_options(:madnlp);set_optimizer_attribute(target,k,v);end
    observations=[];set_optimizer_attribute(target,"intermediate_callback",S1MadInitialProbe(observations))
    optimize!(target)
    @test termination_status(target)==JuMP.MOI.LOCALLY_SOLVED
    @test objective_value(target)≈objective_value(model) atol=1e-6
    @test !isempty(observations)
    @test all(iszero,observations[1].y)
    @test all(isone,observations[1].zl) && all(isone,observations[1].zu)
end
