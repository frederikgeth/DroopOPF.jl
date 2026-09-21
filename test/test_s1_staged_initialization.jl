using Test, DroopOPF, JuMP
isdefined(@__MODULE__,:m72_case) || include(joinpath(@__DIR__,"..","examples","m7_2_case.jl"))
isdefined(@__MODULE__,:s1_run_staged) || include(joinpath(@__DIR__,"..","examples","s1_staged_initialization.jl"))
@testset "S1 validated staged initialization and shared budgets" begin
    c=m72_case()
    p=(tap_controls=[TapControl(11;lower=.95,upper=1.05)],shunt_controls=[ShuntControl(201)],
        droop_controls=[DroopControl(2;slope_bounds=(.04,.1))])
    for fraction in (.2,.8)
        seeded=s1_reseed(c,p;fraction)
        held=s1_hold_controls(c,seeded)
        @test s1_stage_free_counts(c,held)==Dict("tap"=>0,"shunt"=>0,"droop"=>0)
        @test held.tap_controls[1].lower==seeded.tap_controls[1].initial
        @test held.shunt_controls[1].lower==seeded.shunt_controls[1].initial
        q=DroopOPF._joint_droop_policy(c,held.droop_controls[1])
        @test q.initial==DroopOPF._joint_droop_policy(c,seeded.droop_controls[1]).initial
        @test all(lo==hi for (lo,hi) in values(q.ranges))
        released=s1_hold_controls(c,seeded;equipment=false)
        @test released.tap_controls==seeded.tap_controls
        @test released.shunt_controls==seeded.shunt_controls
        @test s1_stage_free_counts(c,released)==Dict("tap"=>1,"shunt"=>1,"droop"=>0)
    end
    @test isnothing(s1_stage_seed(c,p,Dict("valid"=>false),nothing))
    mktempdir() do out
        @test_throws ArgumentError s1_run_staged(out,"bad",c,m5_initial_state(c);policies=p,strategy=:load)
        expired,r=s1_run_policy(out,"expired-outer",c,m5_initial_state(c);outer_deadline_ns=UInt64(0))
        @test isempty(expired["attempts"]) && isnothing(r)
        for strategy in (:release,:load)
            row,r=s1_run_staged(out,string(strategy),c,m5_initial_state(c);policies=p,strategy,factor=1.05)
            @test row["valid"]
            @test validate_joint_design(s1_load(c,1.05),r).valid
            @test !row["budget_exceeded"]["iterations"]
            @test row["iterations"]==sum(x["iterations"] for x in row["preparations"])+row["final"]["iterations"]
            @test [x["tags"]["load_factor"] for x in row["preparations"]]==(strategy==:release ? [1.05,1.05] : [1.,1.025])
            seed=s1_stage_seed(c,p,Dict("valid"=>true),r)
            @test seed.policies.tap_controls[1].lower==p.tap_controls[1].lower
            @test seed.policies.droop_controls[1].bounds==p.droop_controls[1].bounds
        end
        limited,r=s1_run_staged(out,"limited",c,m5_initial_state(c);policies=p,total_iterations=4)
        @test limited["iterations"]<=4
        @test !limited["valid"] && isnothing(r)
        @test length(limited["preparations"])==2
        @test all(!x["seed_transferred"] for x in limited["preparations"])
    end
end
