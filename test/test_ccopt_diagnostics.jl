using JuMP
import CCOpt

@testset "CCOpt diagnostics for ordinary NLP fallback" begin
    model=Model(CCOpt.Optimizer)
    set_silent(model)
    @variable(model, -2 <= x <= 2, start=0.0)
    @objective(model, Min, (x-1)^2)
    optimize!(model)
    @test is_solved_and_feasible(model)
    @test value(x) ≈ 1 atol=1e-5
    diagnostics=ccopt_diagnostics(model)
    @test diagnostics["algorithm"] == "MadNLP ordinary NLP fallback"
    @test diagnostics["complementarity_pairs"] == 0
    @test diagnostics["complementarity_feasibility"] == 0
    @test diagnostics["relaxation_min"] === nothing
    @test diagnostics["relaxation_max"] === nothing
    @test diagnostics["solve_time_seconds"] === nothing
    @test diagnostics["total_time_seconds"] >= 0
    @test diagnostics["inner_iterations"] > 0
end
