using Test,DroopOPF
@testset "explicit static reactive laws" begin
 g=Generator(1,1;p_min=0.,p_max=1.,q_min=-.3,q_max=.4,initial_p=.2,initial_q=.05,s_rated=.7)
 for mode in (:droop,:statcom)
  l=StaticReactiveLaw(1,mode,1;current_limit=.5,q_ref=.05,gain=3.,v_ref=1.,deadband=.005)
  for v in [.8,.99,1.,1.01,1.2],p in [.1,.3,.5]
   cap=sqrt(max(min(.7^2,(.5v)^2)-p^2,0.));desired=.05-3(max(v-1-.005,0)-max(1-v-.005,0))
   @test static_reactive_output(g,l,p,0.,v,v)≈min(min(.4,cap),max(max(-.3,-cap),desired)) atol=1e-12
  end
 end
 pf=StaticReactiveLaw(1,:fixed_pf,1;q_over_p=-.5);@test static_reactive_output(g,pf,.4,0.,1.,1.)≈-.2
 fixed=StaticReactiveLaw(1,:fixed_q,1;q_ref=.4);@test static_reactive_output(g,fixed,.69,0.,1.,1.)==.4
 svc=StaticReactiveLaw(1,:svc,1;b_ref=.05,b_min=-.1,b_max=.1,gain=2.,v_ref=1.,deadband=0.)
 @test static_reactive_output(g,svc,0.,0.,.8,.8)≈.064
 avr=StaticReactiveLaw(1,:avr,1;v_ref=1.);@test static_reactive_output(g,avr,.2,.4,.9,.9)==.4
 for extrap in (:clamp,:linear)
  piece=StaticReactiveLaw(1,:piecewise,1;voltages=[.9,1.,1.1],reactive=[.3,.05,-.2],extrapolation=extrap)
  @test static_reactive_output(g,piece,.2,0.,1.,1.)≈.05
 end
 @test_throws ArgumentError StaticReactiveLaw(1,:statcom,1;q_ref=0.,gain=1.,v_ref=1.,deadband=0.)
 @test_throws ArgumentError StaticReactiveLaw(1,:droop,1;q_ref=0.,gain=1.,v_ref=1.,deadband=0.,extra=2.)
end
function fixture(qmax=.4)
 buses=[Bus(1;reference=true),Bus(2),Bus(3)]
 branches=[Branch(1,1,2;resistance=.01,reactance=.2,thermal_limit=2.),Branch(2,2,3;resistance=.015,reactance=.15,thermal_limit=2.),Branch(3,3,1;resistance=.02,reactance=.2,thermal_limit=2.)]
 gs=[Generator(1,1;p_min=-1.,p_max=1.,q_min=-2.,q_max=2.,initial_p=.3,initial_q=.15),Generator(2,2;p_min=0.,p_max=.4,q_min=-.3,q_max=qmax,initial_p=.1,initial_q=.05,s_rated=.5)]
 Case("static-witness-test";base_power=100.,base_frequency=50.,network=ACNetwork(buses,branches),loads=[Load(1,2;p=.3,q=.15),Load(2,3;p=.15,q=.1)],generators=gs,controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
end
@testset "heterogeneous coupled native operating and Q witnesses" begin
 laws=[StaticReactiveLaw(1,:avr,1;v_ref=1.),StaticReactiveLaw(2,:droop,2;current_limit=.35,q_ref=.05,gain=3.,v_ref=1.,deadband=.005)]
 c=fixture();d=fixture(.3);ws=[StaticWitness(c,laws;weight=.5),StaticWitness(d,laws;weight=.5),StaticWitness(c,laws;anchor=1,test_bus=3,test_q=-.01),StaticWitness(d,laws;anchor=2,test_bus=3,test_q=.01)]
 bounds=Dict(2=>(;gain=(1.5,6.),v_ref=(.99,1.01)))
 result=optimize_static_witnesses(ws;design_bounds=bounds,optimizer_attributes=Dict("tol"=>1e-9,"bound_relax_factor"=>0.,"hessian_approximation"=>"limited-memory","max_iter"=>1500))
 println(result.termination_status)
 report=validate_static_witnesses(ws,result;design_bounds=bounds)
 @test report.valid
 @test all(r.valid for r in report.rows)
 bad=merge(result,(;signals=[0.,0.,.1,result.signals[4]]));@test !validate_static_witnesses(ws,bad;design_bounds=bounds).valid
 @test_throws ArgumentError StaticWitness(c,laws;test_bus=3,test_q=.01)
 @test_throws ArgumentError optimize_static_witnesses([StaticWitness(c,laws;anchor=1)])
 @test_throws ArgumentError optimize_static_witnesses([ws[1],StaticWitness(d,laws;anchor=1)])
 @test all(w.case.loads==c.loads for w in ws)
end
@testset "smooth static witnesses match native softplus controls" begin
 c=fixture();g=c.generators[2];d=VoltVarDroop(VoltageSchedule(1.),1/3,.05,ReactiveCapability(p_min=g.p_min,p_max=g.p_max,q_min=g.q_min,q_max=g.q_max));width=reactive_smoothing_epsilon(d,1e-4)
 laws=[StaticReactiveLaw(1,:smooth_avr,1;v_ref=1.,projection_gain=200.,reactive_epsilon=2e-6),StaticReactiveLaw(2,:smooth_droop,2;q_ref=.05,gain=3.,v_ref=1.,deadband=0.,voltage_epsilon=1e-4,reactive_epsilon=width)]
 for p in [0.,.2,.4],v in [.8,.95,.9999,1.,1.0001,1.05,1.2]
  @test static_reactive_output(g,laws[2],p,0.,v,v)≈DroopOPF._smooth_capability_droop_value(d,v,p,g,1e-4,width) atol=1e-12
 end
 attrs=Dict("tol"=>1e-9,"bound_relax_factor"=>0.,"max_iter"=>1500,"hessian_approximation"=>"limited-memory")
 ws=[StaticWitness(c,laws;weight=1.),StaticWitness(c,laws;anchor=1,test_bus=3,test_q=.01)]
 result=optimize_static_witnesses(ws;optimizer_attributes=attrs);@test validate_static_witnesses(ws,result).valid
 assignments=[ReactiveControlAssignment(1,AVR(1.),RegulatedLocation(:bus,1)),ReactiveControlAssignment(2,d,RegulatedLocation(:bus,2))]
 legacy=solve_opf(c;reactive_assignments=assignments,smooth_epsilon=1e-4,optimizer_attributes=attrs)
 @test legacy.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED)
 @test validate_static_reactive(c,legacy.state,laws).valid
 @test validate_equilibrium(c,result.states[1];reactive_assignments=assignments,smooth_epsilon=1e-4,power_tolerance=1e-8,droop_tolerance=1e-8,limit_tolerance=1e-8).valid
 @test_throws ArgumentError StaticReactiveLaw(2,:smooth_droop,2;q_ref=.05,gain=3.,v_ref=1.,deadband=0.,voltage_epsilon=1e-4,reactive_epsilon=0.)
end

@testset "shared AVR targets and IBR curves" begin
 c=fixture();laws=[StaticReactiveLaw(1,:smooth_avr,1;v_ref=1.,projection_gain=200.,reactive_epsilon=2e-6),StaticReactiveLaw(2,:smooth_droop,2;q_ref=.05,gain=3.,v_ref=1.,deadband=0.,voltage_epsilon=1e-4,reactive_epsilon=3.5e-5)]
 ws=[StaticWitness(c,laws;weight=1.),StaticWitness(c,laws;anchor=1,test_bus=3,test_q=.01)]
 bounds=Dict(1=>(;v_ref=(.99,1.01)),2=>(;gain=(1.5,6.),v_ref=(.99,1.01)))
 result=optimize_static_witnesses(ws;design_bounds=bounds,optimizer_attributes=Dict("tol"=>1e-9,"bound_relax_factor"=>0.,"hessian_approximation"=>"limited-memory"))
 @test validate_static_witnesses(ws,result;design_bounds=bounds).valid
 @test keys(result.parameters[1])==(:v_ref,)
 @test .99<=result.parameters[1].v_ref<=1.01
 @test all(validate_static_reactive(c,st,laws;settings=result.parameters).valid for st in result.states)
 bad=copy(result.parameters);bad[1]=(;v_ref=1.02);@test !validate_static_witnesses(ws,merge(result,(;parameters=bad));design_bounds=bounds).valid
 bad=copy(result.parameters);bad[1]=(;v_ref=1.,gain=200.);@test !validate_static_witnesses(ws,merge(result,(;parameters=bad));design_bounds=bounds).valid
 @test_throws ArgumentError optimize_static_witnesses(ws;design_bounds=Dict(1=>(;gain=(1.,2.),v_ref=(.99,1.01))))
 @test_throws ArgumentError optimize_static_witnesses(ws;design_bounds=Dict(2=>(;v_ref=(.99,1.01))))
end
