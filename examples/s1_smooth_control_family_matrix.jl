include("s1_policy_matrix.jl")

const S1_SMOOTH_FAMILIES = (
    :fixed, :droop, :tap, :shunt, :tap_shunt, :tap_droop, :shunt_droop, :joint,
)

"""Select complete free-control families while retaining every case droop curve."""
function s1_smooth_family(policies, family::Symbol)
    family in S1_SMOOTH_FAMILIES || error("unknown smooth control family: $family")
    use_tap = family in (:tap, :tap_shunt, :tap_droop, :joint)
    use_shunt = family in (:shunt, :tap_shunt, :shunt_droop, :joint)
    use_droop = family in (:droop, :tap_droop, :shunt_droop, :joint)
    (
        tap_controls=use_tap ? policies.tap_controls : TapControl[],
        shunt_controls=use_shunt ? policies.shunt_controls : ShuntControl[],
        droop_controls=use_droop ? policies.droop_controls : DroopControl[],
    )
end

function s1_smooth_family_rows(out)
    path = joinpath(out, "summary.json")
    isfile(path) || return Dict{String,Any}[]
    parsed = JSON.parsefile(path)
    raw = parsed isa AbstractDict ? get(parsed, "rows", Any[]) : parsed
    return Dict{String,Any}[Dict{String,Any}(string(k)=>v for (k,v) in row) for row in raw]
end

function s1_smooth_family_report(out, rows; planned_attempts=192)
    groups = Dict{String,Any}()
    group_keys = sort(unique((r["solver"], r["tags"]["network"],
        r["tags"]["load_factor"], r["tags"]["family"]) for r in rows))
    for (solver, network, load_factor, family) in group_keys
        group = filter(r -> r["solver"] == solver && r["tags"]["network"] == network &&
            r["tags"]["load_factor"] == load_factor && r["tags"]["family"] == family, rows)
        valid = count(r -> get(r, "valid", false), group)
        groups["$solver-$network-load$load_factor-$family"] = Dict(
            "attempts"=>length(group), "valid"=>valid,
            "starts"=>Dict(r["tags"]["start"]=>get(r, "valid", false) for r in group),
        )
    end
    payload = Dict(
        "scope"=>"matched smooth S1 control-family isolation matrix",
        "epsilon"=>1e-6, "exact_droop_tolerance"=>1e-5,
        "completion_status"=>length(rows) == planned_attempts ? "complete" : "partial",
        "completed_attempts"=>length(rows), "planned_attempts"=>planned_attempts,
        "rows"=>rows, "groups"=>groups,
    )
    write(joinpath(out, "summary.json"), JSON.json(payload; pretty=true) * "\n")
    open(joinpath(out, "report.md"), "w") do io
        println(io, "# S1 smooth control-family isolation matrix\n")
        println(io, "This checkpointed matrix uses the frozen Ipopt/MadNLP one-reset policy, epsilon `1e-6`, exact-droop tolerance `1e-5`, public 118/300 overlays, nominal/+5% loads, and anchor/flat-low/flat-high starts. Each family includes **all** controls of that type. `fixed` means *no free design variables*: the overlay's droop equalities remain active at their nominal anchor-derived settings, selected banks remain disconnected, and transformer ratios retain their source values. It is not the untouched PGLib OPF. No result replaces the original joint frozen decision.\n")
        println(io, "Status: **", payload["completion_status"], "** (", length(rows), "/", planned_attempts, " cells).\n")
        println(io, "## Aggregate acceptance\n")
        println(io, "| Free families | Ipopt | MadNLP | Combined |\n|---|---:|---:|---:|")
        for family in S1_SMOOTH_FAMILIES
            bysolver = [filter(r -> r["solver"] == string(solver) &&
                r["tags"]["family"] == string(family), rows) for solver in (:ipopt, :madnlp)]
            allfamily = vcat(bysolver...)
            println(io, "| ", family, " | ", count(r -> get(r, "valid", false), bysolver[1]),
                "/", length(bysolver[1]), " | ", count(r -> get(r, "valid", false), bysolver[2]),
                "/", length(bysolver[2]), " | ", count(r -> get(r, "valid", false), allfamily),
                "/", length(allfamily), " |")
        end
        println(io, "\n## Paired family effects\n")
        println(io, "Each row adds exactly one free family. Positive values mean more accepted cells; they diagnose numerical interaction, not physical value.\n")
        println(io, "| Added family / context | Ipopt delta | MadNLP delta | Combined delta |\n|---|---:|---:|---:|")
        contrasts = (
            ("droop to fixed", :fixed, :droop),
            ("droop with tap", :tap, :tap_droop),
            ("droop with shunt", :shunt, :shunt_droop),
            ("droop with tap+shunt", :tap_shunt, :joint),
            ("tap to fixed", :fixed, :tap),
            ("tap with droop", :droop, :tap_droop),
            ("tap with shunt", :shunt, :tap_shunt),
            ("tap with shunt+droop", :shunt_droop, :joint),
            ("shunt to fixed", :fixed, :shunt),
            ("shunt with droop", :droop, :shunt_droop),
            ("shunt with tap", :tap, :tap_shunt),
            ("shunt with tap+droop", :tap_droop, :joint),
        )
        valid_count(family, solver=nothing) = count(r -> get(r, "valid", false) &&
            r["tags"]["family"] == string(family) &&
            (isnothing(solver) || r["solver"] == string(solver)), rows)
        signed(value) = value > 0 ? "+$value" : string(value)
        for (label, before, after) in contrasts
            di = valid_count(after, :ipopt) - valid_count(before, :ipopt)
            dm = valid_count(after, :madnlp) - valid_count(before, :madnlp)
            println(io, "| ", label, " | ", signed(di), " | ", signed(dm),
                " | ", signed(di + dm), " |")
        end
        println(io, "\n## Detailed slices\n")
        println(io, "| Solver/network/load/family | Valid | Attempts | Start outcomes (A/L/H) |\n|---|---:|---:|---|")
        for key in sort(collect(keys(groups)))
            group = groups[key]; starts = group["starts"]
            mark(name) = get(starts, name, false) ? "✓" : "–"
            println(io, "| $key | ", group["valid"], " | ", group["attempts"],
                " | ", mark("anchor"), "/", mark("flat_low"), "/", mark("flat_high"), " |")
        end
        println(io, "\nInterpretation rule: a family that succeeds alone but degrades in a pair identifies an interaction; failure of the fixed family means the control family cannot be assigned primary blame for that cell. Failures remain algorithmic evidence, not infeasibility certificates.")
    end
    return payload
end

"""Run all fixed/single/pair/joint combinations under the frozen smooth policy."""
function s1_smooth_control_family_matrix(out; solvers=(:ipopt, :madnlp),
    networks=(118, 300), load_factors=(1.0, 1.05),
    starts=(:anchor, :flat_low, :flat_high), families=S1_SMOOTH_FAMILIES)
    mkpath(out)
    rows = s1_smooth_family_rows(out)
    completed = Set(r["name"] for r in rows)
    planned_attempts = length(solvers) * length(networks) * length(load_factors) *
        length(starts) * length(families)
    for solver in solvers, n in networks
        source = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07",
            "pglib_opf_case$(n)_ieee.m")
        original = load_matpower_case(source; base_frequency=60.0)
        anchor = read_joint_design(joinpath(@__DIR__, "..", "artifacts",
            "s1_public_controls", "public$n-baseline-design.json"))
        base_case, all_policies, metadata = s1_public_overlay(original, anchor, source;
            bank_count=n == 118 ? 12 : 32)
        overlay_path = joinpath(out, "public$n-overlay.json")
        isfile(overlay_path) || write(overlay_path, JSON.json(metadata; pretty=true) * "\n")
        for factor in load_factors, family in families, start_kind in starts
            name = "public$n-load$factor-$solver-$family-$start_kind"
            name in completed && continue
            case = s1_load(base_case, factor)
            selected = s1_smooth_family(all_policies, family)
            state = start_kind == :anchor ? anchor.opf.state : s1_flat(case)
            policies = start_kind == :anchor ? selected : s1_reseed(case, selected;
                fraction=start_kind == :flat_low ? 0.2 : 0.8)
            row, result = s1_run_policy(out, name, case, state; policies, solver,
                epsilon=1e-6, tags=Dict("study"=>"s1_smooth_control_family_matrix_v1",
                    "network"=>n, "load_factor"=>factor, "family"=>string(family),
                    "start"=>string(start_kind), "all_controls_in_selected_families"=>true,
                    "excluded_families"=>"fixed at supplied overlay values"))
            if get(row, "valid", false)
                row["source_audit"] = s1_source_audit(case, result, source)
            end
            push!(rows, row); push!(completed, name)
            s1_smooth_family_report(out, rows; planned_attempts)
            println("FAMILY ", name, " valid=", row["valid"]); flush(stdout)
        end
    end
    return s1_smooth_family_report(out, rows; planned_attempts)
end

if abspath(PROGRAM_FILE) == (@__FILE__)
    isempty(ARGS) && error("usage: julia --project=. examples/s1_smooth_control_family_matrix.jl OUTPUT [SOLVERS] [NETWORKS] [LOADS] [STARTS] [FAMILIES]")
    solvers = length(ARGS) >= 2 ? Tuple(Symbol.(split(ARGS[2], ','))) : (:ipopt, :madnlp)
    networks = length(ARGS) >= 3 ? Tuple(parse.(Int, split(ARGS[3], ','))) : (118, 300)
    loads = length(ARGS) >= 4 ? Tuple(parse.(Float64, split(ARGS[4], ','))) : (1.0, 1.05)
    starts = length(ARGS) >= 5 ? Tuple(Symbol.(split(ARGS[5], ','))) : (:anchor, :flat_low, :flat_high)
    families = length(ARGS) >= 6 ? Tuple(Symbol.(split(ARGS[6], ','))) : S1_SMOOTH_FAMILIES
    s1_smooth_control_family_matrix(abspath(ARGS[1]); solvers, networks,
        load_factors=loads, starts, families)
end
