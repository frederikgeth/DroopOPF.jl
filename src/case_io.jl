import SHA

export NativeBackend, PowerIOBackend, ImportOptions, CaseImport, CaseIOMetadata
export CaseSource, CaseIODiagnostic, CaseIOError, import_case, load_case

abstract type AbstractCaseIOBackend end

"""The existing RAW/MATPOWER readers, retained during the PowerIO migration."""
struct NativeBackend <: AbstractCaseIOBackend end

"""The PowerIO integration. Load `using PowerIO` before selecting this backend."""
struct PowerIOBackend <: AbstractCaseIOBackend end

"""Validated common import policy. `unrated_limit_pu` must be explicit for
zero/omitted branch ratings. `base_frequency` overrides the source/default
frequency when supplied; MATPOWER otherwise uses 50 Hz for native compatibility.
"""
struct ImportOptions
    unrated_limit_pu::Union{Nothing,Float64}
    base_frequency::Union{Nothing,Float64}
    id::Union{Nothing,String}
    function ImportOptions(; unrated_limit_pu=nothing, base_frequency=nothing, id=nothing)
        for (name, value) in ((:unrated_limit_pu, unrated_limit_pu), (:base_frequency, base_frequency))
            isnothing(value) || (value isa Real && !(value isa Bool) && isfinite(value) && value > 0) ||
                throw(ArgumentError("$name must be positive and finite, or nothing"))
        end
        isnothing(id) || (id isa AbstractString && !isempty(strip(id))) ||
            throw(ArgumentError("id must be a nonempty string, or nothing"))
        new(isnothing(unrated_limit_pu) ? nothing : Float64(unrated_limit_pu),
            isnothing(base_frequency) ? nothing : Float64(base_frequency),
            isnothing(id) ? nothing : String(id))
    end
end

"""One import/export finding with a stable code and optional upstream code."""
struct CaseIODiagnostic
    code::Symbol
    stage::Symbol
    severity::Symbol
    message::String
    component::Union{Nothing,String}
    upstream_code::Union{Nothing,String}
end

_io_diagnostic(code, stage, message; severity=:warning, component=nothing, upstream_code=nothing) =
    CaseIODiagnostic(code, stage, severity, String(message), component, upstream_code)

"""An error at the case exchange boundary; inspect `code`, `stage` and diagnostics."""
struct CaseIOError <: Exception
    code::Symbol
    stage::Symbol
    message::String
    diagnostics::Vector{CaseIODiagnostic}
end
Base.showerror(io::IO, e::CaseIOError) = print(io, e.code, " (", e.stage, "): ", e.message)
_io_error(code, stage, message; diagnostics=CaseIODiagnostic[]) =
    throw(CaseIOError(code, stage, String(message), copy(diagnostics)))

"""Source identity and parser versions for a single immutable input snapshot."""
struct CaseSource
    backend::Symbol
    format::Symbol
    revision::Union{Nothing,Int}
    path::String
    sha256::String
    parser_version::String
    library_version::Union{Nothing,String}
end

"""Julia-owned source evidence. Ratings are original MVA, with `nothing` for
unknown/unrated branches. Saved-field presence is `:supplied`, `:defaulted`
or `:unknown`, in returned bus/generator order. This evidence is separate from
the effective limits and start hints in `Case`.
"""
struct CaseIOMetadata
    bus_base_kv::Dict{Int,Float64}
    bus_names::Dict{Int,String}
    bus_areas::Dict{Int,Int}
    bus_zones::Dict{Int,Int}
    generator_machine_base_mva::Dict{Int,Float64}
    branch_rating_mva::Dict{Int,Union{Nothing,Float64}}
    saved_field_presence::Dict{Symbol,Vector{Symbol}}
end
CaseIOMetadata() = CaseIOMetadata(Dict{Int,Float64}(), Dict{Int,String}(),
    Dict{Int,Int}(), Dict{Int,Int}(), Dict{Int,Float64}(),
    Dict{Int,Union{Nothing,Float64}}(), Dict{Symbol,Vector{Symbol}}())

"""A converted case, unmodified supplied state, source identities and evidence.
`initial_state` is not a claim of feasibility or complete saved-state evidence.
Identity values are backend-specific source identifiers, keyed by domain ID.
"""
struct CaseImport{T<:Real}
    case::Case{T}
    initial_state::ACState{T}
    source_ids::Dict{Symbol,Dict{Int,Any}}
    metadata::CaseIOMetadata
    diagnostics::Vector{CaseIODiagnostic}
    source::CaseSource
    identity_signature::String
    validation_signature::String
end
CaseImport(c, state, ids, metadata, diagnostics, source) =
    CaseImport(c, state, ids, metadata, diagnostics, source, _io_identity_signature(c),
        _io_import_validation_signature(c, state, metadata))

_io_identities() = Dict(k => Dict{Int,Any}() for k in (:bus, :load, :generator, :branch, :shunt))

function _io_format(path, format)
    format in (:auto, :psse, :matpower) ||
        _io_error(:unsupported_format, :options, "supported formats are :psse and :matpower")
    format != :auto && return format
    ext = lowercase(splitext(path)[2])
    ext == ".raw" && return :psse
    ext == ".m" && return :matpower
    _io_error(:unknown_format, :options, "cannot infer case format; supply format=:psse or :matpower")
end

"""
    import_case(path; backend=NativeBackend(), format=:auto, options=ImportOptions())

Read one RAW or MATPOWER case without solving or certifying its saved state.
Both pathways return `CaseImport`. Zero/omitted thermal ratings require an
explicit `unrated_limit_pu`; this policy does not change legacy loaders.
PowerIO is optional during migration and requires `using PowerIO`.
"""
function import_case(path::AbstractString; backend::AbstractCaseIOBackend=NativeBackend(),
    format::Symbol=:auto, options::ImportOptions=ImportOptions())
    fmt = _io_format(path, format)
    # Read once: parsing, metadata and digest refer to the same bytes.
    bytes = try
        read(path)
    catch err
        err isa SystemError || err isa Base.IOError || rethrow()
        _io_error(:source_read_error, :read, sprint(showerror, err))
    end
    try
        _import_case(backend, bytes, abspath(path), fmt, options)
    catch err
        err isa ArgumentError || rethrow()
        _io_error(:invalid_case_data, :convert, sprint(showerror, err))
    end
end

"""Read a case through `import_case` and return only its `Case`.
Retain `CaseImport` instead when source metadata or supplied state is needed.
"""
load_case(path::AbstractString; kwargs...) = import_case(path; kwargs...).case

function _import_case(::PowerIOBackend, bytes, path, format, options)
    _io_error(:backend_unavailable, :dependency,
        "PowerIO backend is not loaded; install PowerIO and run `using PowerIO`")
end

function _io_rating(value, base, options, diagnostics, identity)
    isfinite(value) && value >= 0 || _io_error(:invalid_rating, :convert, "negative/nonfinite rating for $identity")
    value > 0 && return value / base
    isnothing(options.unrated_limit_pu) &&
        _io_error(:unrated_branch, :convert, "unrated branch $identity requires explicit unrated_limit_pu")
    push!(diagnostics, _io_diagnostic(:unrated_limit_applied, :convert,
        "explicit unrated_limit_pu=$(options.unrated_limit_pu) used; source rating remains unknown";
        component=string(identity)))
    options.unrated_limit_pu
end

# A source envelope guard, not an electrical parser. Unknown MATPOWER extension
# assignments must not silently disappear in either backend. Numerical tables
# remain the selected backend's responsibility.
function _io_matpower_envelope(bytes, diagnostics)
    text = replace(String(copy(bytes)), r"%[^\r\n]*" => "")
    core = ("version", "baseMVA", "bus", "gen", "branch")
    annotations = ("bus_name", "gentype", "genfuel", "gencost")
    for m in eachmatch(r"\bmpc\.([A-Za-z_]\w*)\s*=\s*", text)
        name = m.captures[1]
        name in core && continue
        if name in annotations
            push!(diagnostics, _io_diagnostic(:study_metadata_unmodeled, :convert,
                "mpc.$name is outside the static electrical profile; source costs do not configure the DroopOPF objective";
                component="mpc.$name"))
        else
            rest = SubString(text, m.offset + ncodeunits(m.match))
            occursin(r"^\[\s*\]\s*;", rest) && continue
            _io_error(:unsupported_matpower_extension, :convert,
                "mpc.$name requires a separately qualified model projection"; diagnostics)
        end
    end
end

function _io_angle_limits(lower, upper, available, identity)
    available || return
    ((iszero(lower) && iszero(upper)) || (lower <= -360 && upper >= 360)) && return
    _io_error(:unsupported_angle_limits, :convert,
        "branch $identity has angle-difference constraints not represented by Case")
end

function _io_generator(id, bus; available, p, q, pmin, pmax, qmin, qmax, diagnostics)
    if !(pmin <= p <= pmax && qmin <= q <= qmax)
        push!(diagnostics, _io_diagnostic(:start_hint_clamped, :convert,
            "supplied P/Q retained; only optimizer start hint clamped"; component="generator:$id"))
    end
    Generator(id, bus; available, p_min=pmin, p_max=pmax, q_min=qmin, q_max=qmax,
        initial_p=clamp(p, pmin, pmax), initial_q=clamp(q, qmin, qmax))
end

function _io_state(buses, vm, va_degrees, pg, qg)
    refs = findall(b -> b.reference, buses)
    length(refs) == 1 || _io_error(:reference_bus, :convert, "requires exactly one energized reference bus")
    va = deg2rad.(va_degrees)
    ACState(Float64.(vm), va .- va[only(refs)], Float64.(pg), Float64.(qg))
end

function _io_source(backend, bytes, path, format; revision=nothing,
    parser_version=string(pkgversion(@__MODULE__)), library_version=nothing)
    CaseSource(backend, format, revision, path, bytes2hex(SHA.sha256(bytes)), parser_version, library_version)
end

function _import_case(::NativeBackend, bytes, path, format, options)
    format == :psse && return _import_native_psse(bytes, path, options)
    _import_native_matpower(bytes, path, options)
end

function _import_native_psse(bytes, path, options)
    raw = parse_psse_raw(IOBuffer(bytes); source=path)
    imported = import_psse_case(raw; id=options.id, unrated_limit=options.unrated_limit_pu)
    c = imported.case
    metadata = CaseIOMetadata()
    busrows = Dict(r.fields[:I] => r.fields for r in raw.sections[:bus])
    genrows = Dict((r.fields[:I], get(r.fields, :ID, "1")) => r.fields
        for r in get(raw.sections, :generator, PSSERecord[]))
    branchrows = Dict{Any,Any}()
    for (section, kind) in ((:branch, :line), (:transformer, :transformer)), r in get(raw.sections, section, PSSERecord[])
        f = r.fields
        branchrows[(kind, abs(f[:I]), abs(f[:J]), get(f, :CKT, "1"))] = f
    end
    for b in c.network.buses
        f = busrows[b.id]
        metadata.bus_base_kv[b.id] = get(f, :BASKV, 0.)
        metadata.bus_names[b.id] = get(f, :NAME, "")
        metadata.bus_areas[b.id] = get(f, :AREA, 1)
        metadata.bus_zones[b.id] = get(f, :ZONE, 1)
    end
    for g in c.generators
        metadata.generator_machine_base_mva[g.id] = get(genrows[imported.source_ids[:generator][g.id]], :MBASE, raw.base_power)
    end
    for b in c.network.branches
        f = branchrows[imported.source_ids[:branch][b.id]]
        rating = get(f, b.kind == :transformer ? :RATE1_1 : :RATE1, 0.)
        metadata.branch_rating_mva[b.id] = rating > 0 ? rating : nothing
    end
    for key in (:VM, :VA)
        metadata.saved_field_presence[key] = [haskey(busrows[b.id], key) ? :supplied : :defaulted for b in c.network.buses]
    end
    for key in (:PG, :QG)
        metadata.saved_field_presence[key] = [haskey(genrows[imported.source_ids[:generator][g.id]], key) ? :supplied : :defaulted for g in c.generators]
    end
    diagnostics = [_io_diagnostic(:native_import_notice, :convert, message) for message in imported.diagnostics]
    if !isnothing(options.base_frequency)
        c = Case(c.id; base_power=c.base_power, base_frequency=options.base_frequency,
            network=c.network, loads=c.loads, generators=c.generators, controls=c.controls, attachments=c.attachments)
        push!(diagnostics, _io_diagnostic(:frequency_overridden, :convert, "source frequency overridden explicitly"))
    end
    CaseImport(c, imported.initial_state, imported.source_ids, metadata, diagnostics,
        _io_source(:native, bytes, path, :psse; revision=raw.revision))
end

function _import_native_matpower(bytes, path, options)
    diagnostics = CaseIODiagnostic[]
    _io_matpower_envelope(bytes, diagnostics)
    text = String(copy(bytes))
    base = _matpower_scalar(text, "baseMVA")
    isfinite(base) && base > 0 || _io_error(:invalid_base, :convert, "baseMVA must be positive and finite")
    bt, gt, rt = (_matpower_array(text, name) for name in ("bus", "gen", "branch"))
    size(bt, 2) >= 13 && size(gt, 2) >= 10 && size(rt, 2) >= 11 ||
        _io_error(:invalid_tables, :parse, "incomplete MATPOWER core tables")
    all(isfinite, bt) && all(isfinite, gt) && all(isfinite, rt) ||
        _io_error(:invalid_tables, :convert, "nonfinite MATPOWER core value")
    int(x) = isinteger(x) ? Int(x) : _io_error(:invalid_identifier, :convert, "nonintegral identifier/status")
    ids = _io_identities(); metadata = CaseIOMetadata()
    buses = Bus[]; loads = Load[]; shunts = FixedShunt[]; generators = Generator[]; branches = Branch[]
    allbus = Set(int(row[1]) for row in eachrow(bt))
    length(allbus) == size(bt, 1) || _io_error(:duplicate_identity, :convert, "duplicate MATPOWER bus ID")
    active = Set(int(row[1]) for row in eachrow(bt) if row[2] != 4)
    function buscheck(i)
        i in allbus || _io_error(:unknown_bus, :convert, "equipment references unknown bus $i")
        i in active
    end
    vm = Float64[]; va = Float64[]; pg = Float64[]; qg = Float64[]
    for row in eachrow(bt)
        i, kind = int(row[1]), int(row[2])
        kind in (1, 2, 3, 4) || _io_error(:unsupported_bus_type, :convert, "unknown MATPOWER bus type $kind")
        kind == 4 && continue
        push!(buses, Bus(i; v_min=row[13], v_max=row[12], reference=kind==3)); ids[:bus][i] = i
        push!(vm, row[8]); push!(va, row[9])
        metadata.bus_base_kv[i] = row[10]; metadata.bus_names[i] = string(i)
        metadata.bus_areas[i] = int(row[7]); metadata.bus_zones[i] = int(row[11])
        if !iszero(row[3]) || !iszero(row[4])
            lid = length(loads)+1
            push!(loads, Load(lid, i; p=row[3]/base, q=row[4]/base)); ids[:load][lid] = (:bus_load, i)
        end
        if !iszero(row[5]) || !iszero(row[6])
            sid = length(shunts)+1
            push!(shunts, FixedShunt(sid, i; conductance=row[5]/base, susceptance=row[6]/base))
            ids[:shunt][sid] = (:bus_shunt, i)
        end
    end
    length(active) == length(allbus) || push!(diagnostics, _io_diagnostic(
        :isolated_equipment_excluded, :convert, "isolated buses and attached equipment excluded from energized model"))
    for (i, row) in enumerate(eachrow(gt))
        buscheck(int(row[1])) || continue
        int(row[8]) in (0, 1) || _io_error(:invalid_status, :convert, "generator status must be 0 or 1")
        if row[8] == 1 && length(row) >= 16 && any(!iszero, row[11:16])
            _io_error(:unsupported_generator_capability, :convert, "generator row $i has a nonrectangular capability curve")
        end
        push!(generators, _io_generator(i, int(row[1]); available=row[8]==1,
            p=row[2]/base, q=row[3]/base, pmin=row[10]/base, pmax=row[9]/base,
            qmin=row[5]/base, qmax=row[4]/base, diagnostics))
        ids[:generator][i] = (:generator_row, i); metadata.generator_machine_base_mva[i] = row[7]
        push!(pg, row[2]/base); push!(qg, row[3]/base)
    end
    for (i, row) in enumerate(eachrow(rt))
        a = buscheck(int(row[1])); z = buscheck(int(row[2]))
        a && z || continue
        int(row[11]) in (0, 1) || _io_error(:invalid_status, :convert, "branch status must be 0 or 1")
        length(row) >= 13 && _io_angle_limits(row[12], row[13], row[11]==1, i)
        rate = _io_rating(row[6], base, options, diagnostics, "branch:$i")
        kind = !iszero(row[9]) || !iszero(row[10]) ? :transformer : :line
        push!(branches, Branch(i, int(row[1]), int(row[2]); resistance=row[3], reactance=row[4],
            charging=row[5], thermal_limit=rate, available=row[11]==1,
            tap_ratio=iszero(row[9]) ? 1. : row[9], phase_shift=deg2rad(row[10]), kind))
        ids[:branch][i] = (:branch_row, i); metadata.branch_rating_mva[i] = row[6]>0 ? row[6] : nothing
    end
    for key in (:VM, :VA); metadata.saved_field_presence[key] = fill(:supplied, length(buses)); end
    for key in (:PG, :QG); metadata.saved_field_presence[key] = fill(:supplied, length(generators)); end
    c = Case(something(options.id, _matpower_case_id(path)); base_power=base,
        base_frequency=something(options.base_frequency, 50.), network=ACNetwork(buses, branches; shunts),
        loads, generators, controls=VoltVarDroop[], attachments=GeneratorControlAttachment[])
    state = _io_state(buses, vm, va, pg, qg)
    CaseImport(c, state, ids, metadata, diagnostics, _io_source(:native, bytes, path, :matpower))
end
