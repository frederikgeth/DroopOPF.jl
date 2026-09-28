@testset "explicit reactive-control modes" begin
    network = ACNetwork([Bus(1; reference=true), Bus(2)],
        [Branch(1, 1, 2; resistance=0.01, reactance=0.1, thermal_limit=2.0)])
    generators = [
        Generator(1, 1; p_min=0.0, p_max=2.0, q_min=-1.0, q_max=1.0,
            initial_p=0.5, initial_q=0.0),
        Generator(2, 2; p_min=0.0, p_max=1.0, q_min=-0.5, q_max=0.5,
            initial_p=0.0, initial_q=0.0),
    ]
    schedule = VoltageSchedule(1.0; v_db_low=0.99, v_db_high=1.01)
    capability = ReactiveCapability(p_min=0.0, p_max=2.0, q_min=-1.0, q_max=1.0)
    droop = VoltVarDroop(schedule, 0.05, capability; q_ref=0.0)
    location = RegulatedLocation(:bus, 1)
    case = Case("reactive-modes"; base_power=100.0, base_frequency=50.0, network,
        loads=Load[], generators, controls=[droop],
        attachments=[GeneratorControlAttachment(1, 1, location)])

    @test q_ref(droop) == droop.q_at_deadband == 0.0
    @test validate_reactive_assignments(case, [
        ReactiveControlAssignment(1, AVR(1.0), location),
        ReactiveControlAssignment(2, FixedQ(0.2)),
    ])
    projected = reactive_control_assignments(case)
    @test projected[1].mode isa VoltVarDroop
    @test projected[2].mode isa FreeQ
    @test_throws ArgumentError validate_reactive_assignments(case, [
        ReactiveControlAssignment(1, FreeQ()),
        ReactiveControlAssignment(1, FixedQ(0.0)),
    ])
    @test_throws ArgumentError validate_reactive_assignments(case,
        [ReactiveControlAssignment(2, FixedQ(0.6))])
    @test_throws ArgumentError ReactiveControlAssignment(1, AVR(1.0))
    @test_throws ArgumentError ReactiveControlAssignment(1, FreeQ(), location)
    @test_throws ArgumentError AVR(0.0)
    @test_throws ArgumentError FixedQ(Inf)
end
