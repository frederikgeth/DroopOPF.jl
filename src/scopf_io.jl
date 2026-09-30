import JSON

_json_data(x::Union{Nothing,Bool,AbstractString,Integer}) = x
_json_data(x::Symbol) = string(x)
_json_data(x::AbstractFloat) = isfinite(x) ? x : nothing
_json_data(x::Tuple) = [_json_data(v) for v in x]
_json_data(x::AbstractVector) = [_json_data(v) for v in x]
_json_data(x::AbstractDict) = Dict(string(k) => _json_data(v) for (k,v) in x)
_json_data(x::NamedTuple) = Dict(string(k) => _json_data(v) for (k,v) in pairs(x))
function _json_data(x::Union{Bus,Branch,Load,FixedShunt,ShuntBank,Generator,RegulatedLocation,VoltageSchedule,
    ReactiveCapability,GeneratorControlAttachment,ACNetwork,Case,Contingency,Study,
    ACState,ACOPFResult,SCOPFResult,SCOPFReport,EquilibriumValidationReport,
    SCOPFMultiStartRun,SCOPFMultiStartResult,DroopBreakpointDiagnostic,
    SCOPFFinding,SCOPFDiagnostics,TapControl,ShuntControl,SCOPFControlPolicy,
    SCOPFStageAssessment, ContingencyCatalogEntry, ContingencyCatalog, ContingencyRank,
    ContingencyAssessment, ContingencyScreeningScore, IslandSelection,
    IslandedContingencyAssessment, ContingencyFilterDecision})
    # Heterogeneous field generators cause recursive inference through the
    # entire Study/Case graph. JSON objects intentionally have dynamic values.
    data = Dict{String,Any}()
    for k in fieldnames(typeof(x))
        data[string(k)] = Base.invokelatest(_json_data, getfield(x, k))
    end
    return data
end
function _json_data(x::VoltVarDroop)
    # Curve knots are derived from these physical settings.
    return Dict(string(k) => _json_data(getfield(x,k)) for k in
        (:schedule,:slope,:q_at_deadband,:capability))
end
_json_data(::FreeQ) = Dict("type" => "FreeQ")
_json_data(x::FixedQ) = Dict("type" => "FixedQ", "q_schedule" => x.q_schedule)
_json_data(x::AVR) = Dict("type" => "AVR", "voltage_setpoint" => x.voltage_setpoint)
function _json_data(x::ReactiveControlAssignment)
    mode = x.mode isa VoltVarDroop ?
        merge(Dict("type" => "VoltVarDroop"), _json_data(x.mode)) : _json_data(x.mode)
    Dict("generator_id" => x.generator_id, "mode" => mode,
        "location" => _json_data(x.location))
end

function _write_scopf_json(path, kind, payload)
    open(path, "w") do io
        version = kind == "DroopOPF.Study" ? 8 : kind == "DroopOPF.SCOPFResult" ? 4 : 1
        JSON.json(io, Dict("schema_version"=>version, "kind"=>kind, "data"=>_json_data(payload)); pretty=true)
        println(io)
    end
    return path
end

"""Write a versioned study including its case and response policy to JSON."""
write_study(path::AbstractString, study::Study) =
    _write_scopf_json(path, "DroopOPF.Study", _validated_study(study))

"""Write scenario states and solver metadata to JSON. Nonfinite diagnostics become null."""
write_scopf_result(path::AbstractString, result::SCOPFResult) =
    _write_scopf_json(path, "DroopOPF.SCOPFResult", result)

"""Write a report to JSON; null margins mean an absent bound and null residuals are unavailable."""
write_scopf_report(path::AbstractString, report::SCOPFReport) =
    _write_scopf_json(path, "DroopOPF.SCOPFReport", report)

"""Write a paired M9.3 immediate/settled assessment to JSON."""
write_scopf_stage_assessment(path::AbstractString, assessment::SCOPFStageAssessment) =
    _write_scopf_json(path, "DroopOPF.SCOPFStageAssessment", assessment)

"""Write all multi-start outcomes and the objective-comparison classification."""
write_scopf_multistart(path::AbstractString, result::SCOPFMultiStartResult) =
    _write_scopf_json(path, "DroopOPF.SCOPFMultiStartResult", result)

"""Write breakpoint distances and structured findings to versioned JSON."""
write_scopf_diagnostics(path::AbstractString, diagnostics::SCOPFDiagnostics) =
    _write_scopf_json(path, "DroopOPF.SCOPFDiagnostics", diagnostics)

"""Write a structurally classified N-1 candidate catalog to JSON."""
write_contingency_catalog(path::AbstractString, catalog::ContingencyCatalog) =
    _write_scopf_json(path, "DroopOPF.ContingencyCatalog", catalog)

"""Write an exact-evaluation contingency ranking to JSON."""
write_contingency_ranking(path::AbstractString,
    ranks::AbstractVector{<:ContingencyRank}) =
    _write_scopf_json(path, "DroopOPF.ContingencyRanking", ranks)

function _read_scopf_json(path, kind)
    document = JSON.parsefile(path)
    version = get(document,"schema_version",nothing)
    supported = kind == "DroopOPF.Study" ? (1, 2, 3, 4, 5, 6, 7, 8) :
        kind == "DroopOPF.SCOPFResult" ? (1, 2, 3, 4) : (1,)
    version in supported || throw(ArgumentError("unsupported JSON schema version"))
    get(document,"kind",nothing) == kind || throw(ArgumentError("unexpected JSON document kind"))
    data = document["data"]
    if kind == "DroopOPF.Study"
        if version < 5
            data["reactive_assignments"] = nothing
        else
            haskey(data, "reactive_assignments") ||
                throw(ArgumentError("v5 study requires reactive_assignments"))
        end
        if version < 7
            data["tap_controls"] = []
            data["shunt_controls"] = []
            data["control_policy"] = Dict("taps"=>"preventive",
                "shunts"=>"preventive", "reactive"=>"automatic")
        else
            all(haskey(data, k) for k in
                ("tap_controls", "shunt_controls", "control_policy")) ||
                throw(ArgumentError("v7 study requires equipment controls and policy"))
        end
        if version < 8
            data["control_policy"] = Dict{String,Any}(data["control_policy"])
            data["control_policy"]["tap_movement_limits"] = nothing
            data["control_policy"]["shunt_movement_limits"] = nothing
        else
            all(haskey(data["control_policy"], k) for k in
                ("tap_movement_limits", "shunt_movement_limits")) ||
                throw(ArgumentError("v8 study policy requires movement-limit fields"))
        end
        network = data["case"]["network"]
        if version < 4
            isempty(get(network,"banks",[])) || throw(ArgumentError("bank data requires study schema v4"))
            network["banks"] = []
        else
            haskey(network,"banks") || throw(ArgumentError("v4 study requires network.banks"))
        end
        if version < 3
            isempty(get(network, "shunts", [])) ||
                throw(ArgumentError("fixed shunt data requires study schema v3"))
            network["shunts"] = []
        else
            haskey(network, "shunts") || throw(ArgumentError("v3 study requires network.shunts"))
        end
        for b in data["case"]["network"]["branches"]
            if version == 1
                # Never silently discard contradictory transformer data labelled v1.
                (get(b, "tap_ratio", 1.0) == 1 && get(b, "phase_shift", 0.0) == 0) ||
                    throw(ArgumentError("nontrivial transformer data requires study schema v2"))
                b["tap_ratio"] = 1.0
                b["phase_shift"] = 0.0
            else
                all(haskey(b, k) for k in ("tap_ratio", "phase_shift")) ||
                    throw(ArgumentError("v2 study branches require tap_ratio and phase_shift"))
            end
        end
    end
    if kind == "DroopOPF.SCOPFResult"
        version < 2 && (data["reactive_assignments"] = nothing)
        if version < 3
            data["tap_settings"] = Dict()
            data["shunt_settings"] = Dict()
            data["tap_controls"] = []
            data["shunt_controls"] = []
            data["control_policy"] = Dict("taps"=>"preventive",
                "shunts"=>"preventive", "reactive"=>"automatic")
        else
            all(haskey(data, k) for k in ("tap_settings", "shunt_settings",
                "tap_controls", "shunt_controls", "control_policy")) ||
                throw(ArgumentError("v3 SCOPF result requires equipment settings and policy"))
        end
        if version < 4
            data["control_policy"] = Dict{String,Any}(data["control_policy"])
            data["control_policy"]["tap_movement_limits"] = nothing
            data["control_policy"]["shunt_movement_limits"] = nothing
        else
            all(haskey(data["control_policy"], k) for k in
                ("tap_movement_limits", "shunt_movement_limits")) ||
                throw(ArgumentError("v4 SCOPF result policy requires movement-limit fields"))
        end
    end
    return data
end

function _reactive_assignment_from_data(a)
    m = a["mode"]
    mode = if m["type"] == "FreeQ"
        FreeQ()
    elseif m["type"] == "FixedQ"
        FixedQ(Float64(m["q_schedule"]))
    elseif m["type"] == "AVR"
        AVR(Float64(m["voltage_setpoint"]))
    elseif m["type"] == "VoltVarDroop"
        s, cap = m["schedule"], m["capability"]
        VoltVarDroop(VoltageSchedule(Float64(s["v_ref"]);
            v_db_low=Float64(s["v_db_low"]), v_db_high=Float64(s["v_db_high"]),
            unit=Symbol(s["unit"])), Float64(m["slope"]),
            Float64(m["q_at_deadband"]), ReactiveCapability(;
                (Symbol(k)=>Float64(cap[k]) for k in ("p_min","p_max","q_min","q_max"))...))
    else
        throw(ArgumentError("unknown reactive-control mode type"))
    end
    l = a["location"]
    location = isnothing(l) ? nothing : RegulatedLocation(Symbol(l["kind"]), l["bus_id"];
        side=isnothing(l["side"]) ? nothing : Symbol(l["side"]),
        branch_id=get(l, "branch_id", nothing))
    ReactiveControlAssignment(a["generator_id"], mode, location)
end

_reactive_assignments_from_data(data) = isnothing(data) ? nothing :
    ReactiveControlAssignment[_reactive_assignment_from_data(a) for a in data]

_tap_controls_from_data(data) = TapControl[TapControl(c["branch_id"];
    lower=Float64(c["lower"]), upper=Float64(c["upper"]),
    initial=isnothing(c["initial"]) ? nothing : Float64(c["initial"]),
    nominal=isnothing(c["nominal"]) ? nothing : Float64(c["nominal"])) for c in data]

_shunt_controls_from_data(data) = ShuntControl[ShuntControl(c["bank_id"];
    lower=isnothing(c["lower"]) ? nothing : Float64(c["lower"]),
    upper=isnothing(c["upper"]) ? nothing : Float64(c["upper"]),
    initial=isnothing(c["initial"]) ? nothing : Float64(c["initial"]),
    nominal=isnothing(c["nominal"]) ? nothing : Float64(c["nominal"])) for c in data]

_control_policy_from_data(data) = SCOPFControlPolicy(
    taps=Symbol(data["taps"]), shunts=Symbol(data["shunts"]),
    reactive=Symbol(data["reactive"]),
    tap_movement_limits=isnothing(data["tap_movement_limits"]) ? nothing :
        Dict(parse(Int,k)=>Float64(v) for (k,v) in data["tap_movement_limits"]),
    shunt_movement_limits=isnothing(data["shunt_movement_limits"]) ? nothing :
        Dict(parse(Int,k)=>Float64(v) for (k,v) in data["shunt_movement_limits"]))

"""Load a study and recheck case, outage, and response-policy validity."""
function read_study(path::AbstractString)
    data = _read_scopf_json(path, "DroopOPF.Study")
    c = data["case"]
    n = c["network"]
    buses = [Bus(b["id"]; v_min=Float64(b["v_min"]), v_max=Float64(b["v_max"]), reference=b["reference"]) for b in n["buses"]]
    branches = Branch[Branch(b["id"],b["from_bus"],b["to_bus"]; resistance=Float64(b["resistance"]),
        reactance=Float64(b["reactance"]), charging=Float64(b["charging"]),
        thermal_limit=Float64(b["thermal_limit"]), available=b["available"],
        tap_ratio=Float64(b["tap_ratio"]), phase_shift=Float64(b["phase_shift"])) for b in n["branches"]]
    shunts = FixedShunt[FixedShunt(s["id"],s["bus_id"]; conductance=Float64(s["conductance"]),
        susceptance=Float64(s["susceptance"]), available=s["available"]) for s in n["shunts"]]
    banks = ShuntBank[ShuntBank(b["id"],b["bus_id"]; step_conductances=Float64.(b["step_conductances"]),
        step_susceptances=Float64.(b["step_susceptances"]),legal_states=b["legal_states"],
        state=b["state"],nominal_state=b["nominal_state"],available=b["available"]) for b in n["banks"]]
    generators = [Generator(g["id"],g["bus_id"]; available=g["available"],
        p_min=Float64(g["p_min"]), p_max=Float64(g["p_max"]), q_min=Float64(g["q_min"]),
        q_max=Float64(g["q_max"]), initial_p=Float64(g["initial_p"]), initial_q=Float64(g["initial_q"])) for g in c["generators"]]
    loads = Load[Load(l["id"],l["bus_id"]; p=Float64(l["p"]),q=Float64(l["q"])) for l in c["loads"]]
    controls = VoltVarDroop[]
    for control in c["controls"]
        s, cap = control["schedule"], control["capability"]
        schedule = VoltageSchedule(Float64(s["v_ref"]); v_db_low=Float64(s["v_db_low"]),
            v_db_high=Float64(s["v_db_high"]), unit=Symbol(s["unit"]))
        capability = ReactiveCapability(; (Symbol(k)=>Float64(cap[k]) for k in ("p_min","p_max","q_min","q_max"))...)
        push!(controls, VoltVarDroop(schedule,Float64(control["slope"]),Float64(control["q_at_deadband"]),capability))
    end
    attachments = GeneratorControlAttachment[]
    for a in c["attachments"]
        l = a["location"]
        location = RegulatedLocation(Symbol(l["kind"]),l["bus_id"];
            side=isnothing(l["side"]) ? nothing : Symbol(l["side"]),
            branch_id=get(l,"branch_id",nothing))
        push!(attachments,GeneratorControlAttachment(a["generator_id"],a["control_id"],location; priority=Symbol(a["priority"])))
    end
    case = Case(c["id"]; base_power=Float64(c["base_power"]),base_frequency=Float64(c["base_frequency"]),
        network=ACNetwork(buses,branches;shunts=shunts,banks=banks),loads=loads,generators=generators,controls=controls,attachments=attachments)
    contingencies = [Contingency(Symbol(k["id"]); generator_ids=Int.(k["generator_ids"]),
        branch_ids=Int.(k["branch_ids"])) for k in data["contingencies"]]
    return Study(case; contingencies=contingencies,mode=Symbol(data["mode"]),
        participation=Dict(parse(Int,k)=>Float64(v) for (k,v) in data["participation"]),
        redispatch_limits=Dict(parse(Int,k)=>Float64(v) for (k,v) in data["redispatch_limits"]),
        reactive_assignments=_reactive_assignments_from_data(data["reactive_assignments"]),
        tap_controls=_tap_controls_from_data(data["tap_controls"]),
        shunt_controls=_shunt_controls_from_data(data["shunt_controls"]),
        control_policy=_control_policy_from_data(data["control_policy"]))
end

function _scopf_result_from_data(d)
    states = Dict{Symbol,Union{Nothing,ACState{Float64}}}()
    for (id,state) in d["states"]
        states[Symbol(id)] = isnothing(state) ? nothing : ACState(
            (Float64.(state[k]) for k in ("vm","va","pg","qg"))...)
    end
    return SCOPFResult(states,
        Dict(Symbol(k)=>(isnothing(v) ? NaN : Float64(v)) for (k,v) in d["balancing_power"]),
        isnothing(d["objective"]) ? NaN : Float64(d["objective"]),
        Symbol(d["termination_status"]),Symbol(d["primal_status"]),Symbol(d["mode"]),Symbol(d["encoding"]),
        Float64(d["smooth_epsilon"]),Float64(d["smooth_reactive_relative_epsilon"]),
        isnothing(d["smooth_reactive_epsilon"]) ? nothing : Float64(d["smooth_reactive_epsilon"]),d["solver"],
        _reactive_assignments_from_data(d["reactive_assignments"]),
        Dict(Symbol(id)=>Dict(parse(Int,k)=>(isnothing(v) ? NaN : Float64(v))
            for (k,v) in settings)
            for (id,settings) in d["tap_settings"]),
        Dict(Symbol(id)=>Dict(parse(Int,k)=>(isnothing(v) ? NaN : Float64(v))
            for (k,v) in settings)
            for (id,settings) in d["shunt_settings"]),
        _tap_controls_from_data(d["tap_controls"]),
        _shunt_controls_from_data(d["shunt_controls"]),
        _control_policy_from_data(d["control_policy"]))
end

"""Load saved states and metadata. Revalidate them against the corresponding study before use."""
read_scopf_result(path::AbstractString) =
    _scopf_result_from_data(_read_scopf_json(path,"DroopOPF.SCOPFResult"))
