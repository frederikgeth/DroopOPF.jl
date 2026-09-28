include("s1_policy_matrix.jl")

"""Build a public-case diagnostic with only the first `droop_count` controls and
first `shunt_count` synthetic banks. Source branches and fixed shunts are unchanged.
Counts are deliberately cumulative and deterministic, following the frozen overlay order.
"""
function s1_incremental_case(original, anchor, source; droop_count=0, shunt_count=0)
    full, policies, metadata = s1_public_overlay(original, anchor, source;
        bank_count=length(original.network.buses) == 118 ? 12 : 32)
    0 <= droop_count <= length(full.controls) || throw(ArgumentError("invalid droop count"))
    0 <= shunt_count <= length(full.network.banks) || throw(ArgumentError("invalid shunt count"))
    controls = full.controls[1:droop_count]
    attachments = [a for a in full.attachments if a.control_id <= droop_count]
    banks = full.network.banks[1:shunt_count]
    net = full.network
    case = Case(full.id * "-incremental-d$(droop_count)-s$(shunt_count)";
        base_power=full.base_power, base_frequency=full.base_frequency,
        network=ACNetwork(net.buses, net.branches; shunts=net.shunts, banks),
        loads=full.loads, generators=full.generators, controls, attachments)
    selected = (
        tap_controls=TapControl[],
        shunt_controls=policies.shunt_controls[1:shunt_count],
        droop_controls=policies.droop_controls[1:droop_count],
    )
    return case, selected, metadata
end

function s1_incremental_stages(droop_total, shunt_total; extra_droop_counts=Int[])
    cumulative_counts(total) = unique(vcat(
        [2^k for k in 0:floor(Int, log2(total))], [total]))
    dcounts = sort(unique(vcat(cumulative_counts(droop_total),
        [n for n in extra_droop_counts if 1 <= n <= droop_total])))
    scounts = cumulative_counts(shunt_total)
    stages = NamedTuple[
        (name="raw", droops=0, shunts=0, free_droop=false, free_shunt=false),
    ]
    for count in dcounts
        push!(stages, (name="droop$(count)-fixed", droops=count, shunts=0,
            free_droop=false, free_shunt=false))
        push!(stages, (name="droop$(count)-free", droops=count, shunts=0,
            free_droop=true, free_shunt=false))
    end
    for count in scounts
        push!(stages, (name="shunt$(count)-free", droops=0, shunts=count,
            free_droop=false, free_shunt=true))
    end
    push!(stages,
        (name="droop1-fixed-shunt1-free", droops=1, shunts=1,
            free_droop=false, free_shunt=true),
        (name="droop1-free-shunt1-free", droops=1, shunts=1,
            free_droop=true, free_shunt=true),
    )
    stages
end

"""Select arbitrary frozen-overlay droops and reindex them into a standalone case."""
function s1_selected_droop_case(original, anchor, source, selected_ids)
    full, policies, _ = s1_public_overlay(original, anchor, source;
        bank_count=length(original.network.buses) == 118 ? 12 : 32)
    ids = sort(unique(Int.(selected_ids)))
    all(i -> 1 <= i <= length(full.controls), ids) ||
        throw(ArgumentError("invalid selected droop ID"))
    mapping = Dict(old=>new for (new, old) in enumerate(ids))
    controls = full.controls[ids]
    attachments = [GeneratorControlAttachment(a.generator_id, mapping[a.control_id], a.location;
        priority=a.priority) for a in full.attachments if haskey(mapping, a.control_id)]
    case = Case(full.id * "-selected-droops-" * join(ids, "-");
        base_power=full.base_power, base_frequency=full.base_frequency,
        network=ACNetwork(full.network.buses, full.network.branches; shunts=full.network.shunts),
        loads=full.loads, generators=full.generators, controls, attachments)
    droop_controls = DroopControl[]
    for old in ids
        p = policies.droop_controls[old]
        push!(droop_controls, DroopControl(mapping[old]; slope_bounds=p.bounds.slope,
            v_ref_bounds=p.bounds.v_ref, deadband_low_bounds=p.bounds.deadband_low,
            deadband_high_bounds=p.bounds.deadband_high, initial=p.initial))
    end
    return case, droop_controls
end

"""Target an individual droop after a cumulative ladder identifies a transition."""
function s1_selected_droop_probe(out; network=300, selected_ids=(5,),
    loads=(1.0, 1.01, 1.02, 1.03), solvers=(:ipopt, :madnlp))
    mkpath(out)
    path = joinpath(out, "summary.json")
    rows = isfile(path) ? Dict{String,Any}[Dict{String,Any}(r) for r in JSON.parsefile(path)["rows"]] : Dict{String,Any}[]
    completed = Set(r["name"] for r in rows)
    source = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07",
        "pglib_opf_case$(network)_ieee.m")
    original = load_matpower_case(source; base_frequency=60.0)
    anchor = read_joint_design(joinpath(@__DIR__, "..", "artifacts", "s1_public_controls",
        "public$(network)-baseline-design.json"))
    base, controls = s1_selected_droop_case(original, anchor, source, selected_ids)
    planned = length(loads) * length(solvers) * 2
    label = join(selected_ids, "-")
    for load in loads, solver in solvers, free in (false, true)
        stage = "selected$(label)-" * (free ? "free" : "fixed")
        name = "public$(network)-load$(load)-$(solver)-$(stage)-anchor"
        name in completed && continue
        case = s1_load(base, load)
        policies = (tap_controls=TapControl[], shunt_controls=ShuntControl[],
            droop_controls=free ? controls : DroopControl[])
        tags = Dict("study"=>"s1_selected_droop_probe_v1", "network"=>network,
            "load_factor"=>load, "start"=>"anchor", "stage"=>stage,
            "selected_original_control_ids"=>collect(selected_ids),
            "droop_attachments"=>length(selected_ids), "synthetic_banks"=>0,
            "free_droops"=>free ? length(selected_ids) : 0, "free_shunts"=>0,
            "adjustable_taps"=>0)
        row, _ = s1_run_policy(out, name, case, anchor.opf.state;
            policies, solver, epsilon=1e-6, tags)
        row["reason"] = s1_incremental_reason(row)
        push!(rows, row); push!(completed, name)
        s1_incremental_report(out, rows, planned)
    end
    s1_incremental_report(out, rows, planned)
end

function s1_incremental_reason(row)
    get(row, "valid", false) && return "passed all solver, policy and physical gates"
    attempts = get(row, "attempts", Any[])
    isempty(attempts) && return "no completed attempt"
    attempt = last(attempts)
    haskey(attempt, "error") && return "attempt error: " * attempt["error"]
    status = get(attempt, "status", "unknown")
    failures = get(attempt, "physical_failures", nothing)
    categories = failures isa AbstractVector ? unique(get(f, "category", "unknown") for f in failures) : String[]
    details = isempty(categories) ? "physical checks unavailable or within tolerance" :
        "physical failures: " * join(categories, ", ")
    get(attempt, "solver_valid", false) && return "solver accepted iterate, but " * details
    return "solver status $status; $details"
end

function s1_incremental_report(out, rows, planned)
    for row in rows
        row["reason"] = s1_incremental_reason(row)
    end
    groups = Dict{String,Any}()
    for stage in sort(unique(r["tags"]["stage"] for r in rows))
        group = filter(r -> r["tags"]["stage"] == stage, rows)
        groups[stage] = Dict("passed"=>count(r -> get(r, "valid", false), group),
            "failed"=>count(r -> !get(r, "valid", false), group), "attempts"=>length(group))
    end
    payload = Dict("schema"=>"s1-incremental-controls-v1",
        "scope"=>"raw versus cumulative droop/shunt insertion; frozen equations and strict gates",
        "completed"=>length(rows), "planned"=>planned,
        "status"=>length(rows) == planned ? "complete" : "partial",
        "rows"=>rows, "groups"=>groups)
    write(joinpath(out, "summary.json"), JSON.json(payload; pretty=true) * "\n")
    open(joinpath(out, "report.md"), "w") do io
        println(io, "# S1 incremental droop/shunt isolation\n")
        println(io, "This diagnostic starts from the untouched PGLib import and adds controls cumulatively in deterministic frozen-overlay order. `droopN-fixed` adds N nominal droop equalities without design variables; `droopN-free` additionally frees their slopes. `shuntN-free` adds N initially disconnected synthetic banks with no droop attachments. The paired rows contain exactly one droop and one bank. Transformer ratios remain at source values. Every cell uses the frozen epsilon `1e-6`, exact-droop gate `1e-5`, anchor start, and one-reset policy.\n")
        println(io, "Status: **", payload["status"], "** (", length(rows), "/", planned, ").\n")
        println(io, "| Stage | Passed | Failed | Total |\n|---|---:|---:|---:|")
        for stage in sort(collect(keys(groups)))
            g = groups[stage]
            println(io, "| ", stage, " | ", g["passed"], " | ", g["failed"], " | ", g["attempts"], " |")
        end
        println(io, "\n## Every cell\n")
        println(io, "| Network | Load | Solver | Stage | Result | Reason |\n|---:|---:|---|---|---|---|")
        for row in sort(rows; by=r -> (r["tags"]["network"], r["tags"]["load_factor"], r["solver"], r["tags"]["stage"]))
            println(io, "| ", row["tags"]["network"], " | ", row["tags"]["load_factor"],
                " | ", row["solver"], " | ", row["tags"]["stage"], " | ",
                get(row, "valid", false) ? "PASS" : "FAIL", " | ", replace(row["reason"], "|"=>"/"), " |")
        end
        println(io, "\nA failed nonlinear solve is path evidence, not an infeasibility certificate. The raw stage separates source-case difficulty; fixed-droop stages isolate adding controller equations; free-droop stages isolate parameter freedom; zero-droop shunt stages isolate shunt variables.")
    end
    payload
end

"""Run the focused incremental matrix.

The 300-bus stress defaults to 1.03 because the untouched source has a verified
continuation witness there, whereas 1.05 does not. This prevents an unqualified
raw stress point from being blamed on an added controller.
"""
function s1_incremental_controls(out; networks=(118, 300), solvers=(:ipopt, :madnlp),
    load_factors=Dict(118=>(1.0, 1.05), 300=>(1.0, 1.01, 1.02, 1.03)))
    mkpath(out)
    summary_path = joinpath(out, "summary.json")
    rows = if isfile(summary_path)
        parsed = JSON.parsefile(summary_path)
        Dict{String,Any}[Dict{String,Any}(r) for r in get(parsed, "rows", Any[])]
    else
        Dict{String,Any}[]
    end
    completed = Set(r["name"] for r in rows)
    planned = 0
    specifications = Dict{Int,Any}()
    for n in networks
        source = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07",
            "pglib_opf_case$(n)_ieee.m")
        original = load_matpower_case(source; base_frequency=60.0)
        anchor = read_joint_design(joinpath(@__DIR__, "..", "artifacts",
            "s1_public_controls", "public$n-baseline-design.json"))
        validate_joint_design(original, anchor).valid || error("stored source anchor is invalid")
        full, full_policies, _ = s1_incremental_case(original, anchor, source;
            droop_count=length(s1_public_overlay(original, anchor, source; bank_count=n == 118 ? 12 : 32)[1].controls),
            shunt_count=n == 118 ? 12 : 32)
        stages = s1_incremental_stages(length(full.controls), length(full.network.banks);
            extra_droop_counts=n == 300 ? collect(5:7) : Int[])
        specifications[n] = (source, original, anchor, stages)
        planned += length(solvers) * length(load_factors[n]) * length(stages)
    end
    for n in networks
        source, original, anchor, stages = specifications[n]
        for factor in load_factors[n], solver in solvers, stage in stages
            name = "public$n-load$factor-$solver-$(stage.name)-anchor"
            name in completed && continue
            case, available, _ = s1_incremental_case(original, anchor, source;
                droop_count=stage.droops, shunt_count=stage.shunts)
            case = s1_load(case, factor)
            policies = (
                tap_controls=TapControl[],
                shunt_controls=stage.free_shunt ? available.shunt_controls : ShuntControl[],
                droop_controls=stage.free_droop ? available.droop_controls : DroopControl[],
            )
            tags = Dict("study"=>"s1_incremental_controls_v1", "network"=>n,
                "load_factor"=>factor, "start"=>"anchor", "stage"=>stage.name,
                "droop_attachments"=>stage.droops, "synthetic_banks"=>stage.shunts,
                "free_droops"=>length(policies.droop_controls),
                "free_shunts"=>length(policies.shunt_controls), "adjustable_taps"=>0)
            row, _ = s1_run_policy(out, name, case, anchor.opf.state;
                policies, solver, epsilon=1e-6, tags)
            row["reason"] = s1_incremental_reason(row)
            push!(rows, row); push!(completed, name)
            s1_incremental_report(out, rows, planned)
            println("INCREMENTAL ", name, " valid=", row["valid"], " reason=", row["reason"])
            flush(stdout)
        end
    end
    s1_incremental_report(out, rows, planned)
end

if abspath(PROGRAM_FILE) == (@__FILE__)
    isempty(ARGS) && error("usage: julia --project=. examples/s1_incremental_controls.jl OUTPUT [SOLVERS] [NETWORKS]")
    solvers = length(ARGS) >= 2 ? Tuple(Symbol.(split(ARGS[2], ','))) : (:ipopt, :madnlp)
    networks = length(ARGS) >= 3 ? Tuple(parse.(Int, split(ARGS[3], ','))) : (118, 300)
    s1_incremental_controls(abspath(ARGS[1]); solvers, networks)
end
