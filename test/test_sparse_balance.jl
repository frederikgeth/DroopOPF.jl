@testset "Network balance retains sparse derivatives" begin
    buses = [Bus(i; reference=i == 1) for i in 1:8]
    branches = [Branch(i, i, i == 8 ? 1 : i + 1;
        resistance=0.01, reactance=0.1, thermal_limit=2.0) for i in 1:8]
    case = Case("sparse-eight-bus"; base_power=100.0, base_frequency=50.0,
        network=ACNetwork(buses, branches),
        loads=[Load(1, 5; p=0.4, q=0.1)],
        generators=[Generator(1, 1; p_min=0.0, p_max=1.0,
            q_min=-1.0, q_max=1.0, initial_p=0.4, initial_q=0.0)],
        controls=VoltVarDroop[], attachments=GeneratorControlAttachment[])
    model, _ = DroopOPF._build_acopf_model(case; voltage_epsilon=1e-4,
        reactive_relative_epsilon=1e-4, reactive_epsilon=nothing, silent=true)
    evaluator = DroopOPF.JuMP.NLPEvaluator(model)
    moi = DroopOPF.JuMP.MOI
    moi.initialize(evaluator, [:Jac])
    # Dense active/reactive balances contribute 4n² voltage derivatives alone.
    @test length(moi.jacobian_structure(evaluator)) < 4 * length(buses)^2
end
