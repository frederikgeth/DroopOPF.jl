include(joinpath(@__DIR__, "..", "examples", "s1_epsilon_sensitivity.jl"))

@testset "S1 epsilon sensitivity reporting" begin
    base = Dict{String,Any}(
        "solver_valid" => true,
        "policy_valid" => true,
        "physical" => Dict{String,Any}(
            "valid" => false,
            "violations" => ["droop"],
            "droop_residual_max" => 3e-5,
        ),
    )
    @test s1_epsilon_relaxed_valid(base)
    base["physical"]["droop_residual_max"] = 2e-2
    @test !s1_epsilon_relaxed_valid(base)
    base["physical"]["droop_residual_max"] = 3e-5
    push!(base["physical"]["violations"], "power_balance")
    @test !s1_epsilon_relaxed_valid(base)
end
