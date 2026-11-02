using SHA

include("test_import_profile.jl")
include("test_case_validation.jl")

@testset "Common case import contract" begin
    data = joinpath(@__DIR__, "..", "data")
    @test_throws ArgumentError ImportOptions(unrated_limit_pu=0)
    @test_throws ArgumentError ImportOptions(unrated_limit_pu=Inf)
    @test_throws ArgumentError ImportOptions(base_frequency=true)
    @test_throws ArgumentError ImportOptions(id=" ")
    @test_throws ArgumentError ImportOptions(base_frequency=-50)
    @test ImportOptions(unrated_limit_pu=3).unrated_limit_pu === 3.0
    path = joinpath(data, "case3.m")
    imported = import_case(path)
    c = imported.case
    @test c.base_frequency == 50.
    @test c.base_power == 100.
    @test c.loads[1].p == .217
    @test imported.source.backend == :native
    @test imported.source.format == :matpower
    @test imported.source.sha256 == bytes2hex(sha256(read(path)))
    @test imported.metadata.bus_base_kv[1] == 230.
    @test imported.metadata.branch_rating_mva[1] == 250.
    @test imported.metadata.saved_field_presence[:VM] == fill(:supplied, 3)
    @test imported.initial_state.pg == [.8, .4]
    @test imported.initial_state.va[2] ≈ deg2rad(-4.98)
    @test imported.source_ids[:generator][1] != imported.source_ids[:generator][2]
    @test load_case(path; options=ImportOptions(id="chosen", base_frequency=60.)).id == "chosen"
    @test load_case(path; options=ImportOptions(base_frequency=60.)).base_frequency == 60.
    @test_throws CaseIOError import_case(path; format=:unsupported)
    if isnothing(Base.get_extension(DroopOPF, :DroopOPFPowerIOExt))
        err = try import_case(path; backend=PowerIOBackend()); catch e; e; end
        @test err isa CaseIOError
        @test err.code == :backend_unavailable
    end
    for revision in (33, 34, 36)
        rawpath = joinpath(data, "psse", "synthetic_v$revision.raw")
        r = import_case(rawpath)
        legacy = import_psse_case(parse_psse_raw(rawpath))
        @test DroopOPF._json_data(r.case) == DroopOPF._json_data(legacy.case)
        @test r.source.revision == revision
        @test r.source_ids[:generator][1] == (1, "G1")
        @test r.metadata.bus_base_kv[2] == 110.
        @test r.metadata.saved_field_presence[:PG] == [:supplied]
        @test r.initial_state.qg == [.21]
        @test load_case(rawpath; options=ImportOptions(base_frequency=60.)).base_frequency == 60.
    end
    mktempdir() do dir
        # Differentiate supplied operating data from clamped optimizer hints.
        raw = read(joinpath(data,"psse","synthetic_v33.raw"), String)
        path = joinpath(dir, "changed.raw")
        write(path, replace(raw, "62,21,80,-50" => "162,91,80,-50"))
        r = import_case(path)
        @test r.initial_state.pg == [1.62]
        @test r.initial_state.qg == [.91]
        @test r.case.generators[1].initial_p == 1.5
        @test r.case.generators[1].initial_q == .8
        write(path, replace(raw, "1.02,5,1.1,.9,1.1,.9" => ",,1.1,.9,1.1,.9"))
        r = import_case(path)
        @test r.metadata.saved_field_presence[:VM][1] == :defaulted
        @test r.metadata.saved_field_presence[:VA][1] == :defaulted
        mp = read(joinpath(data,"case3.m"), String)
        path = joinpath(dir, "unrated.m")
        write(path, replace(mp, "0.176 250 250 250" => "0.176 0 250 250"))
        err = try import_case(path); catch e; e; end
        @test err isa CaseIOError
        @test err.code == :unrated_branch
        r = import_case(path; options=ImportOptions(unrated_limit_pu=8.))
        @test r.case.network.branches[1].thermal_limit == 8.
        @test r.metadata.branch_rating_mva[1] === nothing
        @test any(d -> d.code==:unrated_limit_applied, r.diagnostics)
        @test load_matpower_case(path).network.branches[1].thermal_limit == 1e6
    end
end
