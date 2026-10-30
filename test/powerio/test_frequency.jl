@testset "Public construction and RAW export frequency" begin
    supports_frequency = PowerIO.from_powermodels(frequency_document(50.)).value.base_frequency==50.
    @info "Loaded dictionary frequency support" supports_frequency
    fixture = joinpath(@__DIR__,"..","data","case3.m")
    for frequency in (50.,60.,16.7)
        imported = import_case(fixture;options=ImportOptions(base_frequency=frequency))
        c=imported.case
        bound=bind_export_state(imported.initial_state,export_state_context(c))
        if !supports_frequency && frequency!=60.
            err=try prepare_export(c;format=:psse,context=imported,state=bound); catch e; e; end
            @test err isa CaseIOError
            @test err.code==:unsupported_export_frequency
            continue
        end
        plan=prepare_export(c;format=:psse,context=imported,state=bound)
        @test plan.accepted
        mktempdir() do dir
            path=joinpath(dir,"frequency.raw");write_export(path,plan)
            for backend in (NativeBackend(),PowerIOBackend())
                r=import_case(path;backend)
                @test r.case.base_frequency==frequency
                @test r.case.base_power==c.base_power
                @test r.initial_state.vm ≈ imported.initial_state.vm atol=1e-8
                @test r.initial_state.pg ≈ imported.initial_state.pg atol=1e-8
                @test DroopOPF._admittance_matrix(r.case.network) ≈ DroopOPF._admittance_matrix(c.network) atol=1e-8
            end
        end
    end
    if supports_frequency
        for frequency in (0.,-50.)
            @test_throws PowerIO.PowerIOError PowerIO.from_powermodels(frequency_document(frequency))
        end
    end
end
