using Test, LinearAlgebra
using DroopOPF
import PowerIO

profile = get(ENV, "DROOPOPF_POWERIO_TEST_PROFILE", "released")
profile in ("released", "corrected") || error("DROOPOPF_POWERIO_TEST_PROFILE must be released or corrected")
@testset "Required PowerIO capability profile: $profile" begin
    transformers = Base.get_extension(DroopOPF, :DroopOPFPowerIOExt)._raw_transformer_basis_qualified()
    frequency = PowerIO.from_powermodels(Dict("baseMVA"=>100., "base_frequency"=>50.,
        "bus"=>Dict("1"=>Dict("bus_i"=>1,"bus_type"=>3,"base_kv"=>220.)))).value.base_frequency == 50.
    if profile == "corrected"
        @test transformers
        @test frequency
    else
        # This profile is intentionally pinned: an upstream fix must trigger a
        # dependency/profile review, rather than silently changing the test set.
        @test pkgversion(PowerIO) == v"0.11.7"
        @test !transformers
        @test !frequency
    end
end

frequency_document(frequency) = Dict("baseMVA"=>100., "base_frequency"=>frequency,
    "bus"=>Dict("1"=>Dict("bus_i"=>1,"bus_type"=>3,"base_kv"=>220.,
        "vm"=>1.,"va"=>0.,"vmin"=>.9,"vmax"=>1.1)))

@testset "PowerIO integration" begin
    @test !isnothing(Base.get_extension(DroopOPF, :DroopOPFPowerIOExt))
    @info "PowerIO versions" julia=VERSION package=pkgversion(PowerIO) library=PowerIO.library_version()
    include("../io/test_case_io.jl")
    include("test_import.jl")
    include("test_real_raw.jl")
    include("test_export.jl")
    include("test_export_validation.jl")
    include("test_frequency.jl")
    include("test_solver_smoke.jl")
    include("test_loading.jl")
end
