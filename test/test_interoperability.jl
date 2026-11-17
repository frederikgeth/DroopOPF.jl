@testset "Public static transfer contract" begin
    c=Case("transfer";base_power=100.,base_frequency=50.,
        network=ACNetwork([Bus(1;reference=true),Bus(2)],
            [Branch(1,1,2;resistance=.01,reactance=.1,thermal_limit=1.)]),
        generators=[Generator(1,1;p_min=0.,p_max=1.,q_min=-1.,q_max=1.,initial_p=0.,initial_q=0.)],
        loads=Load[],controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
    s=ACState([1.,1.],[0.,0.],[0.],[0.])
    point=materialize_operating_point(c,s)
    @test point.case===c
    @test point.state===s
    @test point.source_context["role"]=="supplied_equilibrium"
    @test model_data(point.case)==DroopOPF._json_data(c)
    @test_throws ArgumentError materialize_operating_point(c,ACState([1.,1.],[0.,0.],[.1],[0.]))
    @test model_data(scale_case_loads(c,1.))==model_data(c)
    @test_throws ArgumentError scale_case_loads(c,NaN)
    @test_throws ArgumentError scale_case_loads(c,-1.)
end
