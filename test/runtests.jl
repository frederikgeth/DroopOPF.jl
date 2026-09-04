using Test
using DroopOPF

@testset "DroopOPF" begin
    include("test_curves.jl")
    include("test_controls.jl")
    include("test_domain.jl")
    include("test_network.jl")
end
