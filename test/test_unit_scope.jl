@testset "Unit suite excludes large reliability networks" begin
    forbidden = String[]
    for size in ("118", "300")
        append!(forbidden, [join((prefix, size)) for prefix in
            ("case", "ieee", "public", "pglib_opf_case")])
    end
    for path in readdir(@__DIR__; join=true)
        basename(path) in ("runtests.jl", "test_unit_scope.jl") && continue
        endswith(path, ".jl") || continue
        source = lowercase(read(path, String))
        @test all(token -> !occursin(token, source), forbidden)
    end
end
