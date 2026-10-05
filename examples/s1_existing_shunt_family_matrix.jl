include("s1_existing_shunts.jl")
include("s1_smooth_control_family_matrix.jl")
isdefined(@__MODULE__, :s1_epsilon_relaxed_valid) || include("s1_epsilon_sensitivity.jl")

function s1_existing_family_rows(out)
    path = joinpath(out, "summary.json")
    isfile(path) || return Dict{String,Any}[]
    parsed = JSON.parsefile(path)
    raw = parsed isa AbstractDict ? get(parsed, "rows", Any[]) : parsed
    Dict{String,Any}[Dict{String,Any}(string(k)=>v for (k,v) in row) for row in raw]
end

function s1_existing_family_diagnostic!(row; tolerance=1e-2)
    attempts = get(row, "attempts", Any[])
    final = isempty(attempts) ? Dict{String,Any}() : last(attempts)
    physical = get(final, "physical", Dict{String,Any}())
    row["exact_droop_residual_pu"] = get(physical, "droop_residual_max", nothing)
    row["relaxed_droop_tolerance"] = tolerance
    row["relaxed_droop_valid"] = s1_epsilon_relaxed_valid(final;
        droop_tolerance=tolerance)
    return row
end

function s1_existing_family_report(out, rows; planned_attempts, load_label)
    payload = Dict(
        "scope"=>"existing-fixed-shunt continuous-envelope control-family matrix",
        "load_label"=>load_label, "epsilon"=>1e-6,
        "strict_exact_droop_tolerance"=>1e-5,
        "diagnostic_exact_droop_tolerance"=>1e-2,
        "completion_status"=>length(rows)==planned_attempts ? "complete" : "partial",
        "completed_attempts"=>length(rows), "planned_attempts"=>planned_attempts,
        "rows"=>rows,
    )
    write(joinpath(out, "summary.json"), JSON.json(payload; pretty=true)*"\n")
    open(joinpath(out, "report.md"), "w") do io
        println(io, "# Existing-shunt continuous-envelope family matrix\n")
        println(io, "This checkpointed matrix replaces every available nonzero-B source fixed shunt by a continuous `alpha` envelope, `G=alpha*G0`, `B=alpha*B0`, `0<=alpha<=1`. It adds no compensation capacity and makes no claim that the source hardware is switchable. Discrete-step and AVR post-checks remain deferred. All converted devices start at `alpha=1`; nominal admittance and anchor feasibility are verified before solving.\n")
        println(io, "The frozen one-reset policy, epsilon `1e-6`, three starts, and strict exact-droop gate `1e-5` are unchanged. A retry is warm-started only from the finite compatible iterate of its own first attempt with solver-specific dual reset. Cells and declared starts are otherwise independent: no accepted solution is propagated to another family, load, start, network, or backend. The `1e-2` result is diagnostic only; every row retains its raw mismatch. Load scope: **$load_label**. Status: **$(payload["completion_status"])** ($(length(rows))/$planned_attempts cells).\n")
        println(io, "| Free families | Ipopt strict / diag | MadNLP strict / diag | Combined strict / diag |\n|---|---:|---:|---:|")
        for family in S1_SMOOTH_FAMILIES
            groups = [filter(r -> r["solver"]==string(s) && r["tags"]["family"]==string(family), rows)
                for s in (:ipopt, :madnlp)]
            vals(g, key) = count(r -> get(r, key, false), g)
            both = vcat(groups...)
            println(io, "| $family | $(vals(groups[1], "valid"))/$(vals(groups[1], "relaxed_droop_valid")) / $(length(groups[1])) | ",
                "$(vals(groups[2], "valid"))/$(vals(groups[2], "relaxed_droop_valid")) / $(length(groups[2])) | ",
                "$(vals(both, "valid"))/$(vals(both, "relaxed_droop_valid")) / $(length(both)) |")
        end
        println(io, "\nCell notation is `strict/diagnostic / attempts`; diagnostic acceptance keeps every non-droop gate unchanged.\n")
        println(io, "| Solver/network/load/family | Strict | Diagnostic | Attempts | Starts strict (A/L/H) | Raw mismatch range (pu) |\n|---|---:|---:|---:|---|---|")
        keys = sort(unique((r["solver"],r["tags"]["network"],r["tags"]["load_factor"],r["tags"]["family"]) for r in rows))
        for (solver, network, load, family) in keys
            g=filter(r->r["solver"]==solver && r["tags"]["network"]==network && r["tags"]["load_factor"]==load && r["tags"]["family"]==family,rows)
            starts=Dict(r["tags"]["start"]=>get(r,"valid",false) for r in g)
            mark(k)=get(starts,k,false) ? "✓" : "–"
            residuals=Float64[x for x in (get(r,"exact_droop_residual_pu",nothing) for r in g) if x isa Number && isfinite(x)]
            range=isempty(residuals) ? "—" : "$(minimum(residuals))–$(maximum(residuals))"
            println(io,"| $solver/$network/$load/$family | $(count(r->get(r,"valid",false),g)) | $(count(r->get(r,"relaxed_droop_valid",false),g)) | $(length(g)) | $(mark("anchor"))/$(mark("flat_low"))/$(mark("flat_high")) | $range |")
        end
        println(io, "\nFailures remain algorithmic evidence, not infeasibility certificates. The 1.05 load study, when present, is a separately labelled near-limit challenge because the untouched IEEE-300 source case failed at 1.05 after succeeding through 1.04.")
    end
    payload
end

function s1_existing_shunt_family_matrix(out; load_factors=(1.0,1.03),
    load_label="nominal plus raw-qualified 1.03 stress")
    mkpath(out)
    rows=s1_existing_family_rows(out); completed=Set(r["name"] for r in rows)
    planned=2*2*length(load_factors)*3*length(S1_SMOOTH_FAMILIES)
    for solver in (:ipopt,:madnlp), n in (118,300)
        source=joinpath(@__DIR__,"..","test","data","pglib","v23.07","pglib_opf_case$(n)_ieee.m")
        original=load_matpower_case(source;base_frequency=60.)
        anchor=read_joint_design(joinpath(@__DIR__,"..","artifacts","s1_public_controls","public$n-baseline-design.json"))
        base,all_policies,metadata=s1_existing_shunt_overlay(original,anchor,source)
        overlay=joinpath(out,"public$n-overlay.json")
        isfile(overlay) || write(overlay,JSON.json(metadata;pretty=true)*"\n")
        for factor in load_factors, family in S1_SMOOTH_FAMILIES, start_kind in (:anchor,:flat_low,:flat_high)
            name="public$n-load$factor-$solver-$family-$start_kind-existing"
            name in completed && continue
            case=s1_load(base,factor); selected=s1_smooth_family(all_policies,family)
            state=start_kind==:anchor ? anchor.opf.state : s1_flat(case)
            policies=start_kind==:anchor ? selected : s1_reseed(case,selected;
                fraction=start_kind==:flat_low ? .2 : .8)
            row,result=s1_run_policy(out,name,case,state;policies,solver,epsilon=1e-6,
                tags=Dict("study"=>"s1_existing_shunt_family_matrix_v1","network"=>n,
                    "load_factor"=>factor,"family"=>string(family),"start"=>string(start_kind),
                    "shunt_assumption"=>"continuous 0-to-source-admittance envelope"))
            s1_existing_family_diagnostic!(row)
            get(row,"valid",false) && (row["source_audit"]=s1_source_audit(case,result,source))
            push!(rows,row);push!(completed,name)
            s1_existing_family_report(out,rows;planned_attempts=planned,load_label)
            println("EXISTING FAMILY $name strict=$(row["valid"]) diagnostic=$(row["relaxed_droop_valid"])");flush(stdout)
        end
    end
    s1_existing_family_report(out,rows;planned_attempts=planned,load_label)
end

if abspath(PROGRAM_FILE)==(@__FILE__)
    isempty(ARGS) && error("usage: julia --project=. examples/s1_existing_shunt_family_matrix.jl OUTPUT [LOADS] [LABEL]")
    loads=length(ARGS)>=2 ? Tuple(parse.(Float64,split(ARGS[2],','))) : (1.0,1.03)
    label=length(ARGS)>=3 ? ARGS[3] : "nominal plus raw-qualified 1.03 stress"
    s1_existing_shunt_family_matrix(abspath(ARGS[1]);load_factors=loads,load_label=label)
end
