# Follow-up requires fresh user confirmation of equipment policy and G5-trip
# assumption. Preparation/import performs no numerical solves.
include("s2_arpae14_campaign.jl")
const S214_FOLLOWUP=joinpath(S214_OUT,"followup")
function s214_island_projection(study,result,angles)
    c=study.case;source=Contingency(:line_7_8;branch_ids=[11])
    base=result.states[:base];witness=result.states[:generator_5]
    reduced=islanded_scenario_case(c,source,base)
    @assert reduced.selection.discarded_bus_ids==[8]
    @assert reduced.selection.discarded_load_p==0.
    @assert [g.id for g in reduced.case.generators]==[1,2,3,4]
    busidx=DroopOPF._bus_indices(c.network);genidx=Dict(g.id=>i for (i,g) in enumerate(c.generators))
    state=ACState([witness.vm[busidx[b.id]] for b in reduced.case.network.buses],
        [witness.va[busidx[b.id]] for b in reduced.case.network.buses],
        [witness.pg[genidx[g.id]] for g in reduced.case.generators],
        [witness.qg[genidx[g.id]] for g in reduced.case.generators])
    taps=result.tap_settings[:generator_5];banks=result.shunt_settings[:generator_5]
    physical=with_shunt_settings(with_tap_settings(reduced.case,taps),banks)
    check=validate_equilibrium(physical,state)
    ids=DroopOPF._bus_indices(physical.network)
    angle_margin=minimum(min(state.va[ids[b.from_bus]]-state.va[ids[b.to_bus]]-angles[b.id][1],
        angles[b.id][2]-state.va[ids[b.from_bus]]+state.va[ids[b.to_bus]])
        for b in physical.network.branches if b.available)
    total=sum(study.participation[g.id] for g in reduced.case.generators)
    delta=result.balancing_power[:generator_5]
    coupling=maximum(abs(state.pg[i]-base.pg[genidx[g.id]]-study.participation[g.id]/total*delta)
        for (i,g) in enumerate(reduced.case.generators))
    valid=check.valid && angle_margin>=-1e-6 && coupling<=1e-6
    (;valid,case=reduced.case,state,taps,susceptances=banks,selection=reduced.selection,
        physical=check,angle_min_margin_rad=angle_margin,response_coupling_max_pu=coupling,
        source_state=:generator_5,assumption="G5 tripped; unloaded bus 8 disconnected; no protection/dynamic validation")
end
function s214_followup(confirmation::AbstractString)
    isempty(strip(confirmation)) && error("Explicit user confirmation is required")
    mkpath(S214_FOLLOWUP)
    original=read_study(joinpath(S214_OUT,"full-designed-ipopt/optimized_input.json"))
    selected=read_scopf_result(joinpath(S214_OUT,"full-designed-ipopt/result.json"))
    angles=fd_inputs(14).angles
    protocol=(;confirmation,selected_controller="Nominal full-designed-ipopt shared curves, frozen at all demands",
        factors=[.9,.95,1.,1.05,1.1],solvers=[:ipopt,:madnlp,:ccopt],
        tap_controls=original.tap_controls,shunt_controls=original.shunt_controls,
        control_policy=original.control_policy,island_assumption="Line 11 (7–8) removed, G5 tripped and unloaded bus 8 disconnected; retained-network steady-state only",
        primary_budget=(iterations=600,native_seconds=20),retry_budget=(iterations=3000,native_seconds=120,max_per_lane=1))
    fd_save(joinpath(S214_FOLLOWUP,"protocol.json"),protocol)
    # Original 24-outage results are kept unchanged. Project existing generator-5
    # outage witnesses to a separate, explicitly conditional island contract.
    nominal=Any[]
    for name in ("full-frozen-ipopt","full-designed-ipopt","full-frozen-madnlp","full-designed-madnlp","exact-frozen-ccopt","exact-designed-ccopt")
        study=read_study(joinpath(S214_OUT,name,"optimized_input.json"))
        result=read_scopf_result(joinpath(S214_OUT,name,"result.json"))
        projection=s214_island_projection(study,result,angles)
        fd_save(joinpath(S214_FOLLOWUP,"island-"*name*".json"),projection)
        push!(nominal,(;name,valid=projection.valid))
    end
    rows=Any[]
    for solver in (:ipopt,:madnlp,:ccopt)
        prior=selected
        for f in (1.,.95,.9,1.05,1.1)
            c=DroopOPF._feasibility_scaled_case(original.case,f)
            study=DroopOPF._copy_study(original;case=c)
            prefix="followup/$(solver)-demand-$f"
            lane=s214_attempt(prefix,study,DroopControl[],s214_starts(study,selected.states[:base],prior),angles;solver)
            primary=lane.record
            if !lane.record["accepted"]
                lane=s214_attempt("followup/retry-$(solver)-demand-$f",study,DroopControl[],
                    s214_starts(study,selected.states[:base],lane.result),angles;solver,retry=true)
            end
            projection=isnothing(lane.result) || any(isnothing,get(lane.result.states,id,nothing) for id in [:base,:generator_5]) ?
                nothing : s214_island_projection(study,lane.result,angles)
            isnothing(projection) || fd_save(joinpath(S214_FOLLOWUP,"island-$(solver)-demand-$f.json"),projection)
            push!(rows,(;solver,factor=f,primary,final=lane.record,island_valid=!isnothing(projection) && projection.valid,
                accepted_with_trip_assumption=lane.record["accepted"] && !isnothing(projection) && projection.valid))
            fd_save(joinpath(S214_FOLLOWUP,"summary.json"),(;nominal_island_projections=nominal,attempts=rows,
                scope="Frozen nominal Ipopt controller; 24 connected outages plus conditional line-11/G5-trip retained-network projection",
                general_full_n1_claim=false))
            isnothing(lane.result) || (prior=lane.result)
        end
    end
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    length(ARGS)==1 || error("Supply the explicit confirmed follow-up scope as one argument")
    s214_followup(only(ARGS))
end
