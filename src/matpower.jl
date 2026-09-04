"""Minimal MATPOWER v2 reader for balanced AC network data."""
function _matpower_array(text::AbstractString, name::AbstractString)
    expression = Regex("mpc\\." * name * "\\s*=\\s*\\[(.*?)\\];", "s")
    match_result = match(expression, text)
    match_result === nothing &&
        throw(ArgumentError("MATPOWER case is missing mpc.$name"))
    rows = Vector{Vector{Float64}}()
    for raw_row in split(match_result.captures[1], ';')
        row = strip(split(raw_row, '%'; limit = 2)[1])
        isempty(row) && continue
        tokens = filter(!isempty, split(row, r"[\s,]+"))
        values = try
            parse.(Float64, tokens)
        catch error
            throw(ArgumentError("could not parse mpc.$name row `$(row)`: $error"))
        end
        push!(rows, values)
    end
    isempty(rows) && throw(ArgumentError("MATPOWER array mpc.$name is empty"))
    ncolumns = length(first(rows))
    all(length(row) == ncolumns for row in rows) ||
        throw(ArgumentError("MATPOWER array mpc.$name has inconsistent row widths"))
    result = Matrix{Float64}(undef, length(rows), ncolumns)
    for (i, row) in enumerate(rows)
        result[i, :] .= row
    end
    return result
end

function _matpower_scalar(text::AbstractString, name::AbstractString)
    expression = Regex("mpc\\." * name * "\\s*=\\s*([^;]+);")
    match_result = match(expression, text)
    match_result === nothing &&
        throw(ArgumentError("MATPOWER case is missing mpc.$name"))
    value = strip(split(match_result.captures[1], '%'; limit = 2)[1])
    try
        return parse(Float64, value)
    catch error
        throw(ArgumentError("could not parse MATPOWER scalar mpc.$name: $error"))
    end
end

function _matpower_case_id(path::AbstractString)
    filename = splitpath(path)[end]
    return replace(filename, r"\.[^.]*$" => "")
end

"""
    load_matpower_case(path; base_frequency = 50.0, id = nothing)

Load the core bus, generator, load, and branch tables from a MATPOWER v2 case
file. Values are normalized to the case base power. MATPOWER fields that are
not represented by the M1 domain model are intentionally ignored.

`RATE_A == 0` is treated as an unavailable thermal limit and represented by a
large finite limit so that the M1 model remains numerically well-defined.
"""
function load_matpower_case(
    path::AbstractString;
    base_frequency::Real = 50.0,
    id::Union{Nothing,AbstractString} = nothing,
)
    isfile(path) || throw(ArgumentError("MATPOWER case file does not exist: $path"))
    text = read(path, String)
    base_power = _matpower_scalar(text, "baseMVA")
    bus_table = _matpower_array(text, "bus")
    generator_table = _matpower_array(text, "gen")
    branch_table = _matpower_array(text, "branch")

    size(bus_table, 2) >= 13 || throw(ArgumentError("MATPOWER bus table needs 13 columns"))
    size(generator_table, 2) >= 10 ||
        throw(ArgumentError("MATPOWER generator table needs 10 columns"))
    size(branch_table, 2) >= 11 ||
        throw(ArgumentError("MATPOWER branch table needs 11 columns"))

    buses = Bus[]
    loads = Load[]
    for row in eachrow(bus_table)
        bus_id = round(Int, row[1])
        bus_type = round(Int, row[2])
        v_max, v_min = row[12], row[13]
        push!(buses, Bus(bus_id; v_min = v_min, v_max = v_max, reference = bus_type == 3))
        if !iszero(row[3]) || !iszero(row[4])
            push!(loads, Load(length(loads) + 1, bus_id; p = row[3] / base_power, q = row[4] / base_power))
        end
    end

    generators = Generator[]
    for row in eachrow(generator_table)
        generator_id = length(generators) + 1
        bus_id = round(Int, row[1])
        available = row[8] > 0
        p_min, p_max = row[10] / base_power, row[9] / base_power
        q_min, q_max = row[5] / base_power, row[4] / base_power
        push!(
            generators,
            Generator(
                generator_id,
                bus_id;
                available = available,
                p_min = p_min,
                p_max = p_max,
                q_min = q_min,
                q_max = q_max,
                # MATPOWER's reported QG can be outside the capability box;
                # treat it as a warm-start hint and keep the domain invariant.
                initial_p = clamp(row[2] / base_power, p_min, p_max),
                initial_q = clamp(row[3] / base_power, q_min, q_max),
            ),
        )
    end

    branches = Branch[]
    for row in eachrow(branch_table)
        rate = row[6] > 0 ? row[6] / base_power : 1.0e6
        push!(
            branches,
            Branch(
                length(branches) + 1,
                round(Int, row[1]),
                round(Int, row[2]);
                resistance = row[3],
                reactance = row[4],
                charging = row[5],
                thermal_limit = rate,
                available = row[11] > 0,
            ),
        )
    end

    network = ACNetwork(buses, branches)
    return Case(
        isnothing(id) ? _matpower_case_id(path) : id;
        base_power = base_power,
        base_frequency = base_frequency,
        network = network,
        loads = loads,
        generators = generators,
        controls = VoltVarDroop[],
        attachments = GeneratorControlAttachment[],
    )
end

"""Return a copy of `case` with the supplied M1 generator controls attached."""
function attach_controls(
    case::Case,
    controls::AbstractVector{<:VoltVarDroop},
    attachments::AbstractVector{<:GeneratorControlAttachment},
)
    return Case(
        case.id;
        base_power = case.base_power,
        base_frequency = case.base_frequency,
        network = case.network,
        loads = case.loads,
        generators = case.generators,
        controls = controls,
        attachments = attachments,
    )
end
