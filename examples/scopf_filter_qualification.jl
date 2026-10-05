using DroopOPF
using JSON
using Statistics

# Deterministic, declared-before-evaluation split. No operating point from the
# held-out partition is used to select guard settings.
function qualification_inputs(split::Symbol)
    offset = split == :discovery ? 0 : split == :heldout ? 1 : error("unknown split")
    specs = [(n=n, chord=chord, stress=stress) for n in (3+offset,5+offset)
        for chord in (false,true) for stress in (:light,:reactive,:loaded)]
    map(enumerate(specs)) do (index,spec)
        n,chord,stress = spec.n,spec.chord,spec.stress
        p = stress == :loaded ? 0.9+0.1offset : 0.35+0.05offset
        q = stress == :reactive ? 0.65+0.05offset : 0.12+0.03offset
        cap = stress == :reactive ? (q+0.09)/2 : 0.8
        pairs = [(i,mod1(i+1,n)) for i in 1:n]
        chord && push!(pairs,(1,div(n,2)+1))
        branches = [Branch(i,f,t; resistance=0.012+0.003offset,
            reactance=0.13+0.015offset, thermal_limit=stress == :loaded ? 0.65 : 1.5,
            kind=i == length(pairs) ? :transformer : :line,
            tap_ratio=i == length(pairs) ? (chord ? 1.02 : 0.99) : 1.0)
            for (i,(f,t)) in enumerate(pairs)]
        generator_buses = (1,div(n,2)+1)
        generators = [Generator(i,b; p_min=0.0,p_max=0.85,q_min=-0.5,q_max=cap,
            initial_p=p/2,initial_q=q/2) for (i,b) in enumerate(generator_buses)]
        load_buses = [b for b in 1:n if !(b in generator_buses)]
        case = Case("$(split)-$index-$n-$(stress)-$(chord)";
            base_power=100.0,base_frequency=50.0,
            network=ACNetwork([Bus(i;reference=i==1) for i in 1:n],branches),
            loads=[Load(i,b;p=p/length(load_buses),q=q/length(load_buses))
                for (i,b) in enumerate(load_buses)],generators,
            controls=VoltVarDroop[],attachments=GeneratorControlAttachment[])
        (; case, spec, split)
    end
end

function qualification_base(case)
    assignments = [ReactiveControlAssignment(g.id,AVR(1.0),RegulatedLocation(:bus,g.bus_id))
        for g in case.generators]
    solve_opf(case;reactive_assignments=assignments,
        optimizer_attributes=Dict("max_iter"=>400,"max_cpu_time"=>15.0))
end

function qualification_run(output; enhanced=false, splits=(:discovery,), repeats=3)
    mkpath(output)
    rows = []
    policy = (;loading_threshold=0.8,voltage_guard=0.02)
    # First-call timing includes JIT compilation and is never called pure compile time.
    for split in splits, input in qualification_inputs(split)
        case = input.case
        base_time = @elapsed base = qualification_base(case)
        base_valid = !isnothing(base.state) && equilibrium_report(case,base).valid
        if !base_valid
            push!(rows,(;id=case.id,split,base_valid,base_time,status=base.termination_status))
            continue
        end
        extra = enhanced ? (;reactive_guard=0.1,ac_risk_guard=true) : (;reactive_guard=0.0,ac_risk_guard=false)
        measured = @timed validate_contingency_filter(case,base.state;policy...,extra...,
            optimizer_attributes=Dict("max_iter"=>400,"max_cpu_time"=>15.0))
        comparison = measured.value
        first_call = (seconds=measured.time,
            compile_seconds=hasproperty(measured,:compile_time) ? measured.compile_time : nothing)
        timings = []
        # Alternate order on repetitions to reduce systematic warm-up bias.
        for repeat in 1:repeats, screening in (isodd(repeat) ? (false,true) : (true,false))
            phases = Dict{Symbol,Float64}()
            elapsed = @elapsed pipeline = assess_contingency_pipeline(case,base.state;
                policy...,extra...,screening_enabled=screening,_phase_timings=phases,
                optimizer_attributes=Dict("max_iter"=>400,"max_cpu_time"=>15.0))
            report_time = @elapsed begin
                markdown_report(pipeline)
                JSON.json(DroopOPF._json_data(pipeline))
            end
            push!(timings,(;repeat,screening,elapsed,phases,report_time,
                screened=pipeline.checks.screened_count))
        end
        row = (;id=case.id,split,base_valid,base_time,policy,extra,enhanced,first_call,
            families=comparison.families,timings)
        push!(rows,row)
        directory=joinpath(output,case.id)
        mkpath(directory)
        DroopOPF._write_scopf_json(joinpath(directory,"comparison.json"),"DroopOPF.FilterQualification",comparison)
        DroopOPF._write_scopf_json(joinpath(output,"results.json"),"DroopOPF.FilterBenchmark",rows)
        println("$(case.id): screened=$(sum(r.screened for r in comparison.families)), misses=$(sum(r.screened_unresolved for r in comparison.families))")
        flush(stdout)
    end
    DroopOPF._write_scopf_json(joinpath(output,"results.json"),"DroopOPF.FilterBenchmark",rows)
    rows
end

function qualification_summary(root)
    rows = Dict(policy=>JSON.parsefile(joinpath(root,policy,"results.json"))["data"]
        for policy in ("baseline","enhanced"))
    lines = ["# Held-out filtering qualification and performance", "",
        "## Protocol and interpretation", "",
        "Twelve discovery networks (3/5 buses) and twelve predeclared held-out networks (4/6 buses), with ring/chord topology, line/transformer identity, tap ratios, load level, reactive demand, and generation location/capability varied. Base points are selected with AVR targets; post-outage Q is free within declared bounds. The partitions and operating inputs were defined before evaluating the held-out results.", "",
        "Frozen legacy policy: loading threshold 0.8, voltage margin 0.02 pu. Enhanced policy adds a 0.1 aggregate bidirectional reactive-reserve fraction guard and impedance/apparent-flow redistribution guards. Settings were frozen after the discovery failure and before held-out evaluation; no held-out threshold tuning was performed. Generators always receive exact AC evaluation. These guards are conservative heuristics, NOT solved AC states or security certificates.", "",
        "Unresolved includes physical failure, solver rejection, and errors—not proof of infeasibility. Zero misses on this finite set is not a deployment guarantee. Per-network comparison.json files retain complete inputs, base states, thresholds, exact states and validation/ranking evidence.", "",
        "## Coverage and misses by device family", "",
        "| Policy | Partition | Family | Outages | Screened | Unresolved | Missed unresolved |",
        "|---|---|---|---:|---:|---:|---:|"]
    plotrows = Vector{Any}[]
    for policy in ("baseline","enhanced"), split in ("discovery","heldout"), kind in ("line","transformer","generator")
        selected = [r for r in rows[policy] if r["split"]==split && r["base_valid"]]
        family = [f for r in selected for f in r["families"] if f["device_kind"]==kind]
        counts = [sum(f[k] for f in family;init=0) for k in
            ("total","screened","unresolved","screened_unresolved")]
        push!(lines,"| $policy | $split | $kind | $(join(counts," | ")) |")
        push!(plotrows,Any[policy,split,kind,counts...])
    end
    DroopOPF._scopf_svg_table(joinpath(root,"coverage.svg"),
        "Frozen policy vs enhanced guards — exhaustive AC reference",
        "Misses are screened unresolved outcomes. Screening is not a certificate; generator contingencies are always evaluated.",
        ["Policy","Partition","Family","Outages","Screened","Unresolved","Misses"],plotrows;
        cell_widths=[140,140,150,140,140,160,250])
    push!(lines,"", "![Coverage and false screens](coverage.svg)", "",
        "## Warm runtime and phase attribution", "",
        "Three paired repetitions per input, alternating screened/exhaustive execution order. Repetition 1 is excluded from warm statistics. Final policy runs were executed sequentially, without another Julia workload launched by this task. Host scheduling, garbage collection and system load remain possible noise sources; these are small-network measurements, not scale forecasts.", "",
        "Each row sums per-input median seconds over repetitions 2–3. Speedup is exhaustive total / screened total for that policy and partition. End-to-end assessment includes validation and routing; report serialization is measured separately in memory (Markdown + JSON), excludes disk I/O and plotting. Preparation/build includes study construction and base checks; optimize/extract includes solver and result extraction. Independent validation/ranking follows extraction. Remaining overhead is outside those measured phases.", "",
        "| Policy | Partition | Mode | Total s | Filter s | Prepare/build s | Optimize/extract s | Validate/rank s | Report s |",
        "|---|---|---|---:|---:|---:|---:|---:|---:|")
    perfrows=Vector{Any}[]
    speedups=String[]
    for policy in ("baseline","enhanced"), split in ("discovery","heldout")
        selected=[r for r in rows[policy] if r["split"]==split && r["base_valid"]]
        totals=Dict{Bool,Float64}()
        for screened in (false,true)
            sums=zeros(6)
            for r in selected
                samples=[t for t in r["timings"] if t["repeat"]>1 && t["screening"]==screened]
                sums[1]+=median([t["elapsed"] for t in samples])
                for (i,key) in enumerate(("filter","prepare_build","optimize_extract","validate_rank"))
                    sums[i+1]+=median([get(t["phases"],key,0.0) for t in samples])
                end
                sums[6]+=median([t["report_time"] for t in samples])
            end
            totals[screened]=sums[1]
            mode=screened ? "screened" : "exhaustive"
            values=string.(round.(sums;digits=5))
            push!(lines,"| $policy | $split | $mode | $(join(values," | ")) |")
            push!(perfrows,Any[policy,split,mode,values...])
        end
        push!(speedups,"- Warm assessment speedup ($policy, $split): **$(round(totals[false]/totals[true];digits=2))×**.")
    end
    DroopOPF._scopf_svg_table(joinpath(root,"timing.svg"),
        "Warm assessment phases — sum of per-input medians (seconds)",
        "First repetition excluded; report serialization is separate. Timing ratios do not imply screening safety.",
        ["Policy","Partition","Mode","Total","Filter","Build/prep","Solve/extract","Validate/rank","Report"],
        perfrows;cell_widths=[120,120,120,120,120,130,130,130,180])
    push!(lines,"")
    append!(lines,speedups)
    push!(lines,"", "![Timing phases](timing.svg)", "", "## Cold-call and exclusions", "")
    for policy in ("baseline","enhanced")
        first_valid=first(filter(r->r["base_valid"],rows[policy]))
        cold=first_valid["first_call"]
        invalid=[r["id"] for r in rows[policy] if !r["base_valid"]]
        push!(lines,"- $policy: first comparison $(round(cold["seconds"];digits=3)) s; reported JIT compilation $(cold["compile_seconds"]) s; invalid bases $(length(invalid)): $(join(invalid,", ")).")
    end
    push!(lines,"", "First-comparison wall time includes JIT, exact evaluation and validation. The runtime-provided compile counter is diagnostic (not a disjoint phase); process startup, package loading/precompilation and base construction are excluded. Every input's base-construction and first-comparison time is retained in results.json.", "",
        "## Assessment", "",
        "The discovery misses arose in the reactive-stressed three-bus ring: two screened branch outages failed AC balance. The reserve guard escalates these. All held-out branch outages were accepted by the exhaustive reference; therefore branch-failure recall cannot be estimated from this held-out set. Its unresolved outcomes were generator outages, which always receive exact evaluation. This demonstrates non-regression, not superiority on unseen branch failures. Enhanced guards deliberately trade screening savings for caution; review family counts and timing together. Additional independently designed stress families and S1/S2 scale qualification remain necessary.", "")
    write(joinpath(root,"evaluation.md"),join(lines,"\n"))
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    if get(ARGS,2,"") == "summary"
        qualification_summary(ARGS[1])
    else
        qualification_run(ARGS[1];enhanced=get(ARGS,2,"baseline")=="enhanced",
            splits=get(ARGS,3,"discovery")=="both" ? (:discovery,:heldout) : (:discovery,))
    end
end
