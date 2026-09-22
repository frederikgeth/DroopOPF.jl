using DroopOPF, JSON
include("s1_ccopt_pilot.jl")

"""Pick declared one-control local/remote placements from one unchanged overlay."""
function s1_ccopt_placement_candidates(case, policies)
    attachments=Dict(a.control_id=>a for a in case.attachments)
    terminal_controls(tap)=sort([a.control_id for a in case.attachments if
        a.location.bus_id==tap.from_bus || a.location.bus_id==tap.to_bus])
    selected_taps=[only(filter(b->b.id==p.branch_id,case.network.branches)) for p in policies.tap_controls]
    local_taps=filter(t->!isempty(terminal_controls(t)),selected_taps)
    remote_taps=filter(t->isempty(terminal_controls(t)),selected_taps)
    droop_buses=Set(a.location.bus_id for a in case.attachments)
    selected_banks=[only(filter(b->b.id==p.bank_id,case.network.banks)) for p in policies.shunt_controls]
    local_banks=filter(b->b.bus_id in droop_buses,selected_banks)
    remote_banks=filter(b->!(b.bus_id in droop_buses),selected_banks)
    isempty(local_taps) && error("overlay has no tap with a terminal droop")
    isempty(remote_taps) && error("overlay has no tap without a terminal droop")
    isempty(local_banks) && error("overlay has no bank colocated with a droop")
    isempty(remote_banks) && error("overlay has no bank remote from a droop")
    (
        tap_terminal=first(local_taps),tap_remote=first(remote_taps),
        bank_colocated=first(local_banks),bank_remote=first(remote_banks),
        terminal_droop_controls=terminal_controls(first(local_taps)),
        attachments=attachments,
    )
end

function s1_ccopt_placement_report(out, rows, candidates)
    summary=Dict{String,Any}()
    for placement in unique(r["tags"]["placement"] for r in rows)
        group=filter(r->r["tags"]["placement"]==placement,rows)
        valid=filter(r->get(r,"valid",false),group)
        worst=maximum((get(get(r,"exact_droop_audit",Dict()),"max_residual_pu",0.) for r in group);init=0.)
        summary[placement]=Dict("attempts"=>length(group),"valid"=>length(valid),
            "worst_exact_droop_residual_pu"=>worst,"ratio_to_criterion"=>worst/1e-5)
    end
    metadata=Dict(
        "scope"=>"same IEEE 118 overlay, +5% load, three starts and fixed CCOpt budget; only one free control location varies",
        "tap_terminal"=>Dict("branch_id"=>candidates.tap_terminal.id,"from_bus"=>candidates.tap_terminal.from_bus,"to_bus"=>candidates.tap_terminal.to_bus,"terminal_droop_controls"=>candidates.terminal_droop_controls),
        "tap_remote"=>Dict("branch_id"=>candidates.tap_remote.id,"from_bus"=>candidates.tap_remote.from_bus,"to_bus"=>candidates.tap_remote.to_bus),
        "bank_colocated"=>Dict("bank_id"=>candidates.bank_colocated.id,"bus_id"=>candidates.bank_colocated.bus_id),
        "bank_remote"=>Dict("bank_id"=>candidates.bank_remote.id,"bus_id"=>candidates.bank_remote.bus_id),
        "rows"=>rows,"groups"=>summary)
    write(joinpath(out,"summary.json"),JSON.json(metadata;pretty=true)*"\n")
    open(joinpath(out,"report.md"),"w") do io
        println(io,"# IEEE 118 CCOpt placement diagnostic\n")
        println(io,"All runs use the same imported IEEE 118 overlay, +5% load, three declared starts, exact complementarity droop, and one declared CCOpt accuracy profile/budget. Only the one free control location differs. This is a diagnostic comparison, not a topology or equipment-model change.\n")
        println(io,"| Placement | Valid | Attempts | Worst exact-droop residual / 1e-5 criterion |\n|---|---:|---:|---:|")
        for (name,g) in sort(collect(summary);by=first)
            println(io,"| $name | $(g["valid"]) | $(g["attempts"]) | $(g["worst_exact_droop_residual_pu"]) / $(g["ratio_to_criterion"])× |")
        end
    end
    metadata
end

function s1_ccopt_placement(out;load_factor=1.05,profile_options=nothing)
    mkpath(out);rows=[]
    source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case118_ieee.m")
    original=load_matpower_case(source;base_frequency=60.)
    anchor=optimize_joint_design(original;initial_state=s1_flat(original),
        optimizer_attributes=Dict("max_iter"=>1000,"max_cpu_time"=>60.))
    validate_joint_design(original,anchor).valid || error("IEEE 118 anchor failed validation")
    overlay,all_policies,overlay_metadata=s1_public_overlay(original,anchor,source;bank_count=12)
    case=s1_load(overlay,load_factor);candidates=s1_ccopt_placement_candidates(case,all_policies)
    write(joinpath(out,"overlay.json"),JSON.json(overlay_metadata;pretty=true)*"\n")
    profiles=isnothing(profile_options) ? Dict{String,Any}(
        "relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14),
        "tol"=>1e-11,"acceptable_tol"=>1e-11) : profile_options
    selections=(
        ("tap_terminal",(tap_controls=[TapControl(candidates.tap_terminal.id;lower=.95*candidates.tap_terminal.tap_ratio,upper=1.05*candidates.tap_terminal.tap_ratio,nominal=candidates.tap_terminal.tap_ratio)],shunt_controls=ShuntControl[],droop_controls=DroopControl[])),
        ("tap_remote",(tap_controls=[TapControl(candidates.tap_remote.id;lower=.95*candidates.tap_remote.tap_ratio,upper=1.05*candidates.tap_remote.tap_ratio,nominal=candidates.tap_remote.tap_ratio)],shunt_controls=ShuntControl[],droop_controls=DroopControl[])),
        ("bank_colocated",(tap_controls=TapControl[],shunt_controls=[ShuntControl(candidates.bank_colocated.id)],droop_controls=DroopControl[])),
        ("bank_remote",(tap_controls=TapControl[],shunt_controls=[ShuntControl(candidates.bank_remote.id)],droop_controls=DroopControl[])),
    )
    for (placement,policy) in selections, mode in (:anchor,:flat_low,:flat_high)
        selected=mode==:anchor ? policy : s1_reseed(case,policy;fraction=mode==:flat_low ? .2 : .8)
        state=mode==:anchor ? anchor.opf.state : s1_flat(case)
        row,_=s1_ccopt_attempt(out,"placement-$placement-$mode",case,state;policies=selected,
            option_overrides=profiles,tags=Dict("study"=>"ccopt_placement","placement"=>placement,
                "start"=>string(mode),"network"=>118,"load_factor"=>load_factor,
                "same_overlay"=>true,"same_budget"=>true))
        push!(rows,row);s1_ccopt_placement_report(out,rows,candidates)
    end
    s1_ccopt_placement_report(out,rows,candidates)
end

abspath(PROGRAM_FILE)==(@__FILE__) && s1_ccopt_placement(abspath(ARGS[1]))
