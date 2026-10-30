@testset "Imported OPF and solved RAW snapshot" begin
    fixture=joinpath(@__DIR__,"..","data","droop2.m")
    control=VoltVarDroop(VoltageSchedule(1.;v_db_low=.99,v_db_high=1.01),.05,0.,
        ReactiveCapability(p_min=0.,p_max=2.,q_min=-1.,q_max=1.))
    supports_frequency=PowerIO.from_powermodels(frequency_document(50.)).value.base_frequency==50.
    for backend in (NativeBackend(),PowerIOBackend())
        imported=import_case(fixture;backend)
        c=attach_controls(imported.case,[control],
            [GeneratorControlAttachment(1,1,RegulatedLocation(:bus,1))])
        state_context=export_state_context(c)
        result=solve_opf(c;smooth_epsilon=1e-3,silent=true)
        @test result.termination_status in (:LOCALLY_SOLVED,:ALMOST_LOCALLY_SOLVED,:OPTIMAL)
        @test result.state !== nothing
        report=validate_equilibrium(c,result;droop_tolerance=5e-3)
        @test report.valid
        @test report.power_balance_max < 1e-6
        # Replay through the other reader's physical case, not solver status.
        reference=attach_controls(load_matpower_case(fixture),[control],
            [GeneratorControlAttachment(1,1,RegulatedLocation(:bus,1))])
        @test validate_equilibrium(reference,result.state;droop_tolerance=5e-3).valid
        if supports_frequency
            plan=prepare_export(c;format=:psse,context=imported,
                state=bind_export_state(result.state,state_context),
                options=ExportOptions(control_policy=:snapshot))
            @test plan.accepted
            mktempdir() do dir
                path=joinpath(dir,"solved.raw");write_export(path,plan)
                readback=import_case(path;backend=PowerIOBackend())
                @test readback.case.base_frequency==50.
                @test maximum(abs,power_balance(readback.case,readback.initial_state).vector)<1e-6
                common = validate_imported_state(readback)
                @test common["power_flow_consistent"]
                @test !common["saved_state_complete"]
                @test !common["valid"]
                @test validate_imported_state(import_case(path))["valid"]
                # The native checker has original field-presence evidence and
                # can independently certify the exported static AC snapshot.
                @test check_psse_file(path;verbose=false)["valid"]
            end
        end
    end
end
