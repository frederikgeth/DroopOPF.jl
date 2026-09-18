using DroopOPF

include("m2_case.jl")

output_directory = isempty(ARGS) ? mktempdir(prefix="droopopf-m4-benchmark-") : abspath(first(ARGS))
mkpath(output_directory)

function controlled_pglib_case(filename)
    path = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07", filename)
    case = load_matpower_case(path)
    reference_bus = only(bus.id for bus in case.network.buses if bus.reference)
    generator = case.generators[findfirst(g -> g.bus_id == reference_bus, case.generators)]
    control = VoltVarDroop(VoltageSchedule(1.0; v_db_low=0.98, v_db_high=1.02),
        0.05, 0.0, ReactiveCapability(p_min=generator.p_min, p_max=generator.p_max,
            q_min=generator.q_min, q_max=generator.q_max))
    return attach_controls(case, [control], [GeneratorControlAttachment(generator.id, 1,
        RegulatedLocation(:bus, generator.bus_id))])
end

studies = Dict(
    :pglib_case3 => Study(controlled_pglib_case("pglib_opf_case3_lmbd.m")),
    :pglib_case5 => Study(controlled_pglib_case("pglib_opf_case5_pjm.m")),
    :m2_full => Study(m2_case(); contingencies=[
        Contingency(:line_22; branch_ids=[22]),
        Contingency(:generator_9; generator_ids=[9]),
    ], participation=Dict(7=>1.0, 9=>1.0)),
)

for name in sort(collect(keys(studies)); by=string)
    if length(ARGS) < 2
        # Each study gets a fresh process: OS peak RSS cannot be reset between studies.
        project = dirname(@__DIR__)
        run(`$(Base.julia_cmd()) --project=$project $(@__FILE__) $output_directory $(string(name))`)
        continue
    end
    string(name) == ARGS[2] || continue
    report = benchmark_scopf(studies[name]; samples=3, warmup=true)
    all(sample.valid for sample in report.samples) || error("$(name) benchmark did not validate")
    write_scopf_benchmark(joinpath(output_directory, "$(name).json"), report)
    write(joinpath(output_directory, "$(name).md"), markdown_report(report) * "\n")
    println(name, ": ", first(report.samples).variables, " variables, ",
        first(report.samples).constraints, " constraints")
end

cp(joinpath(@__DIR__, "..", "test", "data", "pglib", "provenance.json"),
    joinpath(output_directory, "pglib_provenance.json"); force=true)
println("Artifacts: ", output_directory)
