"""One measured SCOPF solve, including actual JuMP model size and allocations."""
struct SCOPFBenchmarkSample
    sample::Int
    elapsed_seconds::Float64
    allocated_bytes::Int
    gc_seconds::Float64
    variables::Int
    constraints::Int
    objective::Float64
    termination_status::Symbol
    valid::Bool
    process_peak_rss_bytes::Int
end

"""Reproducible environment, structural size, and samples for one SCOPF study."""
struct SCOPFBenchmarkReport
    case_id::String
    julia_version::String
    package_version::String
    solver::String
    rss_scope::String
    scenario_count::Int
    bus_count::Int
    branch_count::Int
    generator_count::Int
    samples::Vector{SCOPFBenchmarkSample}
end

function _measured_scopf_solve(study, sample; kwargs...)
    model_size = Ref((variables=0, constraints=0))
    hook = model -> (model_size[] = (
        variables=JuMP.num_variables(model),
        constraints=JuMP.num_constraints(model; count_variable_in_set_constraints=true)))
    measurement = @timed solve_scopf(study; _model_hook=hook, kwargs...)
    result = measurement.value
    report = equilibrium_report(study, result)
    return result, SCOPFBenchmarkSample(sample, measurement.time,
        measurement.bytes, measurement.gctime, model_size[].variables,
        model_size[].constraints, result.objective, result.termination_status, report.valid,
        Int(Sys.maxrss()))
end

"""
    benchmark_scopf(study; samples=3, warmup=true, ...)

Measure complete model construction, optimization, and result extraction. The
optional warm-up solve is excluded. Allocation bytes are Julia allocations, not
process peak RSS. `process_peak_rss_bytes` separately records the operating
system's lifetime process high-water mark, including compilation, warm-up,
solver native memory, and validation. It is not a per-solve increment. Run
different studies in fresh processes for comparable peaks.
Model size is counted from the actual JuMP model passed to the
optimizer. Solver keywords are forwarded to `solve_scopf`.
"""
function benchmark_scopf(study::Study; samples::Integer=3, warmup::Bool=true, kwargs...)
    samples > 0 || throw(ArgumentError("benchmark samples must be positive"))
    warmup && _measured_scopf_solve(study, 0; kwargs...)
    records = SCOPFBenchmarkSample[]
    solver = "unknown"
    for sample in 1:samples
        result, record = _measured_scopf_solve(study, sample; kwargs...)
        solver = result.solver
        push!(records, record)
    end
    return SCOPFBenchmarkReport(study.case.id, string(VERSION),
        string(Base.pkgversion(@__MODULE__)), solver,
        "process lifetime; includes compilation, warm-up, solves and validation",
        1 + length(study.contingencies),
        length(study.case.network.buses), length(study.case.network.branches),
        length(study.case.generators), records)
end

_json_data(sample::SCOPFBenchmarkSample) = Dict(string(field) =>
    _json_data(getfield(sample, field)) for field in fieldnames(typeof(sample)))
_json_data(report::SCOPFBenchmarkReport) = Dict(string(field) =>
    _json_data(getfield(report, field)) for field in fieldnames(typeof(report)))

"""Write reproducible SCOPF benchmark metadata and samples to versioned JSON."""
write_scopf_benchmark(path::AbstractString, report::SCOPFBenchmarkReport) =
    _write_scopf_json(path, "DroopOPF.SCOPFBenchmarkReport", report)

function markdown_report(report::SCOPFBenchmarkReport)
    lines = ["# SCOPF benchmark: $(report.case_id)", "",
        "- Julia: $(report.julia_version)", "- DroopOPF: $(report.package_version)",
        "- Solver: $(report.solver)",
        "- Peak RSS scope: $(report.rss_scope)",
        "- Structure: $(report.scenario_count) scenarios, $(report.bus_count) buses, $(report.branch_count) branches, $(report.generator_count) generators", "",
        "| Sample | Seconds | Allocated bytes | GC seconds | Variables | Constraints | Valid | Objective | Process peak RSS bytes |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for sample in report.samples
        push!(lines, "| $(sample.sample) | $(sample.elapsed_seconds) | $(sample.allocated_bytes) | $(sample.gc_seconds) | $(sample.variables) | $(sample.constraints) | $(sample.valid) | $(sample.objective) | $(sample.process_peak_rss_bytes) |")
    end
    return join(lines, "\n")
end
