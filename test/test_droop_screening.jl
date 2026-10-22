# Solve-free synthetic checks for the opt-in response guard.
function p2_screen_fixture(;tight=false,mixed=false)
    net=ACNetwork([Bus(i;reference=i==1) for i in 1:3],
        [Branch(1,1,2;resistance=.01,reactance=.1,thermal_limit=2.),
         Branch(2,2,3;resistance=.01,reactance=.1,thermal_limit=2.),
         Branch(3,3,1;resistance=.01,reactance=.1,thermal_limit=2.)])
    gs=[Generator(i,i;p_min=0.,p_max=2.,q_min=-.5,q_max=tight && i==1 ? .07 : .8,initial_p=.2,initial_q=.05) for i in 1:3]
    ids=mixed ? (1:2) : (1:3)
    cs=[VoltVarDroop(VoltageSchedule(1.;v_db_low=.997,v_db_high=1.003),.04,.05,
        ReactiveCapability(p_min=0.,p_max=2.,q_min=gs[i].q_min,q_max=gs[i].q_max)) for i in ids]
    c=Case("p2-screen-fixture";base_power=100.,base_frequency=50.,network=net,generators=gs,
        loads=[Load(i,i;p=.2,q=.05) for i in 1:3],controls=cs,
        attachments=[GeneratorControlAttachment(i,i,RegulatedLocation(:bus,i)) for i in ids])
    c,ACState(ones(3),zeros(3),fill(.2,3),fill(.05,3))
end

@testset "Opt-in droop-response risk routing" begin
    c,b=p2_screen_fixture(tight=true)
    @test validate_equilibrium(c,b).valid
    old=filter_contingencies(c,b)
    new=filter_contingencies(c,b;droop_response_guard=true)
    @test all(d.action==:screened for d in old if d.device_kind==:line)
    @test all(d.action==:exact && d.reason==:droop_local_reserve_guard for d in new if d.device_kind==:line)
    @test all(d.action==:exact && d.reason==:generator_outage for d in new if d.device_kind==:generator)
    @test filter_contingencies(c,b;droop_response_guard=false)==old
    c,b=p2_screen_fixture()
    @test validate_equilibrium(c,b).valid
    old=filter_contingencies(c,b);new=filter_contingencies(c,b;droop_response_guard=true)
    @test new==old
    @test all(d.action==:exact for d in filter_contingencies(c,b;droop_response_guard=true,
        participation=Dict{Int,Float64}()) if d.device_kind==:line)
    c,b=p2_screen_fixture()
    controls=copy(c.controls)
    controls[1]=VoltVarDroop(controls[1].schedule,.04,.05,
        ReactiveCapability(p_min=0.,p_max=2.,q_min=-.5,q_max=.06))
    cap_case=Case(c.id;base_power=c.base_power,base_frequency=c.base_frequency,network=c.network,
        generators=c.generators,loads=c.loads,controls,attachments=c.attachments)
    @test all(d.reason==:droop_local_reserve_guard for d in
        filter_contingencies(cap_case,b;droop_response_guard=true) if d.device_kind==:line)
    c,b=p2_screen_fixture()
    catalog=contingency_catalog(c;include_generators=false)
    pipeline=assess_contingency_pipeline(c,b;catalog,droop_response_guard=true)
    @test pipeline.checks.complete
    @test pipeline.checks.screened_count==3
    @test !pipeline.checks.full_ac_coverage
    mktempdir() do dir
        first=run_contingency_campaign(dir,c,b;catalog,droop_response_guard=true)
        again=run_contingency_campaign(dir,c,b;catalog,droop_response_guard=true)
        @test first.evaluated_count==3
        @test again.resumed_count==3 && again.evaluated_count==0
        @test_throws ArgumentError run_contingency_campaign(dir,c,b;catalog,droop_response_guard=false)
    end
    c,b=p2_screen_fixture(mixed=true)
    @test validate_equilibrium(c,b).valid
    @test all(d.action==:exact && d.reason==:droop_guard_unsupported for d in
        filter_contingencies(c,b;droop_response_guard=true) if d.device_kind==:line)
end
