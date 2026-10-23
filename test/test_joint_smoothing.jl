@testset "Joint design absolute reactive smoothing" begin
    function smoothing_case(q0,ref)
        ctrl=VoltVarDroop(VoltageSchedule(ref;v_db_low=ref,v_db_high=ref),.02,q0,
            ReactiveCapability(p_min=0.,p_max=1.,q_min=-1.,q_max=1.))
        Case("matched-smoothing";base_power=100.,base_frequency=50.,
            network=ACNetwork([Bus(1;reference=true)],Branch[]),
            generators=[Generator(1,1;p_min=0.,p_max=1.,q_min=-1.,q_max=1.,initial_p=.5,initial_q=.25)],
            loads=[Load(1,1;p=.5,q=.25)],controls=[ctrl],
            attachments=[GeneratorControlAttachment(1,1,RegulatedLocation(:bus,1))])
    end
    cases=[smoothing_case(0.,1.),smoothing_case(.25,.995)]
    start=ACState([.995],[0.],[.5],[.25])
    results=[optimize_joint_design(c;initial_state=start,smooth_epsilon=1e-6,
        smooth_reactive_epsilon=1e-6) for c in cases]
    for (c,r) in zip(cases,results)
        @test r.opf.smooth_reactive_epsilon==1e-6
        @test validate_joint_design(c,r).physical.valid
        @test isapprox(r.opf.state.vm[1],.995;atol=1e-6)
    end
    @test isapprox(results[1].opf.state.qg,results[2].opf.state.qg;atol=1e-7)
    @test_throws ArgumentError optimize_joint_design(cases[1];smooth_reactive_epsilon=0.)
    @test_throws ArgumentError optimize_joint_design(cases[1];smooth_reactive_epsilon=Inf)
end
