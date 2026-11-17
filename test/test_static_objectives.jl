@testset "static objective policies and lexicographic limits" begin
 c=fixture();laws=[StaticReactiveLaw(1,:smooth_avr,1;v_ref=1.,projection_gain=200.,reactive_epsilon=2e-6),StaticReactiveLaw(2,:smooth_droop,2;q_ref=.05,gain=3.,v_ref=1.,deadband=0.,voltage_epsilon=1e-4,reactive_epsilon=3.5e-5)]
 ws=[StaticWitness(c,laws;weight=.5),StaticWitness(scale_case_loads(c,1.1),laws;weight=.5)]
 bounds=Dict(1=>(;v_ref=(.95,1.05)),2=>(;gain=(1.5,6.),v_ref=(.95,1.05)))
 costs=Dict(1=>[(10.,2.),(20.,0.)],2=>[(5.,1.)]);attrs=Dict("tol"=>1e-10,"constr_viol_tol"=>1e-10,"bound_relax_factor"=>0.,"max_iter"=>2000)
 results=Dict()
 for obj in (:loss,:cost,:q_reserve,:security_margin,:voltage_deviation)
  r=optimize_static_witnesses(ws;design_bounds=bounds,generation_costs=costs,objective=obj,optimizer_attributes=attrs);metrics=static_witness_metrics(ws,r;generation_costs=costs)
  @test validate_static_witnesses(ws,r;design_bounds=bounds).valid
  expected=obj==:cost ? metrics.cost/1e4 : obj in (:q_reserve,:security_margin) ? -metrics[obj] : metrics[obj]
  @test isapprox(r.objective,expected;atol=1e-7,rtol=1e-6)
  @test isapprox(metrics.cost,sum(w.weight*sum(maximum(m*r.states[i].pg[j]+b for (m,b) in costs[g.id]) for (j,g) in enumerate(w.case.generators)) for (i,w) in enumerate(ws));atol=1e-10)
  results[obj]=(r,metrics)
 end
 r,m=results[:q_reserve];limits=Dict(:q_reserve=>m.q_reserve-1e-5)
 polish=optimize_static_witnesses(ws;design_bounds=bounds,generation_costs=costs,initial_parameters=r.parameters,initial_states=r.states,objective_limits=limits,objective=:loss,optimizer_attributes=attrs)
 @test validate_static_witnesses(ws,polish;design_bounds=bounds,generation_costs=costs,objective_limits=limits).valid
 @test !validate_static_witnesses(ws,polish;design_bounds=bounds,generation_costs=costs,objective_limits=Dict(:q_reserve=>.5)).valid
 @test_throws ArgumentError optimize_static_witnesses(ws;objective=:cost)
 @test_throws ArgumentError optimize_static_witnesses(ws;generation_costs=Dict(1=>[(1.,0.)]),objective=:cost)
 @test_throws ArgumentError optimize_static_witnesses(ws;generation_costs=Dict(1=>[(2.,0.),(1.,0.)],2=>[(1.,0.)]),objective=:cost)
 @test_throws ArgumentError optimize_static_witnesses(ws;objective_limits=Dict(:q_reserve=>.6))
 @test_throws ArgumentError optimize_static_witnesses(ws;objective=:unknown)
 # Fixed floors use constants, including simultaneous Q and network targets.
 for target in (.1,.3)
  limits=Dict(:security_margin=>target,:q_reserve=>max(.2,target))
  seed=results[:security_margin][1]
  rr=optimize_static_witnesses(ws;design_bounds=bounds,generation_costs=costs,initial_parameters=seed.parameters,initial_states=seed.states,objective_limits=limits,objective=:loss,optimizer_attributes=attrs)
  mm=static_witness_metrics(ws,rr;generation_costs=costs)
  @test validate_static_witnesses(ws,rr;design_bounds=bounds,generation_costs=costs,objective_limits=limits).valid
  @test mm.security_margin>=target-1e-8
  @test mm.q_reserve>=max(.2,target)-1e-8
 end
 rr=optimize_static_witnesses(ws;design_bounds=bounds,objective=:q_reserve,objective_limits=Dict(:security_margin=>.1),optimizer_attributes=attrs)
 @test validate_static_witnesses(ws,rr;design_bounds=bounds,objective_limits=Dict(:security_margin=>.1)).valid
 println("objective tests metrics ",Dict(k=>v[2] for (k,v) in results))
end
