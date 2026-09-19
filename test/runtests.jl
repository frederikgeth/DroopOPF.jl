using Test
using DroopOPF

@testset "DroopOPF" begin
    include("test_curves.jl")
    include("test_controls.jl")
    include("test_domain.jl")
    include("test_network.jl")
    include("test_opf.jl")
    include("test_scopf.jl")
    include("test_solver_compatibility.jl")
    include("test_validation.jl")
    include("test_matpower.jl")
    include("test_transformer_data.jl")
    include("test_transformer_physics.jl")
    include("test_fixed_shunts.jl")
    include("test_shunt_banks.jl")
    include("test_plotting.jl")
    include("test_droop_sweep.jl")
    include("test_droop_optimization.jl")
    include("test_robustness.jl")
end
