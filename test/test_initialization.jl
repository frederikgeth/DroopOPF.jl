@testset "Initialization seed is separate from operating policy" begin
 c=frequency_test_case(load=1.4,pmax1=.55)
 laws=frequency_laws();original=model_data(c)
 state=ACState([1.],[.3],[.5,.5],[0.,0.])
 seed=prepare_initialization(c,StaticInverter[],laws;state,frequency_bounds=(48.,52.))
 @test seed.bracketed
 @test seed.frequency_hz≈50-.35/.6 atol=1e-9
 @test seed.state.pg≈[.55,.85] atol=1e-9
 @test seed.state.va==[0.]
 @test state.va==[.3]
 @test model_data(c)==original
 @test laws[1].p_ref==.5
 @test abs(seed.balance_residual)<1e-9
 s=prepare_initialization(c,StaticInverter[],laws;state,frequency_bounds=(49.9,50.1))
 @test !s.bracketed
 @test abs(s.balance_residual)>.1
 @test_throws ArgumentError prepare_initialization(c,StaticInverter[],laws;state=ACState([NaN],[0.],[.5,.5],[0.,0.]))
 @test_throws ArgumentError prepare_initialization(c,StaticInverter[],laws;loss_estimate=NaN)
 @test_throws ArgumentError prepare_initialization(c,StaticInverter[],laws;frequency_bounds=(52.,48.))
end
@testset "Reserve dispatch, frozen references and corruption replay" begin
 c=frequency_test_case(load=1.2,pmax1=1.,pmax2=1.)
 laws=frequency_laws();seed=ACState([1.],[0.],[.2,1.],[0.,0.])
 r=design_preventive_dispatch(c,StaticInverter[],laws;initial_state=seed,frequency_bounds=(48.,52.),
  optimizer_attributes=Dict("tol"=>1e-9,"bound_relax_factor"=>0.))
 @test r.valid
 @test r.reserve_fraction≈.4 atol=1e-6
 @test r.results[1].opf.state.pg≈[.6,.6] atol=1e-6
 @test laws[1].p_ref==.5
 @test r.responses[1].p_ref≈.6 atol=1e-6
 @test !validate_preventive_dispatch(merge(r,(;reserves=Dict(1=>1.)))).valid
 @test_throws ArgumentError design_preventive_dispatch(c,StaticInverter[],laws;initial_state=seed,objective=:bogus)
end
@testset "Inverter reference ownership and security master" begin
 c=m11_case();p=m11_plant(mode=:gfm,q_control=:volt_var,q_ref=.2)
 law=GeneratorFrequencyResponse(generator_id=1,p_ref=.6,gain_pu_per_hz=.4,f_ref_hz=50.)
 base=solve_common_frequency(c,[p],[law];frequency_bounds=(48.,52.))
 @test validate_common_frequency(c,base).valid
 r=design_preventive_dispatch(c,[p],[law];initial_state=base.opf.state,frequency_bounds=(48.,52.),
  optimizer_attributes=Dict("tol"=>1e-9,"bound_relax_factor"=>0.))
 @test r.valid
 @test r.plants[1].q_ref==p.q_ref
 @test r.plants[1].v_ref==p.v_ref
 @test r.plants[1].p_droop_hz==p.p_droop_hz
 @test r.plants[1].s_max==p.s_max
 @test r.plants[1].i_max==p.i_max
 # A duplicated parallel line allows a connected physical outage.
 b=only(c.network.branches)
 b2=Branch(2,b.from_bus,b.to_bus; (k=>getfield(b,k) for k in fieldnames(typeof(b)) if k ∉ (:id,:from_bus,:to_bus))...)
 net=ACNetwork(c.network.buses,[b,b2])
 cc=Case("parallel";network=net,base_power=c.base_power,base_frequency=c.base_frequency,
  loads=c.loads,generators=c.generators,controls=c.controls,attachments=c.attachments)
 co=Contingency(:line;branch_ids=[2])
 rr=design_preventive_dispatch(cc,[p],[law];initial_state=base.opf.state,objective=:security,
  contingencies=[co],frequency_bounds=(48.,52.),optimizer_attributes=Dict("tol"=>1e-9,"bound_relax_factor"=>0.))
 @test rr.valid
 @test length(rr.results)==2
 @test rr.results[1].plants==rr.results[2].plants
 @test rr.results[1].responses==rr.results[2].responses
 @test validate_preventive_dispatch(rr).valid
 m=Model();other=Model();bad=@variable(other,lower_bound=0.,upper_bound=1.)
 v=(;vm=@variable(m,[1:2],lower_bound=.9,upper_bound=1.1),pg=@variable(m,[1:2]),qg=@variable(m,[1:2]))
 @test_throws ArgumentError add_static_inverter_constraints!(m,c,v,[p];active_reference_variables=Dict(p.generator_id=>bad))
end
@testset "Explicit reserve target and delivery validation" begin
 c=frequency_test_case(load=1.2,pmax1=1.,pmax2=1.)
 laws=frequency_laws();s=ACState([1.],[0.],[.2,1.],[0.,0.])
 r=design_preventive_dispatch(c,StaticInverter[],laws;initial_state=s,reserve_fraction_target=.1,
  frequency_bounds=(49.9,50.1),optimizer_attributes=Dict("tol"=>1e-9))
 @test !r.valid # 0.1 pu cannot be delivered by these gains inside +/-0.1 Hz.
 r=design_preventive_dispatch(c,StaticInverter[],laws;initial_state=s,reserve_fraction_target=.1,
  frequency_bounds=(48.,52.),optimizer_attributes=Dict("tol"=>1e-9,"bound_relax_factor"=>0.))
 @test r.valid
 @test r.reserve_fraction≈.1 atol=1e-9
 @test !validate_preventive_dispatch(merge(r,(;frequency_bounds=(49.99,50.01)))).valid
 @test_throws ArgumentError validate_preventive_dispatch(r;tolerance=NaN)
 @test_throws ArgumentError design_preventive_dispatch(c,StaticInverter[],laws;initial_state=s,reserve_fraction_target=.6)
 @test_throws ArgumentError design_preventive_dispatch(c,StaticInverter[],laws;initial_state=s,frequency_bounds=(48.,49.))
end
@testset "Cached frequency seed agrees with exact controller replay" begin
 c=m11_case();s=ACState([1.,1.01],[.2,.21],[.6,.4],[.1,.2])
 law=GeneratorFrequencyResponse(generator_id=1,p_ref=.6,gain_pu_per_hz=.4,f_ref_hz=50.)
 for priority in (:active,:reactive),mode in (:gfl,:gfm)
  p=m11_plant(;mode,priority,q_control=:volt_var,q_ref=.2)
  seed=prepare_initialization(c,[p],[law];state=s,frequency_bounds=(48.,52.),loss_estimate=.01)
  rr=inverter_response(c,p,seed.state.vm[2];frequency_hz=seed.frequency_hz)
  @test seed.state.pg[2]≈rr.p atol=1e-12
  @test seed.state.qg[2]≈rr.q atol=1e-12
  @test seed.state.pg[1]≈DroopOPF._frequency_power(c,law,seed.frequency_hz) atol=1e-12
 end
end
@testset "Prescribed-frequency reference design does not require primary response" begin
 c=frequency_test_case()
 held=[GeneratorFrequencyResponse(generator_id=i,p_ref=.6,gain_pu_per_hz=0.,f_ref_hz=50.) for i in 1:2]
 @test isnothing(DroopOPF._frequency_contract(c,StaticInverter[],held,(48.,52.),Dict();require_responder=false))
 @test_throws ArgumentError DroopOPF._frequency_contract(c,StaticInverter[],held,(48.,52.),Dict())
 r=design_preventive_dispatch(c,StaticInverter[],held;initial_state=ACState([1.],[0.],[.6,.6],[0.,0.]),
  objective=:security,frequency_choice=:prescribed,frequency_bounds=(48.,52.))
 @test r.valid
 @test isempty(r.reserves)
end
@testset "Reserve metadata and frozen-policy corruption are rejected" begin
 c=frequency_test_case(load=1.2,pmax1=1.,pmax2=1.)
 laws=frequency_laws();s=ACState([1.],[0.],[.6,.6],[0.,0.])
 r=design_preventive_dispatch(c,StaticInverter[],laws;initial_state=s,reserve_fraction_target=.1,
  frequency_bounds=(48.,52.),optimizer_attributes=Dict("tol"=>1e-9,"bound_relax_factor"=>0.))
 @test r.valid
 @test !validate_preventive_dispatch(merge(r,(;reserves=Dict{Int,Float64}()))).valid
 @test !validate_preventive_dispatch(merge(r,(;reserve_fraction=.2))).valid
 @test !validate_preventive_dispatch(merge(r,(;responses=laws))).valid
 held=[GeneratorFrequencyResponse(generator_id=i,p_ref=.6,gain_pu_per_hz=0.,f_ref_hz=50.) for i in 1:2]
 @test_throws ArgumentError design_preventive_dispatch(c,StaticInverter[],held;initial_state=s,
  objective=:security,frequency_choice=:prescribed,frequency_bounds=(48.,52.),reserve_fraction_target=.1)
end
@testset "Feasibility polishing preserves the frequency contract" begin
 c=frequency_test_case(load=1.4,pmax1=.55)
 r=solve_common_frequency(c,StaticInverter[],frequency_laws();frequency_bounds=(48.,52.),objective_policy=:feasibility)
 @test validate_common_frequency(c,r).valid
 @test r.frequency_hz≈50-.35/.6 atol=1e-6
 @test_throws ArgumentError solve_common_frequency(c,StaticInverter[],frequency_laws();frequency_bounds=(48.,52.),objective_policy=:unknown)
end
