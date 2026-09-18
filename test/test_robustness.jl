import JSON

@testset "M4 multi-start robustness" begin
    case = m2_case()
    study = Study(case; contingencies=[
        Contingency(:line_22; branch_ids=[22]),
        Contingency(:generator_9; generator_ids=[9]),
    ], participation=Dict(7=>1.0, 9=>1.0))
    reference = solve_scopf(study; smooth_epsilon=1e-5)
    shifted = Dict(id => ACState(state.vm .+ 0.005, state.va, state.pg, state.qg)
        for (id, state) in reference.states)
    starts = Dict{Symbol,Any}(
        :cold => Dict{Symbol,ACState{Float64}}(),
        :reference => reference.states,
        :voltage_high => shifted,
    )
    comparison = solve_scopf_multistart(study, starts;
        smooth_epsilon=1e-5, objective_atol=1e-8, objective_rtol=1e-6)
    @test comparison.classification == :comparable
    @test length(comparison.runs) == 3
    @test Set(comparison.valid_run_ids) == Set(keys(starts))
    @test isempty(only(run.initial_states for run in comparison.runs if run.label == :cold))
    @test Set(keys(only(run.initial_states for run in comparison.runs
        if run.label == :voltage_high))) == Set([:base, :line_22, :generator_9])
    @test comparison.best_run in keys(starts)
    @test comparison.objective_spread <=
        comparison.objective_atol + comparison.objective_rtol * comparison.objective_max
    @test all(run.report.valid for run in comparison.runs)
    @test occursin("voltage_high", markdown_report(comparison))
    @test_throws ArgumentError solve_scopf_multistart(study, Dict())
    @test_throws ArgumentError solve_scopf_multistart(study, starts; objective_atol=-1.0)
    @test_throws ArgumentError solve_scopf_multistart(study, starts;
        initial_states=reference.states)

    mktempdir() do directory
        path = write_scopf_multistart(joinpath(directory, "multistart.json"), comparison)
        text = read(path, String)
        @test occursin("DroopOPF.SCOPFMultiStartResult", text)
        @test occursin("voltage_high", text)
    end
end

@testset "M4 M3 parameter multi-start" begin
    case = m2_case()
    study = Study(case; contingencies=[
        Contingency(:line_22; branch_ids=[22]),
        Contingency(:generator_9; generator_ids=[9]),
    ], participation=Dict(7=>1.0, 9=>1.0))
    reference = solve_scopf(study; smooth_epsilon=1e-5)
    starts = Dict(
        :low => DroopSettings(0.045, 0.996, 0.006, 0.006),
        :high => DroopSettings(0.095, 1.004, 0.014, 0.014),
    )
    comparison = optimize_droop_multistart(study, 2, starts;
        slope_bounds=(0.04, 0.10), v_ref_bounds=(0.995, 1.005),
        deadband_low_bounds=(0.005, 0.015),
        deadband_high_bounds=(0.005, 0.015), smooth_epsilon=1e-5,
        reference_result=reference)
    @test comparison.classification == :comparable
    @test Set(comparison.valid_run_ids) == Set([:low, :high])
    @test all(run.report.valid for run in comparison.runs)
    @test comparison.parameter_spread.slope >= 0
    @test comparison.parameter_spread.v_ref >= 0
    @test only(run.initial_settings for run in comparison.runs if run.label == :low) == starts[:low]
    @test occursin("Parameter spread", markdown_report(comparison))
    @test_throws ArgumentError optimize_droop_parameters(study, 2;
        slope_bounds=(0.04, 0.10), initial_settings=DroopSettings(0.2, 1.0, 0.01, 0.01),
        smooth_epsilon=1e-5, reference_result=reference)
    @test_throws ArgumentError optimize_droop_multistart(study, 2, Dict())
    fixed_other = optimize_droop_parameters(study, 2;
        slope_bounds=(0.06, 0.06), reference_result=reference)
    @test fixed_other.settings.slope == 0.06
    @test validate_droop_design(study, fixed_other).valid
    mktempdir() do directory
        path = write_droop_design_multistart(joinpath(directory, "design-multistart.json"), comparison)
        text = read(path, String)
        @test occursin("DroopOPF.DroopDesignMultiStartResult", text)
        @test occursin("initial_settings", text)
        @test occursin("parameter_spread", text)
    end
end

@testset "M4 structured diagnostics" begin
    case = m2_case()
    study = Study(case; contingencies=[
        Contingency(:line_22; branch_ids=[22]),
        Contingency(:generator_9; generator_ids=[9]),
    ], participation=Dict(7=>1.0, 9=>1.0))
    result = solve_scopf(study; smooth_epsilon=1e-5)
    diagnostics = scopf_diagnostics(study, result;
        breakpoint_tolerance=0.01, binding_tolerance=0.1)
    @test diagnostics.critical_scenario in (:line_22, :generator_9)
    @test length(diagnostics.breakpoints) == 5
    @test all(item.distance >= 0 for item in diagnostics.breakpoints)
    @test any(item.near_breakpoint for item in diagnostics.breakpoints)
    @test any(finding.code == :near_droop_breakpoint for finding in diagnostics.findings)
    @test any(finding.code == :critical_contingency for finding in diagnostics.findings)
    @test any(startswith(string(finding.code), "binding_") for finding in diagnostics.findings)
    @test occursin("Droop breakpoint distances", markdown_report(diagnostics))

    corrupted = deepcopy(result)
    corrupted.states[:line_22].pg[1] += 0.01
    bad = scopf_diagnostics(study, corrupted)
    @test any(finding.code == :validation_failure && finding.scenario == :line_22
        for finding in bad.findings)
    @test_throws ArgumentError scopf_diagnostics(study, result; breakpoint_tolerance=-1.0)
    malformed = deepcopy(result)
    pop!(malformed.states[:line_22].vm)
    @test any(f -> f.code == :validation_failure && f.scenario == :line_22,
        scopf_diagnostics(study, malformed).findings)

    mktempdir() do directory
        path = write_scopf_diagnostics(joinpath(directory, "diagnostics.json"), diagnostics)
        text = read(path, String)
        @test occursin("DroopOPF.SCOPFDiagnostics", text)
        @test occursin("critical_contingency", text)
    end
end

@testset "M4 public PGLib regressions and benchmark metadata" begin
    function benchmark_case(filename)
        case = load_matpower_case(joinpath(@__DIR__, "data", "pglib", "v23.07", filename))
        reference_bus = only(bus.id for bus in case.network.buses if bus.reference)
        generator_index = findfirst(generator -> generator.bus_id == reference_bus, case.generators)
        generator = case.generators[generator_index]
        control = VoltVarDroop(VoltageSchedule(1.0; v_db_low=0.98, v_db_high=1.02),
            0.05, 0.0, ReactiveCapability(p_min=generator.p_min, p_max=generator.p_max,
                q_min=generator.q_min, q_max=generator.q_max))
        return attach_controls(case, [control], [GeneratorControlAttachment(generator.id, 1,
            RegulatedLocation(:bus, generator.bus_id))])
    end

    provenance = JSON.parsefile(joinpath(@__DIR__, "data", "pglib", "provenance.json"))
    @test provenance["version"] == "v23.07"
    @test provenance["license"] == "CC-BY-4.0"
    @test length(provenance["cases"]) == 2

    for filename in ("pglib_opf_case3_lmbd.m", "pglib_opf_case5_pjm.m")
        case = benchmark_case(filename)
        study = Study(case)
        result = solve_scopf(study)
        report = equilibrium_report(study, result)
        @test report.valid
        mktempdir() do directory
            restored_study = read_study(write_study(joinpath(directory, "study.json"), study))
            restored_result = read_scopf_result(write_scopf_result(
                joinpath(directory, "result.json"), result))
            @test equilibrium_report(restored_study, restored_result).valid
            @test isfile(write_scopf_report(joinpath(directory, "report.json"), report))
        end
    end

    measured = benchmark_scopf(Study(benchmark_case("pglib_opf_case3_lmbd.m"));
        samples=1, warmup=false)
    sample = only(measured.samples)
    @test sample.valid
    @test sample.variables > 0
    @test sample.constraints > sample.variables
    @test sample.elapsed_seconds >= 0
    @test sample.allocated_bytes > 0
    @test sample.process_peak_rss_bytes > 0
    @test occursin("process lifetime", measured.rss_scope)
    @test !isempty(measured.julia_version)
    @test !isempty(measured.package_version)
    mktempdir() do directory
        path = write_scopf_benchmark(joinpath(directory, "benchmark.json"), measured)
        @test occursin("DroopOPF.SCOPFBenchmarkReport", read(path, String))
    end
end
