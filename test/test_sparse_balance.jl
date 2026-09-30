@testset "Network balance retains sparse derivatives" begin
    case = load_matpower_case(joinpath(@__DIR__, "data", "pglib", "v23.07",
        "pglib_opf_case118_ieee.m"))
    model, _ = DroopOPF._build_acopf_model(case; voltage_epsilon=1e-4,
        reactive_relative_epsilon=1e-4, reactive_epsilon=nothing, silent=true)
    evaluator = DroopOPF.JuMP.NLPEvaluator(model)
    moi = DroopOPF.JuMP.MOI
    moi.initialize(evaluator, [:Jac])
    # Dense zero-admittance expressions previously produced >55,000 entries.
    @test length(moi.jacobian_structure(evaluator)) < 5_000
end
