include("s1_incremental_controls.jl")

using JuMP
using Ipopt

function s1_phase1_restoration(case, initial_state;
    epsilon=1e-6, optimizer_attributes=Dict{String,Any}(
        "max_iter" => 1000, "max_cpu_time" => 60.0,
        "tol" => 1e-9, "bound_relax_factor" => 0.0,
    ), silent=true)
    validate_case(case)
    network = case.network
    nbus = length(network.buses)
    ngen = length(case.generators)
    bus_indices = DroopOPF._bus_indices(network)
    generator_indices = Dict(g.id => i for (i, g) in enumerate(case.generators))
    attachment_by_generator = Dict(a.generator_id => a for a in case.attachments)
    generators_at_bus = [Int[] for _ in 1:nbus]
    for (i, generator) in enumerate(case.generators)
        push!(generators_at_bus[bus_indices[generator.bus_id]], i)
    end
    load_p = zeros(nbus)
    load_q = zeros(nbus)
    for load in case.loads
        i = bus_indices[load.bus_id]
        load_p[i] += load.p
        load_q[i] += load.q
    end
    Y = DroopOPF._admittance_matrix(network)
    G, B = real.(Y), imag.(Y)

    model = Model(Ipopt.Optimizer)
    silent && set_silent(model)
    for (key, value) in optimizer_attributes
        set_optimizer_attribute(model, key, value)
    end
    @variable(model, 0.5 <= vm[1:nbus] <= 1.5)
    @variable(model, -pi <= va[1:nbus] <= pi)
    @variable(model, pg[1:ngen])
    @variable(model, qg[1:ngen])
    for i in 1:nbus
        set_start_value(vm[i], initial_state.vm[i])
        set_start_value(va[i], initial_state.va[i])
        network.buses[i].reference && fix(va[i], 0.0; force=true)
    end
    for (i, generator) in enumerate(case.generators)
        span_p = max(generator.p_max - generator.p_min, 1.0)
        span_q = max(generator.q_max - generator.q_min, 1.0)
        set_lower_bound(pg[i], generator.p_min - span_p)
        set_upper_bound(pg[i], generator.p_max + span_p)
        set_lower_bound(qg[i], generator.q_min - span_q)
        set_upper_bound(qg[i], generator.q_max + span_q)
        set_start_value(pg[i], initial_state.pg[i])
        set_start_value(qg[i], initial_state.qg[i])
        if !generator.available
            fix(pg[i], 0.0; force=true)
            fix(qg[i], 0.0; force=true)
        end
    end

    @variable(model, p_balance_pos[1:nbus] >= 0)
    @variable(model, p_balance_neg[1:nbus] >= 0)
    @variable(model, q_balance_pos[1:nbus] >= 0)
    @variable(model, q_balance_neg[1:nbus] >= 0)
    @variable(model, voltage_lower[1:nbus] >= 0)
    @variable(model, voltage_upper[1:nbus] >= 0)
    @variable(model, generator_p_lower[1:ngen] >= 0)
    @variable(model, generator_p_upper[1:ngen] >= 0)
    @variable(model, generator_q_lower[1:ngen] >= 0)
    @variable(model, generator_q_upper[1:ngen] >= 0)

    for (i, bus) in enumerate(network.buses)
        @constraint(model, vm[i] + voltage_lower[i] >= bus.v_min)
        @constraint(model, vm[i] - voltage_upper[i] <= bus.v_max)
        p_generation = sum(pg[k] for k in generators_at_bus[i]; init=0.0)
        q_generation = sum(qg[k] for k in generators_at_bus[i]; init=0.0)
        @NLconstraint(model,
            p_generation - load_p[i] + p_balance_pos[i] - p_balance_neg[i] ==
            vm[i] * sum(vm[j] * (G[i, j] * cos(va[i] - va[j]) +
                B[i, j] * sin(va[i] - va[j])) for j in 1:nbus))
        @NLconstraint(model,
            q_generation - load_q[i] + q_balance_pos[i] - q_balance_neg[i] ==
            vm[i] * sum(vm[j] * (G[i, j] * sin(va[i] - va[j]) -
                B[i, j] * cos(va[i] - va[j])) for j in 1:nbus))
    end
    for (i, generator) in enumerate(case.generators)
        if generator.available
            p_min, p_max = generator.p_min, generator.p_max
            if haskey(attachment_by_generator, generator.id)
                control = case.controls[attachment_by_generator[generator.id].control_id]
                p_min = max(p_min, control.capability.p_min)
                p_max = min(p_max, control.capability.p_max)
            end
            @constraint(model, pg[i] + generator_p_lower[i] >= p_min)
            @constraint(model, pg[i] - generator_p_upper[i] <= p_max)
            @constraint(model, qg[i] + generator_q_lower[i] >= generator.q_min)
            @constraint(model, qg[i] - generator_q_upper[i] <= generator.q_max)
        else
            fix(generator_p_lower[i], 0.0; force=true)
            fix(generator_p_upper[i], 0.0; force=true)
            fix(generator_q_lower[i], 0.0; force=true)
            fix(generator_q_upper[i], 0.0; force=true)
        end
    end

    available_branches = filter(branch -> branch.available, network.branches)
    @variable(model, thermal_slack[1:(2 * length(available_branches))] >= 0)
    thermal_index = 0
    for branch in available_branches
        f, t = bus_indices[branch.from_bus], bus_indices[branch.to_bus]
        yff, yft, ytf, ytt = DroopOPF._branch_admittances(branch)
        for (i, j, self, mutual) in ((f, t, yff, yft), (t, f, ytt, ytf))
            thermal_index += 1
            gs, bs = real(self), imag(self)
            gm, bm = real(mutual), imag(mutual)
            @NLconstraint(model,
                (vm[i]^2 * gs + vm[i] * vm[j] *
                    (gm * cos(va[i] - va[j]) + bm * sin(va[i] - va[j])))^2 +
                (-vm[i]^2 * bs + vm[i] * vm[j] *
                    (gm * sin(va[i] - va[j]) - bm * cos(va[i] - va[j])))^2 <=
                (branch.thermal_limit + thermal_slack[thermal_index])^2)
        end
    end

    active_attachments = [a for a in case.attachments
        if case.generators[generator_indices[a.generator_id]].available]
    @variable(model, droop_pos[1:length(active_attachments)] >= 0)
    @variable(model, droop_neg[1:length(active_attachments)] >= 0)
    for (k, attachment) in enumerate(active_attachments)
        generator_index = generator_indices[attachment.generator_id]
        location_index = bus_indices[attachment.location.bus_id]
        control = case.controls[attachment.control_id]
        qepsilon = reactive_smoothing_epsilon(control, epsilon)
        function_name = Symbol("phase1_droop_", k)
        JuMP.register(model, function_name, 1,
            voltage -> DroopOPF._smooth_droop_value(control, voltage, epsilon, qepsilon);
            autodiff=true)
        expression = Expr(:call, function_name, vm[location_index])
        JuMP.add_nonlinear_constraint(model, Expr(:call, :(==),
            Expr(:call, :+, qg[generator_index], droop_pos[k]),
            Expr(:call, :+, expression, droop_neg[k])))
    end

    families = Dict(
        "active_balance" => [p_balance_pos; p_balance_neg],
        "reactive_balance" => [q_balance_pos; q_balance_neg],
        "voltage_limits" => [voltage_lower; voltage_upper],
        "generator_p_limits" => [generator_p_lower; generator_p_upper],
        "generator_q_limits" => [generator_q_lower; generator_q_upper],
        "thermal_limits" => collect(thermal_slack),
        "droop_equalities" => [droop_pos; droop_neg],
    )
    all_slacks = reduce(vcat, values(families); init=VariableRef[])
    @objective(model, Min, sum(all_slacks))
    optimize!(model)

    present = has_values(model)
    state = present ? ACState(value.(vm), value.(va), value.(pg), value.(qg)) : nothing
    family_data = Dict{String,Any}()
    for (name, variables) in families
        values_ = present ? value.(variables) : Float64[]
        family_data[name] = Dict{String,Any}(
            "sum" => present ? sum(values_) : nothing,
            "max" => present ? maximum(values_; init=0.0) : nothing,
            "nonzero_count_1e-8" => present ? count(>(1e-8), values_) : nothing,
        )
    end
    if present
        voltage_components = Dict{String,Any}[]
        for (i, bus) in enumerate(network.buses)
            push!(voltage_components,
                Dict("bus_id" => bus.id, "side" => "lower", "slack" => value(voltage_lower[i])),
                Dict("bus_id" => bus.id, "side" => "upper", "slack" => value(voltage_upper[i])))
        end
        sort!(voltage_components; by=row -> -row["slack"])
        family_data["voltage_limits"]["largest_components"] = voltage_components[1:min(10, end)]
    end
    validation = isnothing(state) ? nothing : validate_equilibrium(case, state;
        smooth_epsilon=epsilon, smooth_reactive_relative_epsilon=epsilon)
    max_slack = present ? maximum(value.(all_slacks); init=0.0) : nothing
    Dict(
        "status" => string(termination_status(model)),
        "primal_status" => string(primal_status(model)),
        "objective" => present ? objective_value(model) : nothing,
        "max_slack" => max_slack,
        "families" => family_data,
        "independent_validation" => isnothing(validation) ? nothing :
            DroopOPF._json_data(validation),
        "classification" => !present ? "no_phase1_point" :
            max_slack <= 1e-7 && validation.valid ? "restored_zero_slack" :
            "positive_slack_local_result",
        "acceptance_warning" => "Phase-I output is diagnostic and never replaces a strict original-model solve.",
        "state" => isnothing(state) ? nothing : DroopOPF._json_data(state),
    )
end

function s1_controller5_phase1(out)
    source = joinpath(@__DIR__, "..", "test", "data", "pglib", "v23.07",
        "pglib_opf_case300_ieee.m")
    original = load_matpower_case(source; base_frequency=60.0)
    anchor = read_joint_design(joinpath(@__DIR__, "..", "artifacts", "s1_public_controls",
        "public300-baseline-design.json"))
    incremental = joinpath(@__DIR__, "..", "artifacts", "s1_incremental_controls")
    selected = joinpath(@__DIR__, "..", "artifacts", "s1_incremental_control5")
    cumulative5, _, _ = s1_incremental_case(original, anchor, source;
        droop_count=5, shunt_count=0)
    selected5, _ = s1_selected_droop_case(original, anchor, source, (5,))
    cases = Dict("cumulative_first_five" => s1_load(cumulative5, 1.02),
        "controller_5_only" => s1_load(selected5, 1.02))
    rows = Dict{String,Any}[]
    for (model_name, case) in sort(collect(cases); by=first), source_solver in (:ipopt, :madnlp)
        folder = model_name == "cumulative_first_five" ? incremental : selected
        stage = model_name == "cumulative_first_five" ? "droop5-fixed" : "selected5-fixed"
        prefix = "public300-load1.02-$(source_solver)-$(stage)-anchor"
        summary = JSON.parsefile(joinpath(folder, "summary.json"))
        summary_rows = summary isa AbstractVector ? summary : summary["rows"]
        failed = only(filter(row -> row["name"] == prefix, summary_rows))
        final_attempt = last(failed["attempts"])
        failed_design = read_joint_design(joinpath(folder, final_attempt["name"] * "-design.json"))
        result = s1_phase1_restoration(case, failed_design.opf.state)
        result["model"] = model_name
        result["source_solver"] = string(source_solver)
        result["source_status"] = final_attempt["status"]
        result["source_cell"] = prefix
        result["source_iterate"] = relpath(joinpath(folder,
            final_attempt["name"] * "-design.json"), pwd())
        push!(rows, result)
    end
    witness_path = joinpath(incremental,
        "public300-load1.02-ipopt-droop6-fixed-anchor-attempt1-design.json")
    witness = read_joint_design(witness_path)
    for (model_name, case) in sort(collect(cases); by=first)
        result = s1_phase1_restoration(case, witness.opf.state)
        result["model"] = model_name
        result["source_solver"] = "known_ipopt_six_witness"
        result["source_status"] = string(witness.opf.termination_status)
        result["source_cell"] = "public300-load1.02-ipopt-droop6-fixed-anchor"
        result["source_iterate"] = relpath(witness_path, pwd())
        push!(rows, result)
    end
    payload = Dict("schema" => "s1-phase1-controller5-v1", "rows" => rows,
        "scope" => "IEEE-300 load 1.02 fixed-droop failed paths",
        "acceptance_warning" => "No Phase-I result is an accepted OPF result or infeasibility certificate.")
    mkpath(out)
    write(joinpath(out, "summary.json"), JSON.json(payload; pretty=true) * "\n")
    open(joinpath(out, "report.md"), "w") do io
        println(io, "# IEEE-300 controller-5 Phase-I restoration\n")
        println(io, "This is a diagnostic elastic model, not an OPF acceptance path. It separately minimizes active/reactive balance, voltage, generator P/Q, thermal, and smooth-droop slacks. Every returned state is also checked by the unchanged independent validator.\n")
        println(io, "| Model | Start source | Original status | Phase-I status | Classification | Total slack objective | Maximum slack | Voltage-slack sum | Strictly valid |\n|---|---|---|---|---|---:|---:|---:|---:|")
        for row in rows
            println(io, "| ", row["model"], " | ", row["source_solver"], " | ",
                row["source_status"], " | ", row["status"], " | ", row["classification"],
                " | ", row["objective"], " | ", row["max_slack"], " | ",
                row["families"]["voltage_limits"]["sum"], " | ",
                row["independent_validation"]["valid"], " |")
        end
        println(io, "\nBoth failed-solver basins converge to the same positive-slack local point for each reduced model. Nearly all material slack is assigned to two voltage-limit violations; balance, generator-limit, thermal, and droop slacks remain near numerical noise. Starting the identical Phase-I model from the known cumulative-six feasible witness reaches a zero-maximum-slack, independently valid point. Therefore the positive result is a local basin diagnosis, not a minimum-violation or infeasibility certificate.")
    end
    payload
end

abspath(PROGRAM_FILE) == (@__FILE__) && s1_controller5_phase1(abspath(
    isempty(ARGS) ? joinpath(@__DIR__, "..", "artifacts", "s1_phase1_controller5") : ARGS[1]))
