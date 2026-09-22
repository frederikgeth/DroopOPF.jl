using DroopOPF, JSON
import CCOpt
include("s1_ccopt_pilot.jl")

const S1_CCOPT_FAMILIES = (
    :fixed, :droop, :tap, :shunt, :tap_shunt, :tap_droop, :shunt_droop, :joint,
)

"""Select the same declared control family without changing case physics or bounds."""
function s1_ccopt_family(policies, family::Symbol; count::Int=1)
    family in S1_CCOPT_FAMILIES || error("unknown CCOpt family: $family")
    take(xs) = xs[1:min(count, length(xs))]
    use_tap = family in (:tap, :tap_shunt, :tap_droop, :joint)
    use_shunt = family in (:shunt, :tap_shunt, :shunt_droop, :joint)
    use_droop = family in (:droop, :tap_droop, :shunt_droop, :joint)
    (
        tap_controls=use_tap ? take(policies.tap_controls) : TapControl[],
        shunt_controls=use_shunt ? take(policies.shunt_controls) : ShuntControl[],
        droop_controls=use_droop ? take(policies.droop_controls) : DroopControl[],
    )
end

function s1_ccopt_profile(name::Symbol)
    name == :standard && return Dict{String,Any}()
    name == :tight && return Dict{String,Any}(
        "relaxation_update"=>CCOpt.ProportionalRelaxationUpdate(sigma_min=1e-14),
        "tol"=>1e-11, "acceptable_tol"=>1e-11,
    )
    error("unknown CCOpt accuracy profile: $name")
end

function s1_ccopt_matrix_report(out, rows; planned_attempts=96)
    summary=Dict{String,Any}()
    group_keys=sort(unique((r["tags"]["network"],r["tags"]["load_factor"],r["tags"]["family"]) for r in rows))
    for (network,load,family) in group_keys
        group=filter(r->r["tags"]["network"]==network && r["tags"]["load_factor"]==load && r["tags"]["family"]==family,rows)
        valid=filter(r->get(r,"valid",false),group)
        audited=filter(r->begin
            audit=get(r,"exact_droop_audit",nothing)
            !isnothing(audit) && !isnothing(get(audit,"max_residual_pu",nothing))
        end,group)
        worst=isempty(audited) ? nothing : maximum(get(r["exact_droop_audit"],"max_residual_pu",0.) for r in audited)
        ratio=isempty(audited) ? nothing : maximum(get(r["exact_droop_audit"],"max_ratio_to_tolerance",0.) for r in audited)
        summary["$network-load$load-$family"]=Dict("attempts"=>length(group),"valid"=>length(valid),
            "objective_min"=>isempty(valid) ? nothing : minimum(r["objective"] for r in valid),
            "objective_max"=>isempty(valid) ? nothing : maximum(r["objective"] for r in valid),
            "worst_exact_droop_residual_pu"=>worst,"worst_ratio_to_physical_tolerance"=>ratio)
    end
    payload=Dict("scope"=>"matched S1 CCOpt control-family matrix; separate from frozen Ipopt/MadNLP acceptance counts",
        "completion_status"=>length(rows)==planned_attempts ? "complete" : "partial",
        "completed_attempts"=>length(rows),"planned_attempts"=>planned_attempts,
        "accuracy_profile"=>"tight profile declared before the matrix", "rows"=>rows,"groups"=>summary)
    write(joinpath(out,"summary.json"),JSON.json(payload;pretty=true)*"\n")
    open(joinpath(out,"report.md"),"w") do io
        println(io,"# Matched S1 CCOpt control-family matrix\n")
        status=length(rows)==planned_attempts ? "complete" : "partial"
        println(io,"The tighter CCOpt profile is frozen for this matrix. Every attempt retains independent solver, AC, equipment-policy and exact-droop acceptance. Runs are checkpointed and resumable. This matrix remains separate from the frozen Ipopt/MadNLP counts.\n")
        println(io,"Status: **$status** ($(length(rows))/$planned_attempts attempts retained).\n")
        println(io,"| Network/load/family | Valid | Attempts | Objective range | Worst exact-droop residual / criterion |\n|---|---:|---:|---:|---:|")
        for key in sort(collect(keys(summary)))
            g=summary[key]; range=isnothing(g["objective_min"]) ? "—" : "$(g["objective_min"]) – $(g["objective_max"])"
            residual=isnothing(g["worst_exact_droop_residual_pu"]) ? "not yet audited" : "$(g["worst_exact_droop_residual_pu"]) / $(g["worst_ratio_to_physical_tolerance"])×"
            println(io,"| $key | $(g["valid"]) | $(g["attempts"]) | $range | $residual |")
        end
        println(io,"\nCCOpt's reported relaxed-NLP dual feasibility is not an original-MPCC stationarity certificate. Separate outer-homotopy iteration counts are unavailable through the current MOI wrapper.")
    end
    payload
end

"""Add direct exact-droop audits to retained matrix rows without rerunning CCOpt."""
function s1_ccopt_refresh_audits(out; networks=(118,300),planned_attempts=96)
    rows=_completed_ccopt_rows(out)
    cases=Dict{Int,Case}()
    for n in networks
        source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case$(n)_ieee.m")
        original=load_matpower_case(source;base_frequency=60.)
        anchor=optimize_joint_design(original;initial_state=s1_flat(original),
            optimizer_attributes=Dict("max_iter"=>1000,"max_cpu_time"=>60.))
        validate_joint_design(original,anchor).valid || error("IEEE $n anchor failed validation")
        cases[n]=first(s1_public_overlay(original,anchor,source;bank_count=n==118 ? 12 : 32))
    end
    for row in rows
        tags=row["tags"];n=Int(tags["network"]);haskey(cases,n) || continue
        case=s1_load(cases[n],Float64(tags["load_factor"]))
        design_path=joinpath(out,row["name"]*"-design.json")
        isfile(design_path) || continue
        audit=exact_droop_audit(case,read_joint_design(design_path))
        row["exact_droop_audit"]=audit
        diagnostic_path=joinpath(out,row["name"]*"-diagnostics.json")
        if isfile(diagnostic_path)
            diagnostic=JSON.parsefile(diagnostic_path)
            diagnostic["exact_droop_audit"]=audit
            write(diagnostic_path,JSON.json(diagnostic;pretty=true)*"\n")
        end
    end
    s1_ccopt_matrix_report(out,rows;planned_attempts)
end

function _completed_ccopt_rows(out)
    path=joinpath(out,"summary.json")
    isfile(path) || return Dict{String,Any}[]
    parsed=JSON.parsefile(path)
    Dict{String,Any}[Dict{String,Any}(r) for r in get(parsed,"rows",Any[])]
end

"""Run a checkpointed 118/300, nominal/+5%, eight-family, three-start CCOpt matrix."""
function s1_ccopt_matrix(out; networks=(118,300), load_factors=(1.0,1.05),
    starts=(:anchor,:flat_low,:flat_high), families=S1_CCOPT_FAMILIES,
    profile=:tight, control_count=1)
    mkpath(out);rows=_completed_ccopt_rows(out)
    completed=Set(r["name"] for r in rows)
    options=s1_ccopt_profile(profile)
    planned_attempts=length(networks)*length(load_factors)*length(starts)*length(families)
    for n in networks
        source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case$(n)_ieee.m")
        original=load_matpower_case(source;base_frequency=60.)
        anchor=optimize_joint_design(original;initial_state=s1_flat(original),
            optimizer_attributes=Dict("max_iter"=>1000,"max_cpu_time"=>60.))
        validate_joint_design(original,anchor).valid || error("IEEE $n anchor failed validation")
        case,all_policies,metadata=s1_public_overlay(original,anchor,source;bank_count=n==118 ? 12 : 32)
        write(joinpath(out,"public$n-overlay.json"),JSON.json(metadata;pretty=true)*"\n")
        for factor in load_factors, family in families, mode in starts
            name="public$n-load$factor-$(family)-$(mode)-count$control_count-$profile"
            name in completed && continue
            base=s1_ccopt_family(all_policies,family;count=control_count)
            policies=mode==:anchor ? base : s1_reseed(case,base;fraction=mode==:flat_low ? .2 : .8)
            state=mode==:anchor ? anchor.opf.state : s1_flat(case)
            row,_=s1_ccopt_attempt(out,name,s1_load(case,factor),state;policies,
                option_overrides=options,tags=Dict("study"=>"matched_ccopt_family",
                    "network"=>n,"load_factor"=>factor,"family"=>string(family),
                    "start"=>string(mode),"control_count"=>control_count,
                    "accuracy_profile"=>string(profile),
                    "acceptance_scope"=>"outside frozen Ipopt/MadNLP counts"))
            push!(rows,row);push!(completed,name);s1_ccopt_matrix_report(out,rows;planned_attempts)
        end
    end
    s1_ccopt_matrix_report(out,rows;planned_attempts)
end

if abspath(PROGRAM_FILE)==(@__FILE__)
    isempty(ARGS) && error("usage: julia --project=. examples/s1_ccopt_matrix.jl OUTPUT [NETWORKS] [LOADS] [STARTS]")
    networks=length(ARGS)>=2 ? Tuple(parse.(Int,split(ARGS[2],','))) : (118,300)
    loads=length(ARGS)>=3 ? Tuple(parse.(Float64,split(ARGS[3],','))) : (1.0,1.05)
    starts=length(ARGS)>=4 ? Tuple(Symbol.(split(ARGS[4],','))) : (:anchor,:flat_low,:flat_high)
    s1_ccopt_matrix(abspath(ARGS[1]);networks,load_factors=loads,starts)
end
