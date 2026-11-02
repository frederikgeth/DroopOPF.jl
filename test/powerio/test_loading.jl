@testset "PowerIO extension load order" begin
    project = dirname(Base.active_project())
    for imports in ("using DroopOPF; import PowerIO;", "import PowerIO; using DroopOPF;")
        code = imports * " @assert !isnothing(Base.get_extension(DroopOPF,:DroopOPFPowerIOExt));" *
            " p=import_case(ARGS[1];backend=PowerIOBackend()); @assert length(p.case.network.buses)==3"
        fixture = joinpath(@__DIR__,"..","data","case3.m")
        @test success(`$(Base.julia_cmd()) --startup-file=no --project=$project -e $code $fixture`)
    end
end
