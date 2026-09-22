using Test

include(joinpath(@__DIR__, "..", "examples", "s1_ccopt_policy_matrix.jl"))
include(joinpath(@__DIR__, "..", "examples", "s1_ccopt_frozen_cross_seed.jl"))
include(joinpath(@__DIR__, "..", "examples", "s1_ccopt_droop_feasibility.jl"))
include(joinpath(@__DIR__, "..", "examples", "s1_ccopt_300_continuation.jl"))

@testset "CCOpt frozen S1 matrix specification" begin
    cells=s1_ccopt_policy_cells()
    @test length(cells)==12
    @test Set((c.n,c.load_factor,c.start) for c in cells)==Set((n,f,s) for n in (118,300)
        for f in (1.0,1.05) for s in (:anchor,:flat_low,:flat_high))
end
