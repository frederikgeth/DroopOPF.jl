function _scopf_svg_table(path, title, description, headers, rows;
    cell_widths=fill(150, length(headers)), row_height=36)
    width = sum(cell_widths) + 40
    height = 100 + row_height * (length(rows) + 1)
    x_positions = cumsum([20; cell_widths[1:end-1]])
    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<title>$(_svg_escape(title))</title><desc>$(_svg_escape(description))</desc>")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
        println(io, "<text x=\"20\" y=\"30\" font-family=\"sans-serif\" font-size=\"20\" font-weight=\"600\">$(_svg_escape(title))</text>")
        table_top = 58
        for (j, header) in enumerate(headers)
            x = x_positions[j]
            println(io, "<rect x=\"$x\" y=\"$table_top\" width=\"$(cell_widths[j])\" height=\"$row_height\" fill=\"#e5e7eb\" stroke=\"#9ca3af\"/>")
            println(io, "<text x=\"$(x+8)\" y=\"$(table_top+23)\" font-family=\"sans-serif\" font-size=\"12\" font-weight=\"600\">$(_svg_escape(header))</text>")
        end
        for (i, row) in enumerate(rows)
            y = table_top + i * row_height
            for (j, cell) in enumerate(row)
                value, color = cell isa Tuple ? cell : (string(cell), isodd(i) ? "#f9fafb" : "#ffffff")
                x = x_positions[j]
                println(io, "<rect x=\"$x\" y=\"$y\" width=\"$(cell_widths[j])\" height=\"$row_height\" fill=\"$color\" stroke=\"#d1d5db\"/>")
                println(io, "<text x=\"$(x+8)\" y=\"$(y+23)\" font-family=\"sans-serif\" font-size=\"11\">$(_svg_escape(string(value)))</text>")
            end
        end
        println(io, "</svg>")
    end
    path
end

function _outage_label(case::Case, contingency::Contingency)
    branch_by_id = Dict(branch.id => branch for branch in case.network.branches)
    parts = String[]
    for id in contingency.branch_ids
        branch = branch_by_id[id]
        push!(parts, "$(branch.kind) $id ($(branch.from_bus)-$(branch.to_bus))")
    end
    append!(parts, ["generator $id" for id in contingency.generator_ids])
    join(parts, ", ")
end

"""Plot declared outage, response, and equipment-policy inputs by scenario."""
function write_scopf_input_plot(path::AbstractString, study::Study;
    title::AbstractString="SCOPF declared inputs by scenario")
    study = _validated_study(study)
    ids, cases = _scopf_scenario_cases(study)
    rows = Vector{Any}[]
    for (i, (id, case)) in enumerate(zip(ids, cases))
        outage = id == :base ? "none" : _outage_label(study.case, study.contingencies[i-1])
        response = if id == :base
            "base dispatch"
        elseif study.mode == :preventive
            participants = [string(g.id) for g in case.generators
                if g.available && get(study.participation, g.id, 0.0) > 0]
            "preventive: G" * join(participants, ",G")
        else
            movable = ["G$id≤$(_svg_number(limit))" for (id, limit) in
                sort(collect(study.redispatch_limits); by=first)]
            "corrective: " * (isempty(movable) ? "frozen" : join(movable, ", "))
        end
        taps = isempty(study.tap_controls) ? "none" :
            "$(study.control_policy.taps): " * join(string.(getfield.(study.tap_controls, :branch_id)), ",")
        shunts = isempty(study.shunt_controls) ? "none" :
            "$(study.control_policy.shunts): " * join(string.(getfield.(study.shunt_controls, :bank_id)), ",")
        push!(rows, Any[string(id), outage, response, taps, shunts])
    end
    _scopf_svg_table(path, title,
        "Scenario-level outage, active response, and equipment timing inputs.",
        ["Scenario", "Outage", "Active response", "Tap policy", "Shunt policy"], rows;
        cell_widths=[120, 270, 260, 180, 180])
end

_margin_color(value) = !isfinite(value) ? "#e5e7eb" :
    value < -1e-6 ? "#fecaca" : value < 0.01 ? "#fef3c7" : "#d1fae5"

"""Plot independently recomputed operating margins for every SCOPF scenario."""
function write_scopf_margin_plot(path::AbstractString, study::Study,
    result::SCOPFResult; title::AbstractString="SCOPF independent operating margins")
    report = equilibrium_report(study, result)
    headers = ["Scenario", "V min", "V max", "Thermal", "P min", "P max",
        "Q min", "Q max"]
    rows = Vector{Any}[]
    for id in report.scenario_ids
        if !haskey(report.scenarios, id)
            push!(rows, Any[string(id); fill(("missing", "#fecaca"), 7)])
            continue
        end
        validation = report.scenarios[id]
        values = (validation.voltage_min_margin, validation.voltage_max_margin,
            validation.branch_thermal_min_margin, validation.generator_p_min_margin,
            validation.generator_p_max_margin, validation.generator_q_min_margin,
            validation.generator_q_max_margin)
        push!(rows, Any[string(id); [(_svg_number(value), _margin_color(value))
            for value in values]])
    end
    _scopf_svg_table(path, title,
        "Green margins exceed 0.01 pu, amber margins are near a limit, and red margins violate a limit.",
        headers, rows; cell_widths=[140; fill(105, 7)])
end

"""Plot maximum base-to-scenario state changes on a logarithmic scale."""
function write_scopf_response_delta_plot(path::AbstractString, study::Study,
    result::SCOPFResult; title::AbstractString="SCOPF base-to-scenario response deltas")
    ids, _, states = _scopf_plot_data(study, result)
    base = first(states)
    scenario_ids = ids[2:end]
    metrics = [
        ("max |ΔV|", [maximum(abs.(state.vm .- base.vm); init=0.0) for state in states[2:end]], "#2563eb"),
        ("max |Δθ|", [maximum(abs.(state.va .- base.va); init=0.0) for state in states[2:end]], "#7c3aed"),
        ("max |ΔP|", [maximum(abs.(state.pg .- base.pg); init=0.0) for state in states[2:end]], "#d97706"),
        ("max |ΔQ|", [maximum(abs.(state.qg .- base.qg); init=0.0) for state in states[2:end]], "#059669"),
    ]
    width, height = 1180, 620
    left, top, plot_width, plot_height = 90, 58, 850, 450
    lower = -8.0
    upper = max(0.0, maximum((log10(max(value, 1e-8)) for (_, values, _) in metrics
        for value in values); init=0.0) + 0.25)
    yscale(value) = top + plot_height * (upper - value) / (upper - lower)
    groups = max(length(scenario_ids), 1)
    group_width = plot_width / groups
    bar_width = 0.72group_width / length(metrics)
    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<title>$(_svg_escape(title))</title><desc>Maximum absolute scenario changes from the saved base state, plotted on a log10 scale.</desc>")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/><text x=\"$left\" y=\"30\" font-family=\"sans-serif\" font-size=\"20\" font-weight=\"600\">$(_svg_escape(title))</text>")
        for tick in lower:2:upper
            y = yscale(tick)
            println(io, "<line x1=\"$left\" y1=\"$(_svg_number(y))\" x2=\"$(left+plot_width)\" y2=\"$(_svg_number(y))\" stroke=\"#e5e7eb\"/><text x=\"$(left-8)\" y=\"$(_svg_number(y+4))\" text-anchor=\"end\" font-family=\"sans-serif\" font-size=\"11\">1e$(Int(tick))</text>")
        end
        println(io, "<rect x=\"$left\" y=\"$top\" width=\"$plot_width\" height=\"$plot_height\" fill=\"none\" stroke=\"#374151\"/>")
        for (i, id) in enumerate(scenario_ids)
            center = left + (i-0.5)group_width
            println(io, "<text x=\"$(_svg_number(center))\" y=\"$(top+plot_height+26)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"12\">$(_svg_escape(string(id)))</text>")
            for (j, (_, values, color)) in enumerate(metrics)
                value = log10(max(values[i], 1e-8))
                x = center - 0.36group_width + (j-1)bar_width
                y = yscale(value)
                println(io, "<rect x=\"$(_svg_number(x))\" y=\"$(_svg_number(y))\" width=\"$(_svg_number(0.82bar_width))\" height=\"$(_svg_number(yscale(lower)-y))\" fill=\"$color\"/>")
            end
        end
        for (j, (name, _, color)) in enumerate(metrics)
            y = top + 26(j-1) + 20
            println(io, "<rect x=\"$(left+plot_width+30)\" y=\"$(y-9)\" width=\"16\" height=\"16\" fill=\"$color\"/><text x=\"$(left+plot_width+54)\" y=\"$(y+3)\" font-family=\"sans-serif\" font-size=\"12\">$name</text>")
        end
        println(io, "</svg>")
    end
    path
end

function _validation_cell(failures, names)
    any(name -> name in failures, names) ? ("FAIL", "#fecaca") : ("PASS", "#d1fae5")
end

"""Plot independent scenario checks, including invalid and corrupted results."""
function write_scopf_validation_matrix_plot(path::AbstractString, study::Study,
    result::SCOPFResult; title::AbstractString="SCOPF independent validation matrix")
    report = equilibrium_report(study, result)
    groups = [
        ("State", (:missing_state, :state_dimension, :nonfinite_or_invalid_state)),
        ("AC balance", (:power_balance,)), ("Droop/AVR", (:droop, :avr, :avr_sharing, :fixed_q)),
        ("Voltage", (:voltage_min, :voltage_max)), ("Thermal", (:branch_thermal,)),
        ("Generator P", (:generator_p_min, :generator_p_max)),
        ("Generator Q", (:generator_q_min, :generator_q_max)),
        ("Availability", (:unavailable_generator,)),
        ("P response", (:active_power_response, :missing_balancing_power, :missing_base_state)),
        ("Equipment", (:equipment_response, :tap_settings, :shunt_settings)),
    ]
    rows = Vector{Any}[]
    for id in report.scenario_ids
        failures = get(report.violations, id, Symbol[])
        push!(rows, Any[string(id); [_validation_cell(failures, names)
            for (_, names) in groups]])
    end
    status = report.valid ? "PASS" : "FAIL ($(report.termination_status))"
    title_with_status = "$title — $status"
    _scopf_svg_table(path, title_with_status,
        "Independent physical and cross-scenario checks; red cells identify the failure family.",
        ["Scenario"; first.(groups)], rows; cell_widths=[135; fill(108, length(groups))])
end

"""Write a Markdown index connecting SCOPF inputs, outputs, plots, and validation."""
function write_scopf_evaluation_report(path::AbstractString, study::Study,
    result::SCOPFResult; plot_paths=nothing)
    report = equilibrium_report(study,result)
    plots = isnothing(plot_paths) ? write_scopf_validation_plots(dirname(path),study,result) :
        plot_paths
    lines = ["# SCOPF input/output evaluation", "",
        "- Case: `$(study.case.id)`",
        "- Response mode: `$(study.mode)`",
        "- Scenarios: $(length(report.scenario_ids))",
        "- Solver status: `$(report.termination_status)`",
        "- Independently valid and solver-accepted: `$(report.valid)`", "",
        "## Declared inputs and cross-scenario checks", "",
        "![Declared scenario inputs]($(basename(plots.inputs)))", "",
        "![Operating margins]($(basename(plots.margins)))", "",
        "![Response deltas]($(basename(plots.response_deltas)))", "",
        "![Validation matrix]($(basename(plots.validation_matrix)))", "",
        "## Detailed operating plots", "",
        "![Droop operating points]($(basename(plots.droop)))", "",
        "![Bus voltages]($(basename(plots.voltage)))", "",
        "![Network loading]($(basename(plots.branch_loading)))", "",
        "![Generator dispatch]($(basename(plots.dispatch)))", "",
        "![Validation residuals]($(basename(plots.residuals)))", "",
        "## Numerical validation", "", markdown_report(report), ""]
    write(path,join(lines,"\n"))
    path
end
