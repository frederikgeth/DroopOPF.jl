using JuMP
import Ipopt
function frequency_test_case(;load=1.2,pmax1=2.,pmax2=2.)
 Case("frequency-test";base_power=100.,base_frequency=50.,
  network=ACNetwork([Bus(1;reference=true,v_min=.95,v_max=1.05)],Branch{Float64}[]),
  loads=[Load(1,1;p=load,q=0.)],
  generators=[Generator(1,1;p_min=0.,p_max=pmax1,q_min=-1.,q_max=1.,initial_p=.5),
   Generator(2,1;p_min=0.,p_max=pmax2,q_min=-1.,q_max=1.,initial_p=.5)],
  controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
end
frequency_laws()=[GeneratorFrequencyResponse(generator_id=i,p_ref=.5,gain_pu_per_hz=i==1 ? .4 : .6,f_ref_hz=50.) for i in 1:2]
@testset "Common frequency analytical balance and saturation" begin
 for (load,max1,expected_f,expected_p) in ((1.2,2.,49.8,[.58,.62]),(1.4,.55,50-.35/.6,[.55,.85]),(.8,2.,50.2,[.42,.38]))
  c=frequency_test_case(;load,pmax1=max1)
  r=solve_common_frequency(c,StaticInverter[],frequency_laws();frequency_bounds=(48.,52.))
  report=validate_common_frequency(c,r)
  @test report.valid
  @test report.frequency_sensitive
  @test r.frequency_hz≈expected_f atol=1e-6
  @test r.opf.state.pg≈expected_p atol=1e-6
  @test materialize_operating_point(c,r).source_context["frequency_hz"]==r.frequency_hz
  corrupt=CommonFrequencyResult(r.opf,r.plants,r.responses,r.frequency_hz+.1,r.frequency_bounds,r.branch_angle_bounds)
  @test !validate_common_frequency(c,corrupt).valid
 end
 c=frequency_test_case(load=1.2,pmax1=.55,pmax2=.65)
 r=solve_common_frequency(c,StaticInverter[],frequency_laws();frequency_bounds=(48.,49.))
 @test validate_common_frequency(c,r).valid
 @test !validate_common_frequency(c,r).frequency_sensitive
end
@testset "Common frequency inverter coupling and input coverage" begin
 c=frequency_test_case()
 p=StaticInverter(generator_id=2,terminal_bus=1,mode=:gfm,priority=:active,q_control=:volt_var,
  base_mva=50.,terminal_base_kv=20.,i_max=3.,s_max=3.,p_available=3.,p_ref=1.,q_ref=0.,
  v_ref=1.,q_droop=.05,f_ref_hz=50.,p_droop_hz=1.,reactive_available=true)
 law=GeneratorFrequencyResponse(generator_id=1,p_ref=.5,gain_pu_per_hz=.5,f_ref_hz=50.)
 for priority in (:active,:reactive)
  plant=StaticInverter(;merge((; (k=>getfield(p,k) for k in fieldnames(StaticInverter))...),(;priority))...)
  r=solve_common_frequency(c,[plant],[law];frequency_bounds=(48.,52.))
  @test validate_common_frequency(c,r).valid
  @test r.frequency_hz≈49.8 atol=1e-5
  @test r.opf.state.pg≈[.6,.6] atol=1e-5
 end
 @test_throws ArgumentError solve_common_frequency(c,[p],GeneratorFrequencyResponse[];frequency_bounds=(48.,52.))
 @test_throws ArgumentError solve_common_frequency(c,[p],frequency_laws();frequency_bounds=(48.,52.))
 for bounds in ((0.,52.),(52.,48.),(48.,Inf),(NaN,52.))
  @test_throws ArgumentError solve_common_frequency(c,[p],[law];frequency_bounds=bounds)
 end
 for bad in (-1.,Inf,NaN)
  @test_throws ArgumentError GeneratorFrequencyResponse(generator_id=1,p_ref=.5,gain_pu_per_hz=bad,f_ref_hz=50.)
 end
 held=[GeneratorFrequencyResponse(generator_id=i,p_ref=.6,gain_pu_per_hz=0.,f_ref_hz=50.) for i in 1:2]
 @test_throws ArgumentError solve_common_frequency(c,StaticInverter[],held;frequency_bounds=(48.,52.))
 r=solve_common_frequency(c,StaticInverter[],frequency_laws();frequency_bounds=(49.9,50.1))
 @test !validate_common_frequency(c,r).valid
 @test_throws ArgumentError solve_common_frequency(c,StaticInverter[],frequency_laws();frequency_bounds=(48.,52.),branch_angle_bounds=Dict(99=>(-.1,.1)))
end
@testset "Common frequency network, outages and composition guards" begin
 c=m11_case();p=m11_plant(mode=:gfm,q_control=:volt_var,q_ref=.2)
 law=GeneratorFrequencyResponse(generator_id=1,p_ref=.6,gain_pu_per_hz=.4,f_ref_hz=50.)
 bounds=Dict(1=>(-.4,.4))
 r=solve_common_frequency(c,[p],[law];frequency_bounds=(48.,52.),branch_angle_bounds=bounds)
 @test validate_common_frequency(c,r).valid
 @test abs(r.frequency_hz-50.)>1e-5 # Includes actual AC losses.
 @test abs(sum(r.opf.state.pg)-sum(l.p for l in c.loads))>1e-5
 changed=CommonFrequencyResult(r.opf,r.plants,r.responses,r.frequency_hz,r.frequency_bounds,Dict(1=>(.2,.3)))
 @test !validate_common_frequency(c,changed).angles_valid
 outage=scenario_case(c,Contingency(:unit_off;generator_ids=[2]))
 ro=solve_common_frequency(outage,[p],[law];frequency_bounds=(48.,52.))
 @test validate_common_frequency(outage,ro).valid
 @test abs(ro.opf.state.pg[2])<1e-8
 @test abs(ro.opf.state.qg[2])<1e-8
 disconnected=Case("islands";base_power=c.base_power,base_frequency=c.base_frequency,
  network=ACNetwork(c.network.buses,Branch{Float64}[]),loads=c.loads,generators=c.generators,
  controls=c.controls,attachments=c.attachments)
 @test_throws ArgumentError solve_common_frequency(disconnected,[p],[law];frequency_bounds=(48.,52.))
 for badbounds in ((48.,),(48.,50.,52.))
  @test_throws ArgumentError solve_common_frequency(c,[p],[law];frequency_bounds=badbounds)
 end
 m=Model();vm=@variable(m,[1:2],lower_bound=.9,upper_bound=1.1)
 pg=@variable(m,[1:2]);qg=@variable(m,[1:2]);v=(;vm,pg,qg)
 other=Model();foreign=@variable(other,48<=foreign_f<=52)
 @test_throws ArgumentError add_static_inverter_constraints!(m,c,v,[p];frequency_hz=foreign)
 f=@variable(m)
 @test_throws ArgumentError add_static_inverter_constraints!(m,c,v,[p];frequency_hz=f)
 fix(f,0.)
 @test_throws ArgumentError add_static_inverter_constraints!(m,c,v,[p];frequency_hz=f)
end

@testset "Frequency initialization is numerical only" begin
 c=frequency_test_case()
 for start in (48.,50.,52.)
  r=solve_common_frequency(c,StaticInverter[],frequency_laws();frequency_bounds=(48.,52.),initial_frequency_hz=start)
  @test validate_common_frequency(c,r).valid
  @test r.frequency_hz≈49.8 atol=1e-6
 end
 @test_throws ArgumentError solve_common_frequency(c,StaticInverter[],frequency_laws();frequency_bounds=(48.,52.),initial_frequency_hz=NaN)
end
@testset "Effective active capability bounds" begin
 c=frequency_test_case(load=1.4)
 gens=[Generator(1,1;p_min=0.,p_max=2.,q_min=-1.,q_max=1.,initial_p=.5,s_rated=.55),c.generators[2]]
 rated=Case("rated-frequency";base_power=c.base_power,base_frequency=c.base_frequency,
  network=c.network,loads=c.loads,generators=gens,controls=c.controls,attachments=c.attachments)
 r=solve_common_frequency(rated,StaticInverter[],frequency_laws();frequency_bounds=(48.,52.))
 @test validate_common_frequency(rated,r).valid
 @test r.opf.state.pg≈[.55,.85] atol=1e-6
 @test r.frequency_hz≈50-.35/.6 atol=1e-6
end

@testset "Invalid voltage cannot enter response sensitivity" begin
 c=m11_case();p=m11_plant(mode=:gfm,q_control=:volt_var,q_ref=.2)
 law=GeneratorFrequencyResponse(generator_id=1,p_ref=.6,gain_pu_per_hz=.4,f_ref_hz=50.)
 r=solve_common_frequency(c,[p],[law];frequency_bounds=(48.,52.))
 for voltage in (0.,-1.)
  st=deepcopy(r.opf.state);st.vm[2]=voltage # Deliberately corrupt a stored witness after construction.
  opf=ACOPFResult{Float64}(st,r.opf.objective,r.opf.termination_status,r.opf.primal_status,1e-4,1e-4,nothing)
  corrupt=CommonFrequencyResult(opf,r.plants,r.responses,r.frequency_hz,r.frequency_bounds,r.branch_angle_bounds)
  @test !validate_common_frequency(c,corrupt).valid
 end
end
