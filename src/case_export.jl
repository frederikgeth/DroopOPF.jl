import JSON

export ExportOptions, ExportStateContext, BoundExportState, ExportPlan
export export_state_context, bind_export_state, prepare_export, write_export, export_case

"""Export policies. State must be bound explicitly, or select
`state_policy=:initial_guess`. `control_policy=:snapshot` permits a static
projection of droop/shunt controls. For imported unrated branches choose
`rating_policy=:source` (zero/unrated) or `:effective` (adopt the case limit).
"""
struct ExportOptions
    state_policy::Symbol
    control_policy::Symbol
    rating_policy::Symbol
    function ExportOptions(; state_policy=:explicit, control_policy=:reject, rating_policy=:reject)
        state_policy in (:explicit, :initial_guess) || throw(ArgumentError("invalid state_policy"))
        control_policy in (:reject, :snapshot) || throw(ArgumentError("invalid control_policy"))
        rating_policy in (:reject, :source, :effective) || throw(ArgumentError("invalid rating_policy"))
        new(state_policy, control_policy, rating_policy)
    end
end

# Explicit ordered encodings avoid process-dependent hash values and unordered
# dictionary iteration. The identity encoding intentionally excludes settings.
function _io_identity_signature(c::Case)
    n = c.network
    data = (schema=1, base=c.base_power,
        buses=isnothing(n) ? [] : [b.id for b in n.buses],
        branches=isnothing(n) ? [] : [(b.id,b.from_bus,b.to_bus,b.kind) for b in n.branches],
        shunts=isnothing(n) ? [] : [(s.id,s.bus_id) for s in n.shunts],
        banks=isnothing(n) ? [] : [(s.id,s.bus_id) for s in n.banks],
        loads=[(l.id,l.bus_id) for l in c.loads], generators=[(g.id,g.bus_id) for g in c.generators])
    bytes2hex(SHA.sha256(codeunits(JSON.json(data))))
end

function _io_model_encoding(x)
    x isa Symbol && return JSON.json(string(x))
    x isa Union{Nothing,Real,AbstractString} && return JSON.json(x)
    x isa Union{AbstractVector,Tuple} && return "["*join(_io_model_encoding.(x), ",")*"]"
    "["*JSON.json(string(nameof(typeof(x))))*","*
        join((_io_model_encoding(getfield(x,f)) for f in fieldnames(typeof(x))), ",")*"]"
end
_io_model_signature(c) = bytes2hex(SHA.sha256(codeunits("DroopOPF.ExportState.v1:"*_io_model_encoding(c))))

"""Captured case signature and state vector ordering. Capture before solving."""
struct ExportStateContext
    signature::String
    bus_ids::Tuple{Vararg{Int}}
    generator_ids::Tuple{Vararg{Int}}
end

"""A copied state with caller-declared provenance from an `ExportStateContext`."""
struct BoundExportState{T<:Real}
    state::ACState{T}
    context::ExportStateContext
end

"""Capture the exact model and ordering against which an exported state is computed."""
function export_state_context(c::Case)
    isnothing(c.network) && _io_error(:missing_network, :export, "case has no AC network")
    ExportStateContext(_io_model_signature(c), Tuple(b.id for b in c.network.buses), Tuple(g.id for g in c.generators))
end

"""Copy a state and declare its originating case context. Dimension checks do
not prove origin: the caller must bind the context used for that computation.
"""
function bind_export_state(s::ACState, context::ExportStateContext)
    length(s.vm) == length(context.bus_ids) && length(s.pg) == length(context.generator_ids) ||
        _io_error(:state_shape_mismatch, :export, "state dimensions do not match captured case")
    BoundExportState(ACState(s.vm,s.va,s.pg,s.qg), context)
end

"""Prepared single-file bytes and diagnostics. `accepted` must be true to write.
Bytes are independent of later case changes; a checksum detects plan mutation.
`fidelity` describes a static AC projection, not a complete DroopOPF study.
"""
struct ExportPlan
    format::Symbol
    bytes::Vector{UInt8}
    sha256::String
    diagnostics::Vector{CaseIODiagnostic}
    accepted::Bool
    fidelity::Symbol
    writer_fidelity::String
    source_path::Union{Nothing,String}
end

"""
    prepare_export(case; backend=PowerIOBackend(), format, context=nothing,
                   metadata=nothing, state=nothing, revision=33, options=ExportOptions())

Prepare canonical MATPOWER/RAW33 output in memory. Supply a `CaseImport` context
or Julia-owned `CaseIOMetadata`, and bind an explicit state or request an
initial guess. No destination is modified. Requires `using PowerIO`.
"""
function prepare_export(c::Case; backend::AbstractCaseIOBackend=PowerIOBackend(),
    format::Symbol, context::Union{Nothing,CaseImport}=nothing,
    metadata::Union{Nothing,CaseIOMetadata}=nothing, state::Union{Nothing,BoundExportState}=nothing,
    revision::Integer=33, options::ExportOptions=ExportOptions())
    format in (:matpower,:psse) || _io_error(:unsupported_format, :export, "export supports :matpower and :psse")
    revision==33 || _io_error(:unsupported_revision, :export, "initial RAW writer profile supports revision 33")
    isnothing(c.network) && _io_error(:missing_network, :export, "case has no AC network")
    !isnothing(context) && !isnothing(metadata) && throw(ArgumentError("supply context or metadata, not both"))
    if !isnothing(context)
        context.identity_signature == _io_identity_signature(c) ||
            _io_error(:context_mismatch, :export, "equipment identity/order or power base changed; supply explicit export metadata")
    end
    md = isnothing(context) ? metadata : context.metadata
    isnothing(md) && _io_error(:missing_metadata, :export, "supply import context or explicit CaseIOMetadata")
    diagnostics = CaseIODiagnostic[]
    if !isempty(c.controls) || !isempty(c.attachments) || !isempty(c.network.banks)
        options.control_policy == :snapshot ||
            _io_error(:control_projection_required, :export, "droop/shunt controls require control_policy=:snapshot")
        push!(diagnostics, _io_diagnostic(:controls_projected_to_snapshot, :export,
            "static electrical settings exported; droop curves and legal switching states omitted"))
    end
    if isnothing(state)
        options.state_policy == :initial_guess ||
            _io_error(:explicit_state_required, :export, "bind a state or explicitly select state_policy=:initial_guess")
        s = ACState(ones(length(c.network.buses)), zeros(length(c.network.buses)),
            [g.initial_p for g in c.generators], [g.initial_q for g in c.generators])
        push!(diagnostics, _io_diagnostic(:initial_guess_exported, :export, "exported state is an initial guess, not a solved state"))
    else
        captured = export_state_context(c)
        (state.context.signature == captured.signature && state.context.bus_ids == captured.bus_ids &&
            state.context.generator_ids == captured.generator_ids) ||
            _io_error(:state_context_mismatch, :export, "state belongs to a different case or ordering")
        s = state.state
        length(s.vm)==length(c.network.buses) && length(s.pg)==length(c.generators) ||
            _io_error(:state_shape_mismatch, :export, "bound state dimensions changed")
        # Revalidate mutable arrays and copy before crossing the backend boundary.
        s = ACState(s.vm,s.va,s.pg,s.qg)
    end
    _prepare_export(backend, c, md, context, s, format, options, diagnostics)
end

_prepare_export(::NativeBackend, args...) = _io_error(:unsupported_operation, :export, "native export is unavailable; use PowerIOBackend()")
_prepare_export(::PowerIOBackend, args...) = _io_error(:backend_unavailable, :dependency, "install PowerIO and run `using PowerIO`")

function _io_output_path(path)
    path = abspath(path)
    ispath(path) ? realpath(path) : joinpath(realpath(dirname(path)),basename(path))
end

"""Write an accepted single-file export plan. Existing destinations require
`overwrite=true`; source aliases and symlink destinations are always rejected.
Preparation failures never modify destination bytes.
"""
function write_export(path::AbstractString, plan::ExportPlan; overwrite::Bool=false)
    try
        _write_export(path,plan;overwrite)
    catch err
        err isa SystemError || err isa Base.IOError || rethrow()
        _io_error(:destination_write_error,:write,sprint(showerror,err))
    end
end

function _write_export(path, plan; overwrite)
    plan.accepted || _io_error(:export_loss_rejected, :write, "writer reported unapproved losses"; diagnostics=plan.diagnostics)
    bytes2hex(SHA.sha256(plan.bytes)) == plan.sha256 || _io_error(:export_plan_modified, :write, "prepared bytes changed")
    dest = abspath(path)
    islink(dest) && _io_error(:unsafe_destination, :write, "symlink destinations are not supported")
    if !isnothing(plan.source_path)
        same = abspath(dest)==abspath(plan.source_path)
        if isdir(dirname(plan.source_path))
            same |= _io_output_path(dest)==_io_output_path(plan.source_path)
        end
        if ispath(dest) && ispath(plan.source_path)
            a,b = stat(dest),stat(plan.source_path)
            same |= a.device==b.device && a.inode==b.inode
        end
        same && _io_error(:source_overwrite, :write, "export must not overwrite its source")
    end
    ispath(dest) && !overwrite && _io_error(:destination_exists, :write, "destination exists; set overwrite=true to replace it")
    temp, io = mktemp(dirname(dest))
    try
        write(io, plan.bytes); close(io)
        if overwrite
            Base.Filesystem.rename(temp,dest)
        else
            # Hard-link installation is atomic and refuses a destination that
            # appeared since preflight; rename alone could overwrite it.
            Base.Filesystem.hardlink(temp,dest)
        end
    finally
        isopen(io) && close(io)
        ispath(temp) && rm(temp)
    end
    dest
end

"""Prepare and write a single-file export, returning its fidelity/diagnostic plan."""
function export_case(path::AbstractString, c::Case; overwrite::Bool=false, kwargs...)
    plan = prepare_export(c; kwargs...)
    write_export(path,plan;overwrite)
    plan
end
