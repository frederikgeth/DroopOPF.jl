include(joinpath(@__DIR__, "m10_contingency_baseline.jl"))

"""
Run a public-network reliability campaign through the integrated pipeline.
Indices refer to the full catalog, including islanding entries. Use a new
directory for old-format campaigns; their evidence is not overwritten.
For arbitrary/small networks use `run_contingency_campaign(output, case, base)`.
"""
function m10_contingency_campaign(name::AbstractString, output::AbstractString;
    first_index::Integer=1, last_index::Union{Nothing,Integer}=nothing,
    base_cache::Union{Nothing,AbstractString}=nothing,
    base_max_cpu_time::Real=120.0, scenario_max_cpu_time::Real=120.0,
    max_iter::Integer=1000, screening_enabled::Bool=true,
    audit_screened_ids::AbstractVector{Symbol}=Symbol[])
    all(x -> isfinite(x) && x > 0, (base_max_cpu_time, scenario_max_cpu_time)) ||
        throw(ArgumentError("time limits must be positive and finite"))
    max_iter > 0 || throw(ArgumentError("max_iter must be positive"))
    source = m10_source(name)
    case = load_matpower_case(source; base_frequency=60.0)
    catalog = contingency_catalog(case)
    final_index = isnothing(last_index) ? length(catalog.entries) : Int(last_index)
    1 <= first_index <= final_index <= length(catalog.entries) ||
        throw(ArgumentError("requested range must lie within the full catalog"))
    selected = ContingencyCatalog(case.id, catalog.entries[first_index:final_index])
    cache_path = isnothing(base_cache) ?
        joinpath(dirname(abspath(output)), "ieee$(name)-base-state.json") : abspath(base_cache)
    mkpath(dirname(cache_path))
    base = if isfile(cache_path)
        m10_read_base_cache(cache_path, source, case)
    else
        result = solve_opf(case; optimizer_attributes=Dict(
            "max_cpu_time"=>Float64(base_max_cpu_time),
            "max_wall_time"=>Float64(base_max_cpu_time), "max_iter"=>Int(max_iter)))
        m10_write_base_cache(cache_path, source, case, result)
    end
    run_contingency_campaign(output, case, base.state; catalog=selected,
        screening_enabled, audit_screened_ids,
        optimizer_attributes=Dict("max_cpu_time"=>Float64(scenario_max_cpu_time),
            "max_wall_time"=>Float64(scenario_max_cpu_time), "max_iter"=>Int(max_iter)),
        on_checkpoint=a -> println("$(a.entry.contingency.id): $(a.rank.classification) (checkpoint saved)"))
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    name = get(ARGS, 1, "118")
    output = abspath(get(ARGS, 2, joinpath(pwd(), "m10_contingency_campaign")))
    first_index = parse(Int, get(ARGS, 3, "1"))
    last_argument = get(ARGS, 4, "all")
    last_index = last_argument == "all" ? nothing : parse(Int, last_argument)
    scenario_seconds = parse(Float64, get(ARGS, 5, "120"))
    max_iter = parse(Int, get(ARGS, 6, "1000"))
    m10_contingency_campaign(name, output; first_index, last_index,
        scenario_max_cpu_time=scenario_seconds, max_iter)
end
