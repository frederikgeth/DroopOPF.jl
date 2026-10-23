# Extended numerical-policy coverage. The default full suite and CI include this file.
@testset "Extended numerical policies" begin
    include("test_s1_ccopt_matrix.jl")
    include("test_s1_experiments.jl")
    include("test_s1_warm_start.jl")
    include("test_s1_restart_policy.jl")
    include("test_s1_staged_initialization.jl")
    include("test_s1_epsilon_sensitivity.jl")
    include("test_s1_frozen_contract_ledger.jl")
    include("test_s1_phase1_restoration.jl")
    include("test_s1_kkt.jl")
end
