using JuMP
isdefined(@__MODULE__,:m72_case) || include(joinpath(@__DIR__,"..","examples","m7_2_case.jl"))
@testset "Apparent rating data and physical rejection" begin
    @test_throws ArgumentError Generator(1,1;p_min=0.,p_max=1.,q_min=-1.,q_max=1.,s_rated=0.)
    @test_throws ArgumentError Generator(1,1;p_min=0.,p_max=1.,q_min=-1.,q_max=1.,s_rated=Inf)
    g=Generator(1,1;p_min=0.,p_max=2.,q_min=-1.,q_max=1.,s_rated=1.)
    @test collect(reactive_limits(g,.8)) ≈ [-.6,.6]
    @test collect(reactive_limits(g,.6)) ≈ [-.8,.8]
    net=ACNetwork([Bus(1;reference=true)],Branch{Float64}[])
    make(q)=Case("circle";base_power=100.,base_frequency=50.,network=net,
        generators=[g],loads=[Load(1,1;p=.8,q=q)],controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    bad=ACState([1.],[0.],[.8],[.7])
    @test :generator_apparent_power in validate_equilibrium(make(.7),bad).violations
    a=[ReactiveControlAssignment(1,AVR(1.),RegulatedLocation(:bus,1))]
    for q in (-.6,.6)
        c=make(q);w=ACState([q>0 ? .98 : 1.02],[0.],[.8],[q])
        @test validate_equilibrium(c,w;reactive_assignments=a).valid
        for exact in (false,true)
            r=exact ? solve_opf_complementarity(c;reactive_assignments=a,initial_state=w) :
                solve_opf(c;reactive_assignments=a,initial_state=w,smooth_epsilon=1e-7)
            @test validate_equilibrium(c,r;reactive_assignments=a).valid
            @test hypot(r.state.pg[1],r.state.qg[1])<=1+1e-6
        end
    end
    @test_throws ArgumentError FeasibilityProblem(make(.4))
    prediction=DroopOPF._droop_screening_diagnostics(make(.4),bad,Contingency(:branch;branch_ids=[1]);
        participation=Dict(1=>1.),voltage_guard=.01,loading_threshold=.8,reactive_guard=.01)
    @test !prediction.safe
    @test prediction.reason==:apparent_capability_guard_unsupported
    c=make(.4);w=ACState([.98],[0.],[.8],[.4])
    @test :avr in validate_equilibrium(c,w;reactive_assignments=a).violations
    @test scenario_case(c,Contingency(:g;generator_ids=[1])).generators[1].s_rated==1.
    mktempdir() do d
        write_study(joinpath(d,"case.json"),Study(c;reactive_assignments=a))
        @test read_study(joinpath(d,"case.json")).case.generators[1].s_rated==1.
    end
end
@testset "Empty effective reactive interval is rejected without crashing" begin
    g=Generator(1,1;p_min=0.,p_max=1.,q_min=.65,q_max=1.,initial_q=.7,s_rated=1.)
    d=VoltVarDroop(VoltageSchedule(1.;v_db_low=1.,v_db_high=1.),.05,.8,
        ReactiveCapability(p_min=0.,p_max=1.,q_min=.65,q_max=1.))
    c=Case("empty-circle-interval";base_power=100.,base_frequency=50.,
        network=ACNetwork([Bus(1;reference=true)],Branch{Float64}[]),generators=[g],
        loads=[Load(1,1;p=.8,q=.7)],controls=[d],attachments=[GeneratorControlAttachment(1,1,RegulatedLocation(:bus,1))])
    report=validate_equilibrium(c,ACState([1.],[0.],[.8],[.7]))
    @test !report.valid
    @test :generator_apparent_power in report.violations
end
@testset "Shared AVR uses remaining circular capability" begin
    gs=[Generator(i,1;p_min=0.,p_max=1.,q_min=-1.,q_max=1.,s_rated=1.) for i in 1:2]
    c=Case("circular-sharing";base_power=100.,base_frequency=50.,
        network=ACNetwork([Bus(1;reference=true)],Branch{Float64}[]),generators=gs,
        loads=[Load(1,1;p=1.4,q=.7)],controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    a=[ReactiveControlAssignment(i,AVR(1.),RegulatedLocation(:bus,1)) for i in 1:2]
    @test validate_equilibrium(c,ACState([1.],[0.],[.8,.6],[.3,.4]);reactive_assignments=a).valid
    @test :avr_sharing in validate_equilibrium(c,ACState([1.],[0.],[.8,.6],[.2,.5]);reactive_assignments=a).violations
    studies=[Study(c;reactive_assignments=a)]
    shared=optimize_multi_period_security(studies;avr_bounds=Dict(1=>(.98,1.02),2=>(.99,1.01)))
    @test validate_multi_period_security(studies,shared).valid
    @test shared.avr_targets[1][1]===shared.avr_targets[1][2]
    held=optimize_multi_period_security(studies;avr_bounds=Dict(1=>(.98,1.02)))
    @test validate_multi_period_security(studies,held).valid
    @test held.avr_targets[1][1]==1.
    @test_throws ArgumentError optimize_multi_period_security(studies;avr_bounds=Dict(1=>(.98,.99),2=>(1.,1.02)))
end
@testset "Droop saturates against active-dependent headroom" begin
    for (p,q) in ((.8,.6),(.6,.8))
        g=Generator(1,1;p_min=0.,p_max=1.,q_min=-1.,q_max=1.,s_rated=1.)
        d=VoltVarDroop(VoltageSchedule(1.;v_db_low=1.,v_db_high=1.),.01,0.,
            ReactiveCapability(p_min=0.,p_max=1.,q_min=-1.,q_max=1.))
        c=Case("rated-droop";base_power=100.,base_frequency=50.,
            network=ACNetwork([Bus(1;reference=true)],Branch{Float64}[]),generators=[g],
            loads=[Load(1,1;p,q)],controls=[d],attachments=[GeneratorControlAttachment(1,1,RegulatedLocation(:bus,1))])
        w=ACState([.97],[0.],[p],[q])
        @test validate_equilibrium(c,w).valid
        @test droop_response(c,1,.97;p) ≈ q
        for exact in (false,true)
            r=exact ? solve_opf_complementarity(c;initial_state=w) : solve_opf(c;initial_state=w,smooth_epsilon=1e-7)
            @test validate_equilibrium(c,r).valid
        end
    end
end
@testset "Mixed design, time and outage coupling" begin
    c=m72_case();eligible=sort(c.generators;by=g->(-g.p_max,g.id));firstid=eligible[1].id
    setup=mixed_reactive_controls(c;avr_fraction=.5,
        ratings=Dict(g.id=>g.p_max/.95 for g in c.generators),voltage_targets=Dict(firstid=>1.))
    @test setup.avr_ids==[firstid]
    @test length(setup.droop_ids)==1
    @test_throws ArgumentError mixed_reactive_controls(c;ratings=Dict(),voltage_targets=Dict())
    c=setup.case;a=setup.assignments
    control=only(x.control_id for x in c.attachments if x.generator_id in setup.droop_ids)
    dc=[DroopControl(control;slope_bounds=(.5c.controls[control].slope,2c.controls[control].slope),v_ref_bounds=(.98,1.02))]
    cs=[DroopOPF._feasibility_scaled_case(c,f) for f in (.9,1.)]
    opts=Dict("tol"=>1e-9,"max_cpu_time"=>30.,"bound_relax_factor"=>0.)
    time=MultiPeriodStudy(cs;ramp_limits=Dict(g.id=>(.5,.5) for g in c.generators))
    m=optimize_multi_period(time;reactive_assignments=a,droop_controls=dc,optimizer_attributes=opts)
    @test validate_multi_period(time,m).valid
    @test length(m.droops)==1
    @test_throws ArgumentError optimize_multi_period(time;reactive_assignments=a,
        droop_controls=[DroopControl(only(x.control_id for x in c.attachments if x.generator_id==firstid))])
    # Parallel lines leave a connected outage with nontrivial response.
    studies=[Study(x;reactive_assignments=a,contingencies=[Contingency(:line11;branch_ids=[11])]) for x in cs]
    r=optimize_multi_period_security(studies;droop_controls=dc,optimizer_attributes=opts,
        ramp_limits=Dict(g.id=>(.5,.5) for g in c.generators))
    audit=validate_multi_period_security(studies,r)
    @test audit.valid
    @test length(audit.rows)==4
    mktempdir() do d
        path=joinpath(d,"result.json");write_multi_period_security(path,r)
        restored=read_multi_period_security(path)
        @test validate_multi_period_security(studies,restored).valid
        @test restored.droops==r.droops
    end
    frozenstudies=[DroopOPF._copy_study(s;case=begin
        cc=s.case
        for (id,setting) in r.droops;cc=with_droop_settings(Study(cc),id,setting).case;end
        cc
    end,reactive_assignments=r.periods[t].reactive_assignments) for (t,s) in enumerate(studies)]
    frozen=optimize_multi_period_security(frozenstudies;optimizer_attributes=opts,
        fixed_base_states=[p.states[:base] for p in r.periods],
        fixed_base_taps=[p.tap_settings[:base] for p in r.periods],
        fixed_base_shunts=[p.shunt_settings[:base] for p in r.periods])
    @test validate_multi_period_security(frozenstudies,frozen).valid
    damaged=deepcopy(r);damaged.periods[2].states[:line11].qg[1]+=.1
    @test !validate_multi_period_security(studies,damaged).valid
    scheduled=optimize_multi_period_security(studies;droop_controls=dc,optimizer_attributes=opts,
        avr_bounds=Dict(firstid=>(.98,1.02)),avr_movement_per_hour=.005)
    @test validate_multi_period_security(studies,scheduled).valid
    @test abs(scheduled.avr_targets[2][firstid]-scheduled.avr_targets[1][firstid])<=.005+1e-6
    # Exact S2 equality and emergency relief are a distinct, explicit contract.
    s2=optimize_multi_period_security(studies;response=:s2_proportional,s2_emergency=true,
        optimizer_attributes=opts)
    @test validate_multi_period_security(studies,s2).valid
    mktempdir() do d
        failed=deepcopy(s2);failed.periods[1].states[:base]=nothing
        failed.relief[1][:line11].dr[1]=NaN
        path=joinpath(d,"failed.json");write_multi_period_security(path,failed)
        restored=read_multi_period_security(path)
        @test isnothing(restored.periods[1].states[:base])
        @test isnan(restored.relief[1][:line11].dr[1])
        @test !validate_multi_period_security(studies,restored).valid
    end
    @test length(s2.stages)==3
    wrongstage=deepcopy(s2);st=wrongstage.stages[1]
    wrongstage.stages[1]=(;name=st.name,status=st.status,objective=-1.)
    @test !validate_multi_period_security(studies,wrongstage).valid
    corrupt=deepcopy(s2);corrupt.relief[1][:line11].shed[1]+=1.
    @test !validate_multi_period_security(studies,corrupt).valid
end
