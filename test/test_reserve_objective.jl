using Test, DroopOPF
@testset "Reserve-aware preventive objective" begin
    c=Case("reserve-dispatch";base_power=100.,base_frequency=50.,
        network=ACNetwork([Bus(1;reference=true)],Branch{Float64}[]),
        generators=[Generator(1,1;p_min=0.,p_max=1.,q_min=-1.,q_max=1.),
                    Generator(2,1;p_min=0.,p_max=3.,q_min=-1.,q_max=1.)],
        loads=[Load(1,1;p=1.,q=0.)],controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    studies=[Study(c;participation=Dict(1=>1.,2=>3.))]
    opts=Dict("tol"=>1e-9,"bound_relax_factor"=>0.,"max_cpu_time"=>20.)
    r=optimize_multi_period_security(studies;objective_policy=:reserve_loss,optimizer_attributes=opts)
    @test validate_multi_period_security(studies,r).valid
    @test [s.name for s in r.stages]==[:reserve,:loss]
    @test r.periods[1].states[:base].pg ≈ [.25,.75] atol=1e-6
    @test r.stages[1].objective ≈ -.75 atol=1e-6
    reserve_only=optimize_multi_period_security(studies;objective_policy=:reserve,optimizer_attributes=opts)
    @test validate_multi_period_security(studies,reserve_only).valid
    @test [s.name for s in reserve_only.stages]==[:reserve]
    @test_throws ArgumentError optimize_multi_period_security(studies;objective_policy=:unknown)
    damaged=deepcopy(r);damaged.stages[1]=(;name=:reserve,status=:LOCALLY_SOLVED,objective=-.9)
    @test !validate_multi_period_security(studies,damaged).valid
    guarded=optimize_multi_period_security(studies;objective_policy=:reserve,
        reserve_generator_outages=[1,2],optimizer_attributes=opts)
    @test validate_multi_period_security(studies,guarded).valid
    @test sum(guarded.periods[1].states[:base].pg)<=1.0 + 1e-6
    feasible=optimize_multi_period_security(studies;objective_policy=:feasibility,
        reserve_generator_outages=[1,2],optimizer_attributes=opts)
    @test validate_multi_period_security(studies,feasible).valid
    @test [s.name for s in feasible.stages]==[:feasibility]
    @test_throws ArgumentError optimize_multi_period_security(studies;reserve_generator_outages=[99])
    @test_throws ArgumentError optimize_multi_period_security(studies;reserve_generator_outages=[1,1])
    @test_throws ArgumentError optimize_multi_period_security(studies;reserve_margin_pu=-1.)
    # Each frozen scan must retain its period-specific preventive AVR target.
    targets=[1.,1.005]
    assignments=[[ReactiveControlAssignment(1,AVR(v),RegulatedLocation(:bus,1)),
        ReactiveControlAssignment(2,FreeQ())] for v in targets]
    scheduled=[Study(c;reactive_assignments=a,participation=Dict(1=>1.,2=>3.),
        contingencies=[Contingency(:g2;generator_ids=[2])]) for a in assignments]
    states=[ACState([v],[0.],[.25,.75],[0.,0.]) for v in targets]
    empty_settings=[Dict{Int,Float64}(),Dict{Int,Float64}()]
    frozen=optimize_multi_period_security(scheduled;fixed_base_states=states,
        fixed_base_taps=empty_settings,fixed_base_shunts=empty_settings,optimizer_attributes=opts)
    @test validate_multi_period_security(scheduled,frozen).valid
    @test [p.reactive_assignments[1].mode.voltage_setpoint for p in frozen.periods]==targets
    eq=[(;taps=Dict(),shunts=Dict(),scenarios=Dict(:base=>(;taps=Dict(),shunts=Dict()),
        :g2=>(;taps=Dict(),shunts=Dict()))) for _ in 1:2]
    warmed=optimize_multi_period_security(scheduled;fixed_base_states=states,
        fixed_base_taps=empty_settings,fixed_base_shunts=empty_settings,initial_equipment=eq,optimizer_attributes=opts)
    @test validate_multi_period_security(scheduled,warmed).valid
    @test_throws ArgumentError optimize_multi_period_security(studies;
        initial_equipment=[(;taps=Dict(),shunts=Dict(),scenarios=Dict(:unknown=>(;taps=Dict(),shunts=Dict())))])
    @test_throws ArgumentError optimize_multi_period_security(scheduled;optimizer_attributes=opts)
    common=[Study(c;reactive_assignments=assignments[1],participation=Dict(1=>1.,2=>3.),
        contingencies=[Contingency(:g2;generator_ids=[2])]) for _ in 1:2]
    full_starts=[Dict(:base=>states[t],:g2=>ACState([targets[t]],[0.],[.998,0.],[0.,0.])) for t in 1:2]
    warm_targets=[Dict(1=>v) for v in targets]
    warm_relief=[Dict(:g2=>(;dr=[.001],shed=[.001])) for _ in 1:2]
    complete=optimize_multi_period_security(common;initial_states=full_starts,
        initial_avr_targets=warm_targets,initial_relief=warm_relief,
        initial_balancing_power=[Dict(:g2=>.748) for _ in 1:2],avr_bounds=Dict(1=>(.98,1.02)),
        response=:s2_proportional,s2_emergency=true,objective_policy=:feasibility,optimizer_attributes=opts)
    @test validate_multi_period_security(common,complete).valid
    @test_throws ArgumentError optimize_multi_period_security(common;avr_bounds=Dict(1=>(.98,1.02)),
        initial_avr_targets=[Dict(99=>1.),Dict()])
    @test_throws ArgumentError optimize_multi_period_security(common;avr_bounds=Dict(1=>(.98,1.02)),
        initial_avr_targets=[Dict(1=>NaN),Dict()])
    @test_throws ArgumentError optimize_multi_period_security(common;s2_emergency=true,
        initial_relief=[Dict(:g2=>(;dr=Float64[],shed=Float64[])),Dict()])
    @test_throws ArgumentError optimize_multi_period_security(common;
        initial_balancing_power=[Dict(:base=>0.),Dict()])
    paired=[Study(c;reactive_assignments=[ReactiveControlAssignment(g.id,AVR(1.),RegulatedLocation(:bus,1)) for g in c.generators])]
    @test_throws ArgumentError optimize_multi_period_security(paired;avr_bounds=Dict(1=>(.98,1.02),2=>(.98,1.02)),
        initial_avr_targets=[Dict(1=>.99,2=>1.01)])
    mktempdir() do d
        path=joinpath(d,"reserve.json");write_multi_period_security(path,r)
        @test validate_multi_period_security(studies,read_multi_period_security(path)).valid
    end
end
