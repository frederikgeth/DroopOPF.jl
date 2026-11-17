using Test,DroopOPF
@testset "shared static equipment across demands and outages" begin
 buses=[Bus(1;reference=true),Bus(2),Bus(3)]
 branches=[Branch(1,1,2;resistance=.01,reactance=.2,thermal_limit=2.),Branch(2,2,3;resistance=.015,reactance=.15,thermal_limit=2.),Branch(3,3,1;resistance=.02,reactance=.2,thermal_limit=2.)]
 bank=ShuntBank(7,3;step_susceptances=[.2],legal_states=[[0],[1],[2]],state=[0])
 gs=[Generator(1,1;p_min=0.,p_max=1.,q_min=-2.,q_max=2.,initial_p=.3,initial_q=.15),Generator(2,2;p_min=0.,p_max=.4,q_min=-.3,q_max=.4,initial_p=.1,initial_q=.05,s_rated=.5)]
 c=Case("equipment";base_power=100.,base_frequency=50.,network=ACNetwork(buses,branches;banks=[bank]),loads=[Load(1,2;p=.3,q=.15),Load(2,3;p=.15,q=.1)],generators=gs,controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
 laws=[StaticReactiveLaw(1,:smooth_avr,1;v_ref=1.,projection_gain=200.,reactive_epsilon=2e-6),StaticReactiveLaw(2,:smooth_droop,2;q_ref=.05,gain=3.,v_ref=1.,deadband=0.,voltage_epsilon=1e-4,reactive_epsilon=3.5e-5)]
 off=[Branch(b.id,b.from_bus,b.to_bus;resistance=b.resistance,reactance=b.reactance,thermal_limit=b.thermal_limit,available=b.id!=1) for b in branches]
 oc=Case("outage";base_power=100.,base_frequency=50.,network=ACNetwork(buses,off;banks=[bank]),loads=c.loads,generators=gs,controls=c.controls,attachments=c.attachments)
 ws=[StaticWitness(c,laws;weight=.5),StaticWitness(oc,laws;anchor=1),StaticWitness(scale_case_loads(c,1.1),laws;weight=.5)]
 taps=[TapControl(1;lower=.95,upper=1.05)];banks=[ShuntControl(7;lower=0.,upper=.4,initial=.1)]
 bounds=Dict(1=>(;v_ref=(.95,1.05)),2=>(;gain=(1.5,6.),v_ref=(.95,1.05)))
 attrs=Dict("tol"=>1e-10,"constr_viol_tol"=>1e-10,"bound_relax_factor"=>0.,"max_iter"=>2000)
 r=optimize_static_witnesses(ws;design_bounds=bounds,tap_controls=taps,shunt_controls=banks,optimizer_attributes=attrs)
 @test validate_static_witnesses(ws,r;design_bounds=bounds,tap_controls=taps,shunt_controls=banks).valid
 @test .95<=r.taps[1]<=1.05
 @test 0<=r.susceptances[7]<=.4
 @test !validate_static_witnesses(ws,merge(r,(;taps=Dict(1=>1.2)));design_bounds=bounds,tap_controls=taps,shunt_controls=banks).valid
 @test !validate_static_witnesses(ws,merge(r,(;susceptances=Dict(7=>.5)));design_bounds=bounds,tap_controls=taps,shunt_controls=banks).valid
 @test !validate_static_witnesses(ws,merge(r,(;taps=Dict(1=>r.taps[1]+.005)));design_bounds=bounds,tap_controls=taps,shunt_controls=banks).valid
 @test !validate_static_witnesses(ws,merge(r,(;susceptances=Dict(7=>r.susceptances[7]+.01)));design_bounds=bounds,tap_controls=taps,shunt_controls=banks).valid
 @test !validate_static_witnesses(ws,r;design_bounds=bounds).valid
 @test_throws ArgumentError optimize_static_witnesses(ws;tap_controls=[taps;taps])
 @test_throws ArgumentError optimize_static_witnesses(ws;shunt_controls=[ShuntControl(99)])
 @test_throws ArgumentError optimize_static_witnesses(ws;shunt_controls=[ShuntControl(7;upper=.5)])
 # Fixed-equipment replay must still use the original equations after materialization.
 for (w,st) in zip(ws,r.states)
  frozen=with_shunt_settings(with_tap_settings(w.case,r.taps),r.susceptances)
  @test validate_equilibrium(frozen,st;reactive_assignments=[ReactiveControlAssignment(g.id,FreeQ()) for g in gs],power_tolerance=1e-8,limit_tolerance=1e-8).valid
  @test validate_static_reactive(frozen,st,laws;settings=r.parameters).valid
 end
 println("Joint objective ",r.objective," taps ",r.taps," bank ",r.susceptances)
end
