using JSON

@testset "Reactive-control study and result persistence" begin
    network = ACNetwork([Bus(1; reference=true)], Branch{Float64}[])
    generators = [Generator(i, 1; p_min=0.0, p_max=2.0, q_min=-1.0, q_max=1.0,
        initial_p=0.25) for i in 1:4]
    case = Case("reactive-persistence"; base_power=100.0, base_frequency=50.0,
        network, loads=[Load(1, 1; p=1.0, q=0.1)], generators,
        controls=VoltVarDroop[], attachments=GeneratorControlAttachment[])
    droop = VoltVarDroop(VoltageSchedule(1.0; v_db_low=0.99, v_db_high=1.01),
        0.05, 0.0, ReactiveCapability(p_min=0.0, p_max=2.0, q_min=-1.0, q_max=1.0))
    assignments = ReactiveControlAssignment[
        ReactiveControlAssignment(1, FreeQ()),
        ReactiveControlAssignment(2, FixedQ(0.1)),
        ReactiveControlAssignment(3, AVR(1.0), RegulatedLocation(:bus, 1)),
        ReactiveControlAssignment(4, droop, RegulatedLocation(:bus, 1)),
    ]
    study = Study(case; reactive_assignments=assignments)
    mktempdir() do dir
        study_path = joinpath(dir, "study.json")
        write_study(study_path, study)
        document = JSON.parsefile(study_path)
        @test document["schema_version"] == 6
        @test [a["mode"]["type"] for a in document["data"]["reactive_assignments"]] ==
            ["FreeQ", "FixedQ", "AVR", "VoltVarDroop"]
        restored = read_study(study_path)
        @test DroopOPF._json_data(restored.reactive_assignments) ==
            DroopOPF._json_data(assignments)

        avr_study = Study(Case("avr-persistence"; base_power=100.0,
            base_frequency=50.0, network,
            loads=[Load(1, 1; p=0.5, q=0.0)], generators=[generators[1]],
            controls=VoltVarDroop[], attachments=GeneratorControlAttachment[]);
            reactive_assignments=[ReactiveControlAssignment(1, AVR(1.0),
                RegulatedLocation(:bus, 1))])
        result = solve_scopf(avr_study)
        result_path = joinpath(dir, "result.json")
        write_scopf_result(result_path, result)
        @test JSON.parsefile(result_path)["schema_version"] == 2
        restored_result = read_scopf_result(result_path)
        @test equilibrium_report(avr_study, restored_result).valid
        @test DroopOPF._json_data(restored_result.reactive_assignments) ==
            DroopOPF._json_data(avr_study.reactive_assignments)
        mismatched = JSON.parsefile(result_path)
        mismatched["data"]["reactive_assignments"] = nothing
        write(result_path, JSON.json(mismatched))
        @test :reactive_assignments_mismatch in
            equilibrium_report(avr_study, read_scopf_result(result_path)).violations[:base]

        mismatched["schema_version"] = 1
        delete!(mismatched["data"], "reactive_assignments")
        write(result_path, JSON.json(mismatched))
        @test isnothing(read_scopf_result(result_path).reactive_assignments)

        legacy = JSON.parsefile(study_path)
        legacy["schema_version"] = 4
        delete!(legacy["data"], "reactive_assignments")
        write(study_path, JSON.json(legacy))
        @test isnothing(read_study(study_path).reactive_assignments)
    end
end
