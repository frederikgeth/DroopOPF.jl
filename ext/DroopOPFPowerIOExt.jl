module DroopOPFPowerIOExt

import DroopOPF as D
import PowerIO as P

include("powerio_transformer_qualification.jl")

# Deliberately narrow: a generic FIELD_DROPPED notice is never sufficient to
# establish that a loss is safe. Keep the original notice, including severity.
function _qualified_raw_notice(d, bytes)
    d.severity == :warning || return false
    if d.code == "READ.PSSE.SECTION_UNSUPPORTED"
        return occursin(r"^PSS/E (OWNER|ZONE) section \([0-9]+ record line\(s\)\) is not modeled: preserved only in a same-format \.raw echo, dropped on any other write$", d.message)
    end
    d.code == "READ.PSSE.FIELD_DROPPED" || return false
    suffix = " has no typed representation; retained only in the same format source"
    fields = ("GENERAL.PQBRAK", "GENERAL.BLOWUP", "NEWTON.ACCN", "NEWTON.VCTOLQ",
        "NEWTON.VCTOLV", "NEWTON.DVLIM", "NEWTON.NDVFCT", "GAUSS record",
        "ADJUST record", "TYSL record")
    any(f -> d.message == "PSS/E system wide $f$suffix", fields) && return true
    if d.message == "PSS/E system wide RATING record$suffix"
        # Qualify only rating-set labels, never unknown extra rating options.
        lines = filter(l -> occursin(r"^\s*RATING\s*,"i, l), split(String(copy(bytes)), '\n'))
        return !isempty(lines) && all(l -> occursin(
            r"^\s*RATING\s*,\s*[1-9][0-9]*\s*,\s*\"[^\"]*\"\s*,\s*\"[^\"]*\"\s*(?:/.*)?$"i, l), lines)
    end
    false
end

function _identity(value, kind, i)
    isnothing(value) && D._io_error(:missing_source_identity, :convert, "PowerIO did not provide $kind identity at row $i")
    String(value)
end

function D._import_case(::D.PowerIOBackend, bytes::Vector{UInt8}, path::String,
    format::Symbol, options::D.ImportOptions)
    P.library_available() || D._io_error(:backend_unavailable, :dependency, "PowerIO native library is unavailable")
    diagnostics = D.CaseIODiagnostic[]
    format == :matpower && D._io_matpower_envelope(bytes, diagnostics)
    module_ = try
        P.parse(P.PioModule{P.BalancedNetwork}, bytes; name=basename(path), format=String(format))
    catch err
        err isa P.PowerIOError || rethrow()
        D._io_error(:powerio_parse_error, :parse, sprint(showerror, err))
    end
    for d in module_.diagnostics
        push!(diagnostics, D._io_diagnostic(:powerio_reader_notice, :parse, d.message;
            severity=d.severity, component=d.target, upstream_code=d.code))
    end
    any(d -> d.severity in (:warning, :error) &&
        !(format == :psse && _qualified_raw_notice(d, bytes)), module_.diagnostics) &&
        D._io_error(:unqualified_source_diagnostic, :convert,
            "PowerIO source warnings require model-coverage qualification"; diagnostics)
    n = module_.value
    for table in (:static_var_compensators, :storage, :switches, :hvdc, :transformers_3w)
        isempty(getproperty(n, table)) || D._io_error(:unsupported_equipment, :convert,
            "PowerIO parsed $table, which this DroopOPF import profile cannot represent"; diagnostics)
    end
    if format == :psse && any(b -> !iszero(b.tap_ratio) || !iszero(b.phase_shift_degrees), n.branches)
        _raw_transformer_basis_qualified() || D._io_error(:unqualified_raw_transformer, :convert,
            "loaded PowerIO library failed the RAW transformer basis qualification; use NativeBackend() or a corrected PowerIO library";
            diagnostics)
        push!(diagnostics,D._io_diagnostic(:raw_transformer_basis_qualified,:convert,
            "loaded PowerIO library passed CW/CZ and nominal-voltage basis probes";severity=:note))
    end
    # Detailed node/breaker topology cannot be treated as an ordinary bus/branch
    # case without a separately qualified topology reduction.
    details = n.detailed_connectivity
    if !isnothing(details)
        for table in (:substations, :voltage_levels, :connectivity_nodes, :busbar_sections,
            :switches, :internal_connections, :tap_changers, :dc_lines)
            isempty(getproperty(details, table)) || D._io_error(:unsupported_connectivity, :convert,
                "detailed $table require a qualified topology/control projection"; diagnostics)
        end
    end
    base = n.base_mva
    isfinite(base) && base > 0 || D._io_error(:invalid_base, :convert, "invalid PowerIO base MVA")
    metadata = D.CaseIOMetadata(); ids = D._io_identities()
    buses = D.Bus[]; generators = D.Generator[]; loads = D.Load[]
    branches = D.Branch[]; shunts = D.FixedShunt[]
    busrows = collect(n.buses)
    allbus = Set(b.id for b in busrows)
    active = Set(b.id for b in busrows if b.bus_type != "ISOLATED")
    active_busrows = [b for b in busrows if b.id in active]
    length(allbus) == length(busrows) || D._io_error(:duplicate_identity, :convert, "duplicate PowerIO bus ID")
    function buscheck(i)
        i in allbus || D._io_error(:unknown_bus, :convert, "equipment references unknown bus $i")
        i in active
    end
    for b in active_busrows
        b.bus_type in ("PQ", "PV", "REF") || D._io_error(:unsupported_bus_type, :convert, "unsupported bus type $(b.bus_type)")
        push!(buses, D.Bus(b.id; v_min=b.vmin_pu, v_max=b.vmax_pu, reference=b.bus_type=="REF"))
        ids[:bus][b.id] = b.id
        metadata.bus_base_kv[b.id] = b.base_kv
        metadata.bus_names[b.id] = something(b.name, string(b.id))
        metadata.bus_areas[b.id] = b.area; metadata.bus_zones[b.id] = b.zone
    end
    if length(active) != length(allbus)
        push!(diagnostics, D._io_diagnostic(:isolated_equipment_excluded, :convert,
            "isolated buses and attached equipment excluded from energized model"))
    end
    function shunt!(bus, g, b, available, identity)
        sid = length(shunts)+1
        push!(shunts, D.FixedShunt(sid, bus; conductance=g/base, susceptance=b/base, available))
        ids[:shunt][sid] = identity
    end
    for (i, l) in enumerate(n.loads)
        buscheck(l.bus_id) || continue
        l.in_service || continue
        identity = _identity(l.component_id, :load, i)
        m = l.voltage_model
        any(!iszero, (m.p_constant_current_mw, m.q_constant_current_mvar,
            m.exponential_p_mw, m.exponential_q_mvar)) &&
            D._io_error(:unsupported_load_model, :convert, "current/exponential load terms cannot be represented")
        lid = length(loads)+1
        push!(loads, D.Load(lid, l.bus_id; p=m.p_constant_power_mw/base, q=m.q_constant_power_mvar/base))
        ids[:load][lid] = identity
        if !iszero(m.p_constant_impedance_mw) || !iszero(m.q_constant_impedance_mvar)
            shunt!(l.bus_id, m.p_constant_impedance_mw, -m.q_constant_impedance_mvar, true, (:load_impedance, identity))
        end
    end
    for (i, s) in enumerate(n.shunts)
        buscheck(s.bus_id) || continue
        shunt!(s.bus_id, s.conductance_mw, s.susceptance_mvar, s.in_service, _identity(s.component_id, :shunt, i))
        isnothing(s.control) || push!(diagnostics, D._io_diagnostic(:shunt_control_locked, :convert,
            "shunt control fixed at supplied admittance"; component=string(s.component_id)))
    end
    pg = Float64[]; qg = Float64[]
    for (i, g) in enumerate(n.generators)
        buscheck(g.bus_id) || continue
        g.in_service && any(cap -> cap.name in ("pc1", "pc2", "qc1min", "qc1max", "qc2min", "qc2max") &&
            !isnothing(cap.value) && !iszero(cap.value), g.capabilities) &&
            D._io_error(:unsupported_generator_capability, :convert, "generator $i has a nonrectangular capability curve")
        gid = length(generators)+1
        push!(generators, D._io_generator(gid, g.bus_id; available=g.in_service,
            p=g.active_power_mw/base, q=g.reactive_power_mvar/base,
            pmin=g.active_power_min_mw/base, pmax=g.active_power_max_mw/base,
            qmin=g.reactive_power_min_mvar/base, qmax=g.reactive_power_max_mvar/base, diagnostics))
        push!(pg, g.active_power_mw/base); push!(qg, g.reactive_power_mvar/base)
        ids[:generator][gid] = _identity(g.component_id, :generator, i)
        metadata.generator_machine_base_mva[gid] = g.machine_base_mva
    end
    for (i, b) in enumerate(n.branches)
        a = buscheck(b.from_bus_id); z = buscheck(b.to_bus_id)
        a && z || continue
        D._io_angle_limits(b.angle_min_degrees, b.angle_max_degrees, b.in_service, i)
        # These terms already include charging; do not add total B a second time.
        expected = b.total_charging_susceptance_pu/2
        (iszero(b.from_conductance_pu) && iszero(b.to_conductance_pu) &&
            b.from_susceptance_pu == expected && b.to_susceptance_pu == expected) ||
            D._io_error(:unsupported_terminal_admittance, :convert, "branch terminal shunts cannot be represented exactly")
        isnothing(b.current_ratings) || D._io_error(:unsupported_rating_units, :convert, "current-based branch ratings require a separate model")
        bid = length(branches)+1
        identity = _identity(b.component_id, :branch, i)
        rate = D._io_rating(b.rate_a_mva, base, options, diagnostics, identity)
        kind = !iszero(b.tap_ratio) || !iszero(b.phase_shift_degrees) ? :transformer : :line
        push!(branches, D.Branch(bid, b.from_bus_id, b.to_bus_id; resistance=b.resistance_pu,
            reactance=b.reactance_pu, charging=b.total_charging_susceptance_pu, thermal_limit=rate,
            available=b.in_service, tap_ratio=b.effective_tap_ratio,
            phase_shift=deg2rad(b.phase_shift_degrees), kind))
        ids[:branch][bid] = identity
        metadata.branch_rating_mva[bid] = b.rate_a_mva>0 ? b.rate_a_mva : nothing
        isnothing(b.control) || push!(diagnostics, D._io_diagnostic(:transformer_control_locked, :convert,
            "transformer control fixed at supplied tap/phase"; component=identity))
    end
    for kind in (:load, :generator, :branch, :shunt)
        values_ = collect(values(ids[kind]))
        length(unique(values_)) == length(values_) || D._io_error(:duplicate_identity, :convert, "duplicate $kind identity")
    end
    for key in (:VM, :VA); metadata.saved_field_presence[key] = fill(:unknown, length(buses)); end
    for key in (:PG, :QG); metadata.saved_field_presence[key] = fill(:unknown, length(generators)); end
    push!(diagnostics, D._io_diagnostic(:saved_field_presence_unknown, :convert,
        "typed values do not establish source saved-field presence; no saved-solution certification"))
    push!(diagnostics, D._io_diagnostic(:control_metadata_unmodeled, :convert,
        "no automatic droop/AVR assignments inferred from source controls"; severity=:note))
    frequency = something(options.base_frequency, format==:matpower ? 50. : n.base_frequency)
    c = D.Case(something(options.id, splitext(basename(path))[1]); base_power=base,
        base_frequency=frequency, network=D.ACNetwork(buses, branches; shunts), loads, generators,
        controls=D.VoltVarDroop[], attachments=D.GeneratorControlAttachment[])
    state = D._io_state(buses, [b.vm_pu for b in active_busrows],
        [b.va_degrees for b in active_busrows], pg, qg)
    D.CaseImport(c, state, ids, metadata, diagnostics,
        D._io_source(:powerio, bytes, path, format;
            parser_version=string(pkgversion(P)), library_version=string(P.library_version())))
end

include("powerio_export.jl")

end
