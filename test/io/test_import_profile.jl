@testset "Common static import profile" begin
    backends = isnothing(Base.get_extension(DroopOPF, :DroopOPFPowerIOExt)) ?
        (NativeBackend(),) : (NativeBackend(), PowerIOBackend())
    source = read(joinpath(@__DIR__, "..", "data", "case3.m"), String)
    mktempdir() do dir
        path = joinpath(dir, "profile.m")
        for backend in backends
            errorcode(text) = begin
                write(path, text)
                err = try import_case(path; backend); catch e; e; end
                @test err isa CaseIOError
                err isa CaseIOError ? err.code : nothing
            end
            # Active extra equipment/constraints must not silently disappear.
            for field in ("dcline", "storage", "A", "unknown_extension")
                @test errorcode(source * "\nmpc.$field = [1 2 3];\n") == :unsupported_matpower_extension
            end
            @test errorcode(replace(source, "1 -360 360" => "1 -30 30")) == :unsupported_angle_limits
            write(path, source * "\nmpc.storage = [];\n")
            @test length(import_case(path; backend).case.network.buses) == 3
            write(path, source * "\nmpc.gencost = [2 0 0 2 1 0; 2 0 0 2 1 0];\n")
            r = import_case(path; backend)
            @test any(d -> d.code == :study_metadata_unmodeled, r.diagnostics)
            # Isolated buses and every attachment are excluded together. Supplied
            # state order must follow the remaining equipment, including gaps.
            write(path, replace(source, "2 2 21.7" => "2 4 21.7"))
            r = import_case(path; backend)
            @test [b.id for b in r.case.network.buses] == [1,3]
            @test r.initial_state.vm == [1.06,1.01]
            @test r.initial_state.pg == [.8]
            @test length(r.case.network.branches) == 1
            @test only(r.case.loads).bus_id == 3
            @test any(d -> d.code == :isolated_equipment_excluded, r.diagnostics)
            @test errorcode(replace(source, "2 40.0" => "9 40.0")) in (:unknown_bus, :powerio_parse_error)
            @test errorcode(replace(source, "1.06 0.94" => "0.9 1.1")) in (:invalid_case_data, :powerio_parse_error)
        end
        err = try import_case(joinpath(dir,"missing.m")); catch e; e; end
        @test err isa CaseIOError
        @test err.code == :source_read_error
    end
end
