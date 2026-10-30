@testset "Real RAW profile and diagnostic classification" begin
    path = joinpath(@__DIR__,"..","data","psse","public_v34_ieee14.raw")
    options = ImportOptions(unrated_limit_pu=10.)
    ext = Base.get_extension(DroopOPF, :DroopOPFPowerIOExt)
    raw = read(path)
    parsed = PowerIO.parse(path)
    @test !isempty(parsed.diagnostics)
    @test all(d -> ext._qualified_raw_notice(d, raw), parsed.diagnostics)
    if ext._raw_transformer_basis_qualified()
        r = import_case(path; backend=PowerIOBackend(), options)
        native = import_case(path; options)
        @test length(r.case.network.buses) == 14
        @test length(r.case.generators) == 5
        @test r.initial_state.vm ≈ native.initial_state.vm atol=1e-12
        @test r.initial_state.pg ≈ native.initial_state.pg atol=1e-12
        @test DroopOPF._admittance_matrix(r.case.network) ≈ DroopOPF._admittance_matrix(native.case.network) atol=1e-10
        @test count(d -> !isnothing(d.upstream_code), r.diagnostics) == length(parsed.diagnostics)
        for dv in (-.02, .03)
            s = r.initial_state
            state = ACState(s.vm .+ dv, s.va, s.pg, s.qg)
            @test power_balance(r.case,state).vector ≈ power_balance(native.case,state).vector atol=1e-10
        end
    else
        err = try import_case(path;backend=PowerIOBackend(),options); catch e; e; end
        @test err isa CaseIOError
        @test err.code == :unqualified_raw_transformer
    end
    notice(code, message; severity=:warning) = (;code, message, severity)
    @test !ext._qualified_raw_notice(notice("READ.PSSE.FIELD_DROPPED",
        "PSS/E system wide UNKNOWN record has no typed representation; retained only in the same format source"),raw)
    @test !ext._qualified_raw_notice(notice("READ.PSSE.SECTION_UNSUPPORTED",
        "PSS/E TWO-TERMINAL DC section (1 record line(s)) is not modeled: preserved only in a same-format .raw echo, dropped on any other write"),raw)
    @test !ext._qualified_raw_notice(notice(parsed.diagnostics[1].code, parsed.diagnostics[1].message;severity=:error),raw)
    rating_notice = only(unique([d.message for d in parsed.diagnostics if occursin("RATING record",d.message)]))
    @test !ext._qualified_raw_notice(notice("READ.PSSE.FIELD_DROPPED",rating_notice),
        collect(codeunits(replace(String(copy(raw)), "RATING, 1,"=>"RATING, EXTRA_OPTION=1,"))))
end
