@testset "balanced AC network residuals" begin
    buses = [Bus(1; reference = true), Bus(2)]
    branches = [Branch(1, 1, 2; resistance = 0.0, reactance = 0.1, thermal_limit = 10.0)]
    network = ACNetwork(buses, branches)
    generator = Generator(
        1,
        1;
        p_min = 0.0,
        p_max = 2.0,
        q_min = -2.0,
        q_max = 2.0,
        initial_p = 0.5,
        initial_q = 0.0,
    )
    angle = asin(0.05)
    reactive_flow = 10.0 * (1.0 - cos(angle))
    load = Load(1, 2; p = 0.5, q = -reactive_flow)
    state = ACState([1.0, 1.0], [0.0, -angle], [0.5], [reactive_flow])
    residual = power_balance(network, state, [generator], [load])

    @test length(residual.vector) == 4
    @test maximum(abs, residual.vector) < 0.01
    @test length(branch_flows(network, state).from) == 1
    @test operating_margins(network, state)[1] > 9.0

    bad_state = ACState([1.0, 1.0], [0.0, 0.0], [0.6], [0.0])
    @test maximum(abs, power_balance(network, bad_state, [generator], [load]).vector) > 0.05
    @test_throws ArgumentError ACNetwork([Bus(1), Bus(1)], Branch[])
    @test_throws ArgumentError Branch(1, 1, 1; resistance = 0.0, reactance = 0.1, thermal_limit = 1.0)
end
