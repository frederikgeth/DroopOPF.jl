include("powerio_export_validation.jl")

function D._prepare_export(::D.PowerIOBackend, c::D.Case, md::D.CaseIOMetadata,
    context, state::D.ACState, format::Symbol, options::D.ExportOptions, diagnostics::Vector{D.CaseIODiagnostic})
    for b in c.network.buses
        kv = get(md.bus_base_kv,b.id,NaN)
        isfinite(kv) && kv>0 || D._io_error(:missing_voltage_base, :export, "bus $(b.id) needs a positive base kV")
    end
    count(b -> b.reference,c.network.buses)==1 || D._io_error(:reference_bus,:export,"requires exactly one reference bus")
    any(g -> !isnothing(g.s_rated),c.generators) &&
        D._io_error(:unsupported_capability_export,:export,"generator apparent-power capability cannot be represented by this writer profile")
    bi = Dict(b.id=>i for (i,b) in enumerate(c.network.buses))
    data = Dict{String,Any}("name"=>c.id, "baseMVA"=>c.base_power,
        "base_frequency"=>c.base_frequency, "per_unit"=>true,
        "bus"=>Dict{String,Any}(), "gen"=>Dict{String,Any}(), "load"=>Dict{String,Any}(),
        "shunt"=>Dict{String,Any}(), "branch"=>Dict{String,Any}())
    for (i,b) in enumerate(c.network.buses)
        isfinite(state.vm[i]) && state.vm[i]>0 || D._io_error(:invalid_export_state,:export,"invalid bus voltage")
        data["bus"][string(b.id)] = Dict("bus_i"=>b.id,"bus_type"=>b.reference ? 3 : 1,
            "vm"=>state.vm[i],"va"=>state.va[i],"vmin"=>b.v_min,"vmax"=>b.v_max,
            "base_kv"=>md.bus_base_kv[b.id],"name"=>get(md.bus_names,b.id,string(b.id)),
            "area"=>get(md.bus_areas,b.id,1),"zone"=>get(md.bus_zones,b.id,1))
    end
    for (i,g) in enumerate(c.generators)
        if !(g.p_min <= state.pg[i] <= g.p_max && g.q_min <= state.qg[i] <= g.q_max)
            push!(diagnostics,D._io_diagnostic(:export_state_outside_limits,:export,
                "supplied dispatch exported unchanged outside generator limits";component="generator:$(g.id)"))
        end
        data["gen"][string(i)] = Dict("gen_bus"=>g.bus_id,"pg"=>state.pg[i],"qg"=>state.qg[i],
            "pmin"=>g.p_min,"pmax"=>g.p_max,"qmin"=>g.q_min,"qmax"=>g.q_max,
            "gen_status"=>g.available ? 1 : 0,"vg"=>state.vm[bi[g.bus_id]],
            "mbase"=>get(md.generator_machine_base_mva,g.id,c.base_power))
    end
    for (i,l) in enumerate(c.loads)
        data["load"][string(i)] = Dict("load_bus"=>l.bus_id,"pd"=>l.p,"qd"=>l.q,"status"=>1)
    end
    for (i,s) in enumerate(c.network.shunts)
        data["shunt"][string(i)] = Dict("shunt_bus"=>s.bus_id,"gs"=>s.conductance,
            "bs"=>s.susceptance,"status"=>s.available ? 1 : 0)
    end
    for (i,s) in enumerate(c.network.banks)
        y = D.bank_admittance(s)
        data["shunt"][string(length(c.network.shunts)+i)] = Dict("shunt_bus"=>s.bus_id,
            "gs"=>real(y),"bs"=>imag(y),"status"=>s.available ? 1 : 0)
    end
    for (i,b) in enumerate(c.network.branches)
        rate = b.thermal_limit
        if haskey(md.branch_rating_mva,b.id) && isnothing(md.branch_rating_mva[b.id])
            options.rating_policy==:reject && D._io_error(:rating_policy_required,:export,
                "branch $(b.id) had no source rating; choose :source or :effective rating_policy")
            options.rating_policy==:source && (rate=0.)
            push!(diagnostics,D._io_diagnostic(:unrated_export_policy_applied,:export,
                "$(options.rating_policy) rating policy applied";component="branch:$(b.id)"))
        end
        data["branch"][string(i)] = Dict("f_bus"=>b.from_bus,"t_bus"=>b.to_bus,
            "br_r"=>b.resistance,"br_x"=>b.reactance,"g_fr"=>0.,"g_to"=>0.,
            "b_fr"=>b.charging/2,"b_to"=>b.charging/2,"rate_a"=>rate,
            "tap"=>b.tap_ratio,"shift"=>b.phase_shift,"transformer"=>b.kind==:transformer,
            "br_status"=>b.available ? 1 : 0,"angmin"=>-2pi,"angmax"=>2pi)
    end
    for table in values(data)
        table isa AbstractDict || continue
        for (key,row) in table
            row["index"] = parse(Int,key)
        end
    end
    module_ = try
        P.from_powermodels(data)
    catch err
        err isa P.PowerIOError || rethrow()
        D._io_error(:powerio_construction_error, :export, sprint(showerror, err))
    end
    # Old libraries silently ignore this dictionary metadata and return 60 Hz.
    # Validate the actual constructed module before any target writer runs.
    module_.value.base_frequency == c.base_frequency ||
        D._io_error(:unsupported_export_frequency,:export,
            "loaded PowerIO library did not preserve the requested frequency; use a corrected library with base_frequency dictionary support")
    for d in module_.diagnostics
        push!(diagnostics,D._io_diagnostic(:powerio_builder_notice,:export,d.message;
            severity=d.severity,component=d.target,upstream_code=d.code))
    end
    _check_export_construction(module_.value, data, c)
    result = try
        P.emit(module_,format==:psse ? "psse" : "matpower")
    catch err
        err isa P.PowerIOError || rethrow()
        D._io_error(:powerio_writer_error, :export, sprint(showerror, err))
    end
    accepted = !any(d -> d.severity in (:warning,:error),module_.diagnostics)
    for d in result.diagnostics
        push!(diagnostics,D._io_diagnostic(:powerio_writer_notice,:export,d.message;
            severity=d.severity,component=d.target,upstream_code=d.code))
        d.severity in (:warning,:error) && (accepted=false)
    end
    length(result.artifacts)==1 || D._io_error(:unsupported_output_layout,:export,"writer did not produce one file")
    bytes = copy(only(result.artifacts).data)
    push!(diagnostics,D._io_diagnostic(:static_ac_projection,:export,
        "canonical static AC case; source control behavior and study configuration are outside this projection";severity=:note))
    push!(diagnostics,D._io_diagnostic(:equipment_ids_regenerated,:export,
        "writer generates target equipment IDs; source equipment identifiers are retained only in import context";severity=:note))
    source_path = isnothing(context) ? nothing : context.source.path
    D.ExportPlan(format,bytes,bytes2hex(D.SHA.sha256(bytes)),diagnostics,accepted,
        :static_ac_projection,result.fidelity,source_path)
end
