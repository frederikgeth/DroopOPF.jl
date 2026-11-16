"""Extract one RAW BUS ZONE using saved AC terminal flows as fixed signed P/Q
loads (positive = export/consumption; negative = import/injection). This is an
external-grid approximation, not an equivalent external AC network. All returned
reports and identifiers are confidential. No solve, file write or upload occurs.
Reference selection ranks retained physical generators by Pmax, including offline
units; ties use ascending source bus and generator ID. It is an angle gauge only.
"""
function extract_psse_zone(imported::PSSEImport;zone::Integer=4)
    c=imported.case;net=c.network;s=imported.initial_state;raw=imported.raw
    zonemap=Dict(Int(r.fields[:I])=>Int(get(r.fields,:ZONE,1)) for r in raw.sections[:bus])
    kept=Set(b.id for b in net.buses if zonemap[b.id]==zone)
    isempty(kept) && throw(ArgumentError("requested RAW bus zone has no energized buses"))
    generators=[g for g in c.generators if g.bus_id in kept]
    candidates=[g for g in generators if g.p_max>0]
    isempty(candidates) && throw(ArgumentError("zone requires a physical generator with positive Pmax for reference selection"))
    rank(g)=(-g.p_max,g.bus_id,string(imported.source_ids[:generator][g.id][2]),g.id)
    ref=first(sort(candidates;by=rank))
    buses=[Bus(b.id;v_min=b.v_min,v_max=b.v_max,reference=b.id==ref.bus_id) for b in net.buses if b.id in kept]
    internal=[b for b in net.branches if b.from_bus in kept && b.to_bus in kept]
    boundary=[(i,b) for (i,b) in enumerate(net.branches) if (b.from_bus in kept)!=(b.to_bus in kept)]
    # Missing VM/VA must never be replaced by importer defaults when calculating exchange.
    busrecords=Dict(Int(r.fields[:I])=>r for r in raw.sections[:bus])
    for (_,b) in boundary
        b.available || continue
        all(haskey(busrecords[id].fields,key) for id in (b.from_bus,b.to_bus) for key in (:VM,:VA)) ||
            throw(ArgumentError("boundary exchange requires saved endpoint VM and VA"))
    end
    flows=branch_flows(net,s)
    loads=[l for l in c.loads if l.bus_id in kept]
    ids=Dict(k=>Dict{Int,Any}() for k in keys(imported.source_ids))
    for (kind,objects) in ((:bus,buses),(:generator,generators),(:load,loads),(:branch,internal))
        for x in objects;ids[kind][x.id]=imported.source_ids[kind][x.id];end
    end
    nextload=maximum((l.id for l in c.loads);init=0)
    boundary_rows=Dict{String,Any}[]
    for (k,(i,b)) in enumerate(boundary)
        inside=b.from_bus in kept ? b.from_bus : b.to_bus
        outside=b.from_bus in kept ? b.to_bus : b.from_bus
        terminal=b.from_bus in kept ? flows.from[i] : flows.to[i]
        # One equivalent per tie, including zero for offline ties. Allocate IDs
        # from source branch IDs so identity does not depend on tie-flow direction.
        lid=nextload+b.id
        push!(loads,Load(lid,inside;p=real(terminal),q=imag(terminal)))
        ids[:load][lid]=(:boundary,imported.source_ids[:branch][b.id])
        push!(boundary_rows,Dict("branch_id"=>b.id,"source_id"=>_json_data(imported.source_ids[:branch][b.id]),
            "inside_bus"=>inside,"outside_bus"=>outside,"outside_zone"=>zonemap[outside],
            "available"=>b.available,"equivalent_load_id"=>lid,"p_export_mw"=>real(terminal)*c.base_power,
            "q_export_mvar"=>imag(terminal)*c.base_power))
    end
    shunts=[x for x in net.shunts if x.bus_id in kept]
    for x in shunts;ids[:shunt][x.id]=imported.source_ids[:shunt][x.id];end
    reduced=Case("local_zone";base_power=c.base_power,base_frequency=c.base_frequency,
        network=ACNetwork(buses,internal;shunts),loads,generators,
        controls=c.controls,attachments=c.attachments)
    _connected_after_branch_outage(reduced,-1) || throw(ArgumentError(
        "selected zone is disconnected after removing external network; separate islands need explicit models"))
    idx=_bus_indices(net);shift=s.va[idx[ref.bus_id]]
    gi=Dict(g.id=>i for (i,g) in enumerate(c.generators))
    state=ACState([s.vm[idx[b.id]] for b in buses],[s.va[idx[b.id]]-shift for b in buses],
        [s.pg[gi[g.id]] for g in generators],[s.qg[gi[g.id]] for g in generators])
    original=power_balance(c,s);replay=power_balance(reduced,state)
    preservation=maximum((max(abs(replay.active[i]-original.active[idx[b.id]]),
        abs(replay.reactive[i]-original.reactive[idx[b.id]])) for (i,b) in enumerate(buses));init=0.)
    preservation<=1e-10 || throw(ArgumentError("zone boundary replay did not preserve saved nodal balance"))
    report=Dict{String,Any}("scope"=>"confidential local zone model build; no security qualification",
        "zone"=>zone,"zone_field"=>"RAW BUS ZONE", "boundary_policy"=>"fixed saved terminal P/Q per period; frozen across outages; no relief",
        "reference_policy"=>"largest positive Pmax physical generator including offline; ascending source bus/ID ties; angle gauge only",
        "reference_generator_id"=>ref.id,"reference_source_id"=>_json_data(imported.source_ids[:generator][ref.id]),
        "reference_bus"=>ref.bus_id,"reference_pmax_mw"=>ref.p_max*c.base_power,"reference_generator_online"=>ref.available,
        "bus_ids"=>[b.id for b in buses],"generator_ids"=>[g.id for g in generators],
        "internal_branch_ids"=>[b.id for b in internal],"boundary_exchanges"=>boundary_rows,
        "removed_bus_ids"=>[b.id for b in net.buses if !(b.id in kept)],
        "removed_generator_ids"=>[g.id for g in c.generators if !(g.bus_id in kept)],
        "excluded_boundary_outage_ids"=>[b.id for (_,b) in boundary],
        "nodal_balance_preservation_error_pu"=>preservation,
        "saved_zone_max_p_mismatch_mw"=>maximum(abs,replay.active)*c.base_power,
        "saved_zone_max_q_mismatch_mvar"=>maximum(abs,replay.reactive)*c.base_power,
        "exchange_source"=>"recomputed AC saved VM/VA terminal flows; not an independent PSS/E flow listing")
    (;case=reduced,initial_state=state,report,source_ids=ids)
end

"""Write confidential per-period network-build reports to a caller-opened local IO.
For zone series these include selected reference and all fixed boundary exchanges.
Never transfer this report through the status-only diagnostic channel.
"""
function write_psse_series_build_report(io::IO,series::PSSETimeSeries)
    JSON.json(io,_json_data(series.build_reports);pretty=true);println(io)
    nothing
end

"""Confidential offline viewer with the network-build report and change browser."""
function write_psse_series_inspection(io::IO,series::PSSETimeSeries)
    buffer=IOBuffer();write_psse_series_inspection(buffer,inspect_psse_series(series))
    html=String(take!(buffer))
    build="<details><summary>Network build report (confidential)</summary><pre>"*
        _psse_html(JSON.json(_json_data(series.build_reports);pretty=true))*"</pre></details>"
    print(io,replace(html,"<label>Filter"=>build*_psse_ibr_fit_html(series.ibr_fits)*"<label>Filter";count=1))
    nothing
end

"""Run the existing multi-period SCOPF on explicitly configured zone Studies,
protecting fixed boundary exchanges by refusing emergency/relief policy. Timing,
ramps and angles are forwarded from the parsed series. Cases may add controls but
must retain the extracted network, loads and physical generator data.
"""
function optimize_psse_series_security(series::PSSETimeSeries,studies;
    s2_emergency=false,supplied_avr_schedule=true,initial_states=nothing,kwargs...)
    any(haskey(r,"zone") for r in series.build_reports) || throw(ArgumentError("zone series required"))
    s2_emergency && throw(ArgumentError("fixed boundary exchange requires full-load/no-relief policy"))
    length(studies)==length(series.study.cases) || throw(ArgumentError("one study per period required"))
    _psse_check_required_avrs(series,studies)
    for (s,c) in zip(studies,series.study.cases)
        isequal(_json_data(s.case.network),_json_data(c.network)) &&
        isequal(_json_data(s.case.loads),_json_data(c.loads)) &&
        isequal(_json_data(s.case.generators),_json_data(c.generators)) &&
        s.case.base_power==c.base_power && s.case.base_frequency==c.base_frequency ||
            throw(ArgumentError("zone studies must retain extracted physical data and fixed boundary loads"))
    end
    starts=isnothing(initial_states) ? _psse_series_avr_starts(series,studies) : initial_states
    optimize_multi_period_security(studies;initial_states=starts,duration_hours=series.study.duration_hours,
        ramp_limits=series.study.ramp_limits,angle_limits=series.study.angle_limits,s2_emergency=false,supplied_avr_schedule,kwargs...)
end

function _psse_require_avr_policy(series)
    all(get(get(r,"avr_policy",Dict("qualified"=>true)),"qualified",false) for r in series.build_reports) ||
        throw(ArgumentError("unresolved synchronous AVR/condenser policy; inspect confidential build reports"))
end

function _psse_check_required_avrs(series,studies)
    _psse_require_avr_policy(series)
    for (t,s) in enumerate(studies)
        supplied=isnothing(s.reactive_assignments) ? ReactiveControlAssignment[] : s.reactive_assignments
        for required in series.reactive_assignments[t]
            any(_json_data(x)==_json_data(required) for x in supplied) ||
                throw(ArgumentError("study dropped or changed required synchronous AVR; use psse_series_studies"))
        end
        metadata_map=isempty(series.generator_technologies) ? Dict{Int,Dict{String,Any}}() : series.generator_technologies[t]
        for (id,metadata) in metadata_map
            metadata["technology"]=="synchronous_condenser" || continue
            get(s.participation,id,0.)==0 || throw(ArgumentError("synchronous condenser cannot participate in automatic active response"))
        end
    end
end

"""Construct period Studies with parsed synchronous AVRs and common effective-range
response weights, masking offline units in each scenario. Condensers receive zero
active-response weight. Explicit weights may be supplied. Unresolved AVR locations,
targets or condenser positive-P capability block this path, while reports stay inspectable.
Extra controls require an explicit per-period `reactive_assignments` vector retaining
all required synchronous AVRs. Other Study options are shared over periods.
"""
function psse_series_studies(series::PSSETimeSeries;participation=nothing,
    reactive_assignments=series.reactive_assignments,kwargs...)
    _psse_require_avr_policy(series)
    length(reactive_assignments)==length(series.study.cases) || throw(ArgumentError("one assignment vector per period required"))
    weights=Dict{Int,Float64}()
    if isnothing(participation)
        for (t,c) in enumerate(series.study.cases)
            for (id,w) in default_participation(c;reactive_assignments=reactive_assignments[t])
                weights[id]=max(get(weights,id,0.),w)
            end
        end
        if !isempty(series.generator_technologies)
            for (id,m) in series.generator_technologies[1]
                m["technology"]=="synchronous_condenser" && (weights[id]=0.)
            end
        end
    else
        weights=Dict{Int,Float64}(participation)
    end
    known=Set(g.id for g in series.study.cases[1].generators)
    all(id in known && isfinite(w) && w>=0 for (id,w) in weights) || throw(ArgumentError("invalid supplied response weights"))
    studies=[Study(c;reactive_assignments=reactive_assignments[t],
        participation=Dict(g.id=>weights[g.id] for g in c.generators if g.available && haskey(weights,g.id)),kwargs...)
        for (t,c) in enumerate(series.study.cases)]
    _psse_check_required_avrs(series,studies)
    studies
end

"""Convenience protected zone SCOPF using the parsed synchronous AVRs by default.
Use `study_options` to select contingencies, equipment and any reviewed IBR controls.
"""
function optimize_psse_series_security(series::PSSETimeSeries;study_options=(;),kwargs...)
    studies=psse_series_studies(series;study_options...)
    optimize_psse_series_security(series,studies;kwargs...)
end


# Initialization only: copy saved zone states and initialize regulated VM at the
# declared AVR target to avoid starting on a flat saturated projection branch.
# Original snapshots, stored initial_states and physical acceptance are unchanged.
function _psse_series_avr_starts(series,studies)
    starts=Dict{Symbol,ACState{Float64}}[]
    for (t,s) in enumerate(studies)
        saved=series.initial_states[t]
        vm=copy(saved.vm);idx=_bus_indices(s.case.network)
        active=Set(g.id for g in s.case.generators if g.available)
        for a in something(s.reactive_assignments,ReactiveControlAssignment[])
            a.mode isa AVR && a.generator_id in active || continue
            vm[idx[a.location.bus_id]]=a.mode.voltage_setpoint
        end
        push!(starts,Dict(:base=>ACState(vm,copy(saved.va),copy(saved.pg),copy(saved.qg))))
    end
    starts
end
