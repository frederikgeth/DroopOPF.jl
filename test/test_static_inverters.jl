using JuMP
import Ipopt

# Every numerical value here is a synthetic test assumption, not a rating claim.
function m11_plant(;kwargs...)
    defaults=(;generator_id=2,terminal_bus=2,poi_bus=1,mode=:gfl,priority=:active,
        q_control=:fixed_q,base_mva=50.0,terminal_base_kv=20.0,i_max=1.0,s_max=1.2,
        p_available=1.0,p_ref=0.8,q_ref=0.8,v_ref=1.0,q_droop=0.05,
        f_ref_hz=50.0,p_droop_hz=2.5,reactive_available=true)
    StaticInverter(;merge(defaults,(;kwargs...))...)
end
function m11_case(;system_base=100.0,online=true,rating=nothing)
    ratio=50.0/system_base
    Case("synthetic-inverter";base_power=system_base,base_frequency=50.0,
        network=ACNetwork([Bus(1;reference=true,v_min=.9,v_max=1.1),Bus(2;v_min=.9,v_max=1.1)],
            [Branch(1,1,2;resistance=.01,reactance=.05,thermal_limit=3.0*100/system_base)]),
        loads=[Load(1,1;p=1.0*100/system_base,q=.3*100/system_base)],
        generators=[Generator(1,1;p_min=0.0,p_max=3.0*100/system_base,
                q_min=-2.0*100/system_base,q_max=2.0*100/system_base,initial_p=1.0*100/system_base),
            Generator(2,2;available=online,p_min=-ratio,p_max=2ratio,q_min=-2ratio,q_max=2ratio,
                initial_p=.4*100/system_base,s_rated=rating)],
        controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
end

@testset "M11 declarations, bases and identity rejection" begin
    c=m11_case();p=m11_plant();r=inverter_response(c,p,1.0)
    @test r.p≈.4
    @test r.q≈.3
    @test r.current_plant≈1.0
    @test r.current_base_ka≈50/(sqrt(3)*20)
    @test model_data(p)["priority"]=="active"
    @test model_data(p)["terminal_bus"]==2
    @test model_data(p)["poi_bus"]==1
    for kwargs in ((;base_mva=0.0),(;terminal_base_kv=Inf),(;i_max=-1.0),
        (;s_max=NaN),(;p_available=-.1),(;priority=:radial),(;mode=:unknown),
        (;q_control=:unknown),(;q_droop=0.0),(;p_droop_hz=0.0),(;voltage_deadband=-.01),
        (;p_ref=Inf),(;generator_id=0))
        @test_throws ArgumentError m11_plant(;kwargs...)
    end
    @test_throws ArgumentError m11_plant(mode=:gfm)
    @test_throws ArgumentError m11_plant(mode=:gfm,q_control=:volt_var,regulated_bus=1)
    for plant in (m11_plant(generator_id=99),m11_plant(terminal_bus=1),m11_plant(poi_bus=99))
        @test_throws ArgumentError inverter_response(c,plant,1.0)
    end
    for v in (0.,-.1,NaN,Inf)
        @test_throws ArgumentError inverter_response(c,p,v)
    end
    @test_throws ArgumentError inverter_response(c,p,1.;frequency_hz=0.)
    # Changing only the system base preserves physical MW/MVAr/current.
    r2=inverter_response(m11_case(system_base=200.),p,1.)
    @test r2.p*200≈r.p*100
    @test r2.q*200≈r.q*100
    @test r2.current_plant≈r.current_plant
end

@testset "M11 analytic priority, saturation and zero-output regimes" begin
    c=m11_case()
    a=inverter_response(c,m11_plant(),1.)
    b=inverter_response(c,m11_plant(priority=:reactive),1.)
    @test [a.p,a.q]≈[.4,.3]
    @test [b.p,b.q]≈[.3,.4]
    @test a.q_limited && !a.p_limited
    @test b.p_limited && !b.q_limited
    @test inverter_response(c,m11_plant(),.8).q≈0.0 atol=1e-8
    # MVA cap remains active at high terminal voltage.
    @test inverter_response(c,m11_plant(p_ref=2.,q_ref=2.,i_max=2.),1.).p≈.5
    cap=inverter_response(c,m11_plant(p_ref=2.,q_ref=2.,i_max=2.,p_available=2.),1.)
    @test cap.p≈.6
    @test cap.q≈0.0 atol=1e-8
    rated=inverter_response(m11_case(rating=.45),m11_plant(),1.)
    @test hypot(rated.p,rated.q)≈.45
    # Active availability and Q availability are independent declarations.
    @test inverter_response(c,m11_plant(p_available=0.),1.).q≈.4
    zero=inverter_response(c,m11_plant(p_available=0.,reactive_available=false),1.)
    @test zero.p==zero.q==0.0
    offline=inverter_response(c,m11_plant(available=false),1.)
    @test offline.p==offline.q==0.0
    @test !offline.online
    @test !inverter_response(m11_case(online=false),m11_plant(),1.).online
    @test inverter_response(c,m11_plant(p_ref=-.8,q_ref=-.8),1.).q≈-.3
    @test inverter_response(c,m11_plant(p_ref=-.8,q_ref=-.8,priority=:reactive),1.).p≈-.3
    # Exact transition from unsaturated to current-limited Q.
    for q in (.6-1e-7,.6,.6+1e-7)
        t=inverter_response(c,m11_plant(q_ref=q),1.)
        @test t.q≈.5min(q,.6) atol=1e-12
    end
    # Dense independent feasibility check over signs, priorities and voltages.
    for priority in (:active,:reactive),v in (.2,.8,1.,1.3),pr in (-2.,0.,.3,2.),qr in (-2.,0.,.3,2.)
        t=inverter_response(c,m11_plant(priority=priority,p_ref=pr,q_ref=qr),v)
        @test t.p_plant^2+t.q_plant^2<=min(1.2^2,v^2)+1e-12
        @test -1-1e-12<=t.p_plant<=1+1e-12
        @test abs(t.q_plant)<=2+1e-12
    end
end

@testset "M11 GFL Volt/VAR and GFM steady droop" begin
    c=m11_case()
    plant=m11_plant(mode=:gfm,q_control=:volt_var,q_ref=0.,p_ref=.4,i_max=2.,s_max=2.)
    @test inverter_response(c,plant,1.;frequency_hz=49.5).p≈.3
    @test inverter_response(c,plant,1.;frequency_hz=50.5).p≈.1
    @test inverter_response(c,plant,.99).q≈.1
    @test inverter_response(c,plant,1.01).q≈-.1
    db=m11_plant(q_control=:volt_var,q_ref=0.,voltage_deadband=.01)
    @test inverter_response(c,db,1.005).q==0.
    @test inverter_response(c,db,.98).q≈.1
    # GFL sensing at POI differs from terminal current limiting.
    remote=m11_plant(q_control=:volt_var,q_ref=0.,regulated_bus=1)
    @test inverter_response(c,remote,1.;regulated_voltage=.99).q≈.1
    @test inverter_response(c,m11_plant(),1.;frequency_hz=49.5).p≈.4
end

@testset "M11 independent replay detects forged static witnesses" begin
    c=m11_case();p=m11_plant();r=inverter_response(c,p,1.)
    s=ACState([1.,1.],[0.,0.],[.6,r.p],[0.,r.q])
    @test validate_static_inverters(c,s,[p]).valid
    s.qg[2]+=.01
    @test !validate_static_inverters(c,s,[p]).valid
    s.qg[2]=1.
    @test only(validate_static_inverters(c,s,[p]).rows).current_margin<0
    s.vm[2]=NaN
    @test !validate_static_inverters(c,s,[p]).valid
    @test_throws ArgumentError validate_static_inverters(c,s,[p,p])
    @test_throws ArgumentError validate_static_inverters(c,s,[p];tolerance=-1.)
end

@testset "M11 constrained AC solve and independent network replay" begin
    c=m11_case()
    opts=Dict("tol"=>1e-9,"max_iter"=>2000,"bound_relax_factor"=>0.)
    for p in (m11_plant(),m11_plant(q_ref=.2),m11_plant(priority=:reactive),
        m11_plant(q_control=:volt_var,q_ref=0.,p_ref=.4),
        m11_plant(mode=:gfm,q_control=:volt_var,p_ref=.4,q_ref=0.),
        m11_plant(p_available=0.,q_ref=.3),m11_plant(available=false))
        result=solve_inverter_opf(c,[p];optimizer_attributes=opts)
        report=validate_inverter_opf(c,result)
        @test report.converged
        @test report.ac.valid
        @test report.inverters.valid
        @test report.valid
        state=result.opf.state
        # Independent complex-power current calculation on physical MVA base.
        V=state.vm[2]*cis(state.va[2]);S=(state.pg[2]+im*state.qg[2])*100/50
        @test abs(conj(S/V))<=p.i_max+1e-6
        @test hypot(state.pg[2],state.qg[2])*100/50<=p.s_max+1e-6
        @test maximum(abs,power_balance(c,state).active)<=1e-6
        point=materialize_operating_point(c,result)
        @test point.source_context["inverters"][1]["generator_id"]==2
        @test point.source_context["dynamic_qualification"]=="not_assessed"
        corrupt=deepcopy(result);corrupt.opf.state.pg[2]+=.01
        @test !validate_inverter_opf(c,corrupt).valid
        @test_throws ArgumentError materialize_operating_point(c,corrupt)
    end
    # Disconnected inverter inherits the existing source availability flag.
    result=solve_inverter_opf(m11_case(online=false),[m11_plant()];optimizer_attributes=opts)
    @test validate_inverter_opf(m11_case(online=false),result).valid
end

@testset "M11 model-composition and unsupported-contract guards" begin
    c=m11_case();p=m11_plant()
    build()=DroopOPF._build_acopf_model(c;voltage_epsilon=1e-4,
        reactive_relative_epsilon=1e-4,reactive_epsilon=nothing,silent=true)
    model,vars=build()
    add_static_inverter_constraints!(model,c,vars,[p])
    @test model.ext[:static_inverter_generator_ids]==Set([2])
    @test_throws ArgumentError add_static_inverter_constraints!(model,c,vars,[p])
    model2,vars2=build()
    @test_throws ArgumentError add_static_inverter_constraints!(model2,c,vars2,[p,p])
    @test_throws ArgumentError add_static_inverter_constraints!(model2,c,
        (vm=vars2.vm,pg=vars2.pg[1:1],qg=vars2.qg),[p])
    set_lower_bound(vars2.vm[2],0.)
    @test_throws ArgumentError add_static_inverter_constraints!(model2,c,vars2,[p])
    net=ACNetwork(c.network.buses,Branch{Float64}[])
    island=Case("isolated-inverter";base_power=100.,base_frequency=50.,network=net,
        generators=c.generators,loads=c.loads,controls=c.controls,attachments=c.attachments)
    @test_throws ArgumentError inverter_response(island,p,1.)
    # Positive minimum generation is not silently relaxed to accommodate curtailment.
    positive=Generator(2,2;p_min=.1,p_max=1.,q_min=-1.,q_max=1.,initial_p=.4)
    boxed=Case("positive-minimum";base_power=100.,base_frequency=50.,network=c.network,
        generators=[c.generators[1],positive],loads=c.loads,controls=c.controls,attachments=c.attachments)
    @test_throws ArgumentError inverter_response(boxed,p,1.)
    curve=VoltVarDroop(VoltageSchedule(1.),.05,0.,ReactiveCapability(p_min=0.,p_max=1.,q_min=-1.,q_max=1.))
    attached=Case("duplicate-law";base_power=100.,base_frequency=50.,network=c.network,
        generators=c.generators,loads=c.loads,controls=[curve],
        attachments=[GeneratorControlAttachment(2,1,RegulatedLocation(:bus,2))])
    @test_throws ArgumentError solve_inverter_opf(attached,[p])
    # Nonconverged results cannot materialize an otherwise exact equilibrium.
    valid=solve_inverter_opf(c,[m11_plant(q_ref=.2)])
    opf=valid.opf
    fake=StaticInverterOPFResult(ACOPFResult(opf.state,opf.objective,:ITERATION_LIMIT,
        opf.primal_status,opf.smooth_epsilon,opf.smooth_reactive_relative_epsilon,opf.smooth_reactive_epsilon),
        valid.plants,valid.frequency_hz)
    @test !validate_inverter_opf(c,fake).valid
    @test_throws ArgumentError materialize_operating_point(c,fake)
end

@testset "M11 fixed-voltage algebraic formulation cross-check" begin
    c=m11_case()
    for (priority,expected) in ((:active,[.4,.3]),(:reactive,[.3,.4]))
        model=Model(Ipopt.Optimizer);set_silent(model)
        @variable(model,vm[1:2]);@variable(model,pg[1:2]);@variable(model,qg[1:2])
        fix.(vm,1.;force=true);fix(pg[1],0.;force=true);fix(qg[1],0.;force=true)
        add_static_inverter_constraints!(model,c,(;vm,pg,qg),[m11_plant(priority=priority)])
        @objective(model,Min,0.)
        optimize!(model)
        @test termination_status(model)==JuMP.MOI.LOCALLY_SOLVED
        @test [value(pg[2]),value(qg[2])]≈expected atol=1e-7
    end
    p=m11_plant(mode=:gfm,q_control=:volt_var,p_ref=.4,q_ref=0.)
    r=solve_inverter_opf(c,[p];frequency_hz=49.5)
    @test validate_inverter_opf(c,r).valid
    @test r.opf.state.pg[2]≈.3 atol=1e-6
end

@testset "Fixed-frequency Q–V study policy" begin
    c=m11_case()
    function qvplant(;kwargs...)
        qv_inverter(;generator_id=2,terminal_bus=2,mode=:gfm,priority=:active,
            base_mva=50.,terminal_base_kv=20.,i_max=2.,s_max=1.,
            p_available=1.,p_ref=.8,q_ref=0.,v_ref=1.,q_droop=.05,
            reactive_available=true,kwargs...)
    end
    p=qvplant()
    @test !p.frequency_response
    @test p.q_cap_fraction==.395
    a=inverter_response(c,p,.95)
    @test a.q≈.5*.395
    @test inverter_response(c,p,1.05).q≈-.5*.395
    @test inverter_response(c,p,.95;frequency_hz=49.).p≈a.p
    @test inverter_response(c,qvplant(q_cap_fraction=.2),.95).q≈.1
    @test inverter_response(m11_case(rating=.45),p,.95).q≈.5*.395*.9
    # Voltage-dependent current capability remains tighter than the Q ceiling.
    @test inverter_response(c,p,.4).q≈0 atol=1e-8
    @test model_data(p)["frequency_response"]==false
    @test model_data(p)["q_cap_fraction"]==.395
    @test_throws ArgumentError qvplant(q_cap_fraction=-.1)
    @test_throws ArgumentError qvplant(q_cap_fraction=Inf)
    @test_throws ArgumentError qvplant(frequency_response=true)
    clone(p;kw...)=StaticInverter(;merge((; (k=>getfield(p,k) for k in fieldnames(StaticInverter))...), (;kw...))...)
    charging=clone(p;p_ref=-.8)
    @test inverter_response(c,charging,.95).p≈-.4
    @test inverter_response(c,charging,.95).q≈.1975
    highp=clone(p;p_ref=.99)
    @test inverter_response(c,highp,.95).q≈.5sqrt(1-.99^2)
    @test inverter_response(c,clone(p;mode=:gfl),.95).q≈a.q
    @test inverter_response(c,clone(p;reactive_available=false),.95).q==0
    # A tighter asymmetric supplied Q interval is never widened.
    c.generators[2]=Generator(2,2;p_min=-.5,p_max=1.,q_min=-.05,q_max=.1)
    @test inverter_response(c,p,.95).q≈.1
    @test inverter_response(c,p,1.05).q≈-.05
    for plant in (p,charging,clone(p;priority=:reactive))
        result=solve_inverter_opf(c,[plant])
        @test validate_inverter_opf(c,result).valid
        result.opf.state.qg[2]+=.02
        @test !validate_inverter_opf(c,result).valid
    end
end
