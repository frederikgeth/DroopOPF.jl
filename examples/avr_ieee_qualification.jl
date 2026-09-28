#= Run a separately labelled, seed-preserving AVR qualification on IEEE fixtures.

The experiment first solves the untouched MATPOWER case with bounded FreeQ,
then selects the available generator with greatest normalized bidirectional Q
headroom. Its AVR setpoint is the independently validated FreeQ voltage at its
own bus. The same witness is supplied to smooth Ipopt, MadNLP, and exact CCOpt.
This is a one-device feasibility/consistency check, not a replacement for the
frozen synthetic-droop matrices and not a claim about actual device classes.

Usage: julia --project=. examples/avr_ieee_qualification.jl [118,300] [ipopt|madnlp|ccopt] [count] [1.0,1.01] [opf|joint|joint_staged|joint_cross_seed]
=#
using DroopOPF
using JSON
using MadNLP

function avr_candidates(case, state, count::Int)
    count > 0 || throw(ArgumentError("count must be positive"))
    bus_indices = DroopOPF._bus_indices(case.network)
    candidates = [(i=i, generator=g, bus=case.network.buses[bus_indices[g.bus_id]],
        setpoint=state.vm[bus_indices[g.bus_id]],
        headroom=min(state.qg[i] - g.q_min, g.q_max - state.qg[i]) / (g.q_max - g.q_min))
        for (i, g) in enumerate(case.generators) if g.available &&
            case.network.buses[bus_indices[g.bus_id]].v_min + 1e-5 <=
                state.vm[bus_indices[g.bus_id]] <=
            case.network.buses[bus_indices[g.bus_id]].v_max - 1e-5]
    sort!(candidates; by=x -> -x.headroom)
    selected = eltype(candidates)[]
    used_buses = Set{Int}()
    for item in candidates
        item.generator.bus_id in used_buses && continue
        push!(selected, item)
        push!(used_buses, item.generator.bus_id)
        length(selected) == count && break
    end
    assignments = [ReactiveControlAssignment(item.generator.id, AVR(item.setpoint),
        RegulatedLocation(:generator_terminal, item.generator.bus_id)) for item in selected]
    return assignments, selected
end

function result_row(case, result, assignments)
    valid = !isnothing(result.state) && validate_equilibrium(case, result;
        reactive_assignments=assignments, power_tolerance=1e-5).valid
    Dict("termination_status" => string(result.termination_status),
        "primal_status" => string(result.primal_status), "valid" => valid,
        "objective" => isfinite(result.objective) ? result.objective : nothing)
end

function scaled_load_case(case, factor::Float64)
    factor > 0 || throw(ArgumentError("load factor must be positive"))
    Case(case.id * "-load$(factor)"; base_power=case.base_power,
        base_frequency=case.base_frequency, network=case.network,
        generators=case.generators, controls=case.controls, attachments=case.attachments,
        loads=[Load(l.id, l.bus_id; p=factor * l.p, q=factor * l.q) for l in case.loads])
end

function qualify(n::Int, solver::Symbol, count::Int, factor::Float64, mode::Symbol)
    source = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07",
        "pglib_opf_case$(n)_ieee.m")
    case = scaled_load_case(load_matpower_case(source; base_frequency=60.0), factor)
    limits = Dict("max_iter" => 1000, "max_cpu_time" => 60.0, "tol" => 1e-8)
    free = solve_opf(case; smooth_epsilon=1e-4, optimizer_attributes=limits)
    !isnothing(free.state) && validate_equilibrium(case, free; power_tolerance=1e-5).valid ||
        return Dict("network" => n, "load_factor" => factor, "freeq" => result_row(case, free, nothing),
            "avr" => nothing, "note" => "FreeQ baseline did not validate")
    assignments, selected = avr_candidates(case, free.state, count)
    isempty(assignments) && return Dict("network" => n, "load_factor" => factor, "freeq" => result_row(case, free, nothing),
        "avr" => nothing, "note" => "No generator-bus FreeQ voltage lies inside its limits by 1e-5")
    result = if solver == :ipopt
        solve_opf(case; reactive_assignments=assignments, initial_state=free.state,
            smooth_epsilon=1e-4, optimizer_attributes=limits)
    elseif solver == :madnlp
        solve_opf(case; reactive_assignments=assignments, initial_state=free.state,
            smooth_epsilon=1e-4, optimizer_factory=MadNLP.Optimizer,
            optimizer_attributes=limits)
    elseif solver == :ccopt
        solve_opf_complementarity(case; reactive_assignments=assignments,
            initial_state=free.state, optimizer_attributes=limits)
    else
        error("solver must be ipopt, madnlp, or ccopt")
    end
    joint = nothing
    if mode == :joint_cross_seed && !isnothing(result.state)
        solver == :ccopt || error("joint_cross_seed requires ccopt")
        branch = first(filter(b -> b.available, case.network.branches))
        lower, upper = .99 * branch.tap_ratio, 1.01 * branch.tap_ratio
        stage_state = free.state
        tap_start = branch.tap_ratio
        seed_stages = Dict{String,Any}[]
        for active in [assignments[1:k] for k in eachindex(assignments)]
            tap = TapControl(branch.id; lower, upper, initial=tap_start, nominal=branch.tap_ratio)
            design = optimize_joint_design(case; tap_controls=[tap],
                reactive_assignments=active, initial_state=stage_state,
                smooth_epsilon=1e-4, optimizer_attributes=limits)
            report = validate_joint_design(case, design; power_tolerance=1e-5)
            push!(seed_stages, Dict("avr_count" => length(active),
                "termination_status" => string(design.opf.termination_status),
                "valid" => report.valid, "tap_ratio" => get(design.taps, branch.id, nothing)))
            report.valid || break
            stage_state = design.opf.state
            tap_start = design.taps[branch.id]
        end
        exact_stage = nothing
        if length(seed_stages) == length(assignments) && last(seed_stages)["valid"]
            tap = TapControl(branch.id; lower, upper, initial=tap_start, nominal=branch.tap_ratio)
            design = optimize_joint_design(case; tap_controls=[tap],
                reactive_assignments=assignments, initial_state=stage_state,
                encoding=:complementarity, optimizer_attributes=limits)
            report = validate_joint_design(case, design; power_tolerance=1e-5)
            exact_stage = Dict("avr_count" => length(assignments),
                "termination_status" => string(design.opf.termination_status),
                "valid" => report.valid, "tap_ratio" => get(design.taps, branch.id, nothing))
            exact_stage["complementarity_residual_max"] = design.complementarity_residual_max
        end
        joint = Dict("tap_branch_id" => branch.id, "tap_bounds" => [lower, upper],
            "cross_seeded" => true, "seed_backend" => "ipopt",
            "seed_stages" => seed_stages, "exact_stage" => exact_stage,
            "valid" => !isnothing(exact_stage) && exact_stage["valid"])
    elseif mode in (:joint, :joint_staged) && !isnothing(result.state)
        branch = first(filter(b -> b.available, case.network.branches))
        lower, upper = .99 * branch.tap_ratio, 1.01 * branch.tap_ratio
        stage_assignments = mode == :joint ? [assignments] :
            [assignments[1:k] for k in eachindex(assignments)]
        stage_state = mode == :joint ? result.state : free.state
        tap_start = branch.tap_ratio
        stages = Dict{String,Any}[]
        for active in stage_assignments
            tap = TapControl(branch.id; lower, upper, initial=tap_start, nominal=branch.tap_ratio)
            design = if solver == :ipopt
                optimize_joint_design(case; tap_controls=[tap],
                    reactive_assignments=active, initial_state=stage_state,
                    smooth_epsilon=1e-4, optimizer_attributes=limits)
            elseif solver == :madnlp
                optimize_joint_design(case; tap_controls=[tap],
                    reactive_assignments=active, initial_state=stage_state,
                    smooth_epsilon=1e-4, optimizer_factory=MadNLP.Optimizer,
                    optimizer_attributes=limits)
            else
                optimize_joint_design(case; tap_controls=[tap],
                    reactive_assignments=active, initial_state=stage_state,
                    encoding=:complementarity, optimizer_attributes=limits)
            end
            report = validate_joint_design(case, design; power_tolerance=1e-5)
            push!(stages, Dict("avr_count" => length(active),
                "termination_status" => string(design.opf.termination_status),
                "valid" => report.valid, "tap_ratio" => get(design.taps, branch.id, nothing),
                "complementarity_residual_max" => design.complementarity_residual_max))
            report.valid || break
            stage_state = design.opf.state
            tap_start = design.taps[branch.id]
        end
        joint = Dict("tap_branch_id" => branch.id, "tap_bounds" => [lower, upper],
            "staged" => mode == :joint_staged, "stages" => stages,
            "valid" => !isempty(stages) && last(stages)["valid"])
    elseif mode != :opf
        error("mode must be opf, joint, joint_staged, or joint_cross_seed")
    end
    Dict("network" => n, "load_factor" => factor, "freeq" => result_row(case, free, nothing),
        "avr" => Dict("candidate_count" => length(selected),
            "selection_rule" => "highest normalized bidirectional Q headroom; one generator per bus; raw voltage at least 1e-5 inside limits",
            "candidates" => [Dict("generator_id" => item.generator.id,
                "bus_id" => item.generator.bus_id, "setpoint" => item.setpoint,
                "normalized_bidirectional_q_headroom" => item.headroom,
                "assignment" => DroopOPF._json_data(assignment))
                for (item, assignment) in zip(selected, assignments)],
            string(solver) => result_row(case, result, assignments), "joint" => joint),
        "note" => "predeclared highest-headroom terminal AVR set; separate qualification lane")
end

networks = isempty(ARGS) ? (118, 300) : Tuple(parse.(Int, split(first(ARGS), ',')))
all(n -> n in (118, 300), networks) || error("networks must be 118 and/or 300")
solver = length(ARGS) < 2 ? :ipopt : Symbol(ARGS[2])
count = length(ARGS) < 3 ? 3 : parse(Int, ARGS[3])
factors = length(ARGS) < 4 ? (1.0,) : Tuple(parse.(Float64, split(ARGS[4], ',')))
mode = length(ARGS) < 5 ? :opf : Symbol(ARGS[5])
rows = [qualify(n, solver, count, factor, mode) for n in networks for factor in factors]
out = joinpath(@__DIR__, "..", "artifacts", "avr_ieee_qualification")
mkpath(out)
label = join(string.(networks), "_")
load_label = join(string.(factors), "_")
path = joinpath(out, "summary_$(label)_$(solver)_k$(count)_load$(load_label)_$(mode).json")
write(path, JSON.json(rows; pretty=true) * "\n")
println(path)
for row in rows
    println("IEEE-", row["network"], ": ", row["note"])
end
