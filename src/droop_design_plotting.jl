function _droop_settings_match(left::DroopSettings, right::DroopSettings)
    return all(
        isapprox(getfield(left, field), getfield(right, field); atol = 1e-12, rtol = 1e-12)
        for field in fieldnames(typeof(left))
    )
end

function _design_plot_points(study::Study, result::SCOPFResult, control_id::Int, source::Symbol)
    return [
        (scenario = item.scenario, point = item.point, source = source)
        for item in scopf_operating_points(study, result)
        if item.point.control_id == control_id
    ]
end

"""Write the reference and optimized exact droop curves with validation points.

Training operating points come from `design.result`. When both held-out keywords
are supplied, non-base held-out points are added with a distinct marker colour.
The input study must contain the reference settings used to create `design`.
"""
function write_droop_design_comparison_plot(
    path::AbstractString,
    study::Study,
    design::DroopDesignResult;
    held_out_study::Union{Nothing,Study} = nothing,
    held_out_result::Union{Nothing,SCOPFResult} = nothing,
    samples::Integer = 300,
    title::AbstractString = "Reference and optimized droop design",
)
    samples >= 2 || throw(ArgumentError("samples must be at least 2"))
    xor(isnothing(held_out_study), isnothing(held_out_result)) &&
        throw(ArgumentError("held_out_study and held_out_result must be supplied together"))
    1 <= design.control_id <= length(study.case.controls) ||
        throw(ArgumentError("design control_id is out of range for the study"))

    reference_control = study.case.controls[design.control_id]
    _droop_settings_match(DroopSettings(reference_control), design.reference_settings) ||
        throw(ArgumentError("study control settings do not match the design reference"))
    optimized_study = with_droop_settings(study, design)
    optimized_control = optimized_study.case.controls[design.control_id]
    training_points = _design_plot_points(
        optimized_study,
        design.result,
        design.control_id,
        :training,
    )
    isempty(training_points) &&
        throw(ArgumentError("the optimized design has no operating points for its control"))

    training_ids, _ = _scopf_scenario_cases(optimized_study)
    scenario_entries = [
        (scenario = scenario, source = :training) for scenario in training_ids
    ]
    held_out_points = NamedTuple[]
    if !isnothing(held_out_study)
        1 <= design.control_id <= length(held_out_study.case.controls) ||
            throw(ArgumentError("design control_id is out of range for the held-out study"))
        held_out_settings = DroopSettings(held_out_study.case.controls[design.control_id])
        _droop_settings_match(held_out_settings, design.settings) ||
            throw(ArgumentError("held-out study does not use the optimized settings"))
        append!(
            held_out_points,
            filter(
                item -> item.scenario != :base,
                _design_plot_points(
                    held_out_study,
                    held_out_result,
                    design.control_id,
                    :held_out,
                ),
            ),
        )
        held_out_ids, _ = _scopf_scenario_cases(held_out_study)
        nonbase_held_out_ids = filter(!=(:base), held_out_ids)
        any(in(Set(training_ids)), nonbase_held_out_ids) &&
            throw(ArgumentError("held-out scenario IDs overlap the training scenarios"))
        append!(
            scenario_entries,
            ((scenario = scenario, source = :held_out) for scenario in nonbase_held_out_ids),
        )
    end
    points = vcat(training_points, held_out_points)

    curves = (reference_control.curve, optimized_control.curve)
    curve_voltages = reduce(vcat, (curve.breakpoints for curve in curves))
    curve_q = reduce(vcat, (curve.values for curve in curves))
    voltage_values = vcat(curve_voltages, [item.point.voltage for item in points])
    q_values = vcat(curve_q, [item.point.reactive_power for item in points])
    voltage_min, voltage_max = extrema(voltage_values)
    q_min, q_max = extrema(q_values)
    voltage_pad = max(0.005, 0.06 * (voltage_max - voltage_min))
    q_pad = max(0.02, 0.08 * (q_max - q_min))
    voltage_min -= voltage_pad
    voltage_max += voltage_pad
    q_min -= q_pad
    q_max += q_pad

    width, height = 1280, 680
    left, top, plot_width, plot_height = 90, 58, 820, 520
    xscale(v) = left + plot_width * (v - voltage_min) / (voltage_max - voltage_min)
    yscale(q) = top + plot_height * (q_max - q) / (q_max - q_min)
    reference_color, optimized_color = "#6b7280", "#2563eb"
    source_colors = Dict(:training => "#2563eb", :held_out => "#d97706")

    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<title>$(_svg_escape(title))</title><desc>Reference and optimized exact volt-var curves with training and held-out operating points.</desc>")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
        println(io, "<text x=\"$left\" y=\"28\" font-family=\"sans-serif\" font-size=\"20\" font-weight=\"600\">$(_svg_escape(title))</text>")
        for tick in range(voltage_min, voltage_max, length = 6)
            x = xscale(tick)
            println(io, "<line x1=\"$(_svg_number(x))\" y1=\"$top\" x2=\"$(_svg_number(x))\" y2=\"$(top+plot_height)\" stroke=\"#e5e7eb\"/>")
            println(io, "<text x=\"$(_svg_number(x))\" y=\"$(top+plot_height+22)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"12\">$(_svg_number(tick))</text>")
        end
        for tick in range(q_min, q_max, length = 6)
            y = yscale(tick)
            println(io, "<line x1=\"$left\" y1=\"$(_svg_number(y))\" x2=\"$(left+plot_width)\" y2=\"$(_svg_number(y))\" stroke=\"#e5e7eb\"/>")
            println(io, "<text x=\"$(left-10)\" y=\"$(_svg_number(y+4))\" text-anchor=\"end\" font-family=\"sans-serif\" font-size=\"12\">$(_svg_number(tick))</text>")
        end
        println(io, "<rect x=\"$left\" y=\"$top\" width=\"$plot_width\" height=\"$plot_height\" fill=\"none\" stroke=\"#374151\"/>")
        println(io, "<text x=\"$(left+plot_width/2)\" y=\"$(height-28)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\">Voltage magnitude (pu)</text>")
        println(io, "<text x=\"18\" y=\"$(top+plot_height/2)\" transform=\"rotate(-90 18 $(top+plot_height/2))\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\">Reactive power Q (pu)</text>")

        for (control, color, dash) in (
            (reference_control, reference_color, "10,6"),
            (optimized_control, optimized_color, ""),
        )
            for deadband in (control.schedule.v_db_low, control.schedule.v_db_high)
                x = xscale(deadband)
                println(io, "<line x1=\"$(_svg_number(x))\" y1=\"$top\" x2=\"$(_svg_number(x))\" y2=\"$(top+plot_height)\" stroke=\"$color\" stroke-dasharray=\"4,5\" opacity=\"0.35\"/>")
            end
            data = IOBuffer()
            for (index, voltage) in enumerate(range(voltage_min, voltage_max, length = samples))
                print(data, index == 1 ? "M" : "L", _svg_number(xscale(voltage)), " ",
                    _svg_number(yscale(evaluate(control.curve, voltage))), " ")
            end
            dash_attribute = isempty(dash) ? "" : " stroke-dasharray=\"$dash\""
            println(io, "<path d=\"$(String(take!(data)))\" fill=\"none\" stroke=\"$color\" stroke-width=\"3\"$dash_attribute/>")
        end

        legend_x = left + plot_width + 25
        println(io, "<line x1=\"$legend_x\" y1=\"$(top+18)\" x2=\"$(legend_x+23)\" y2=\"$(top+18)\" stroke=\"$reference_color\" stroke-width=\"3\" stroke-dasharray=\"10,6\"/>")
        println(io, "<text x=\"$(legend_x+30)\" y=\"$(top+22)\" font-family=\"sans-serif\" font-size=\"12\">Reference control $(design.control_id)</text>")
        println(io, "<line x1=\"$legend_x\" y1=\"$(top+44)\" x2=\"$(legend_x+23)\" y2=\"$(top+44)\" stroke=\"$optimized_color\" stroke-width=\"3\"/>")
        println(io, "<text x=\"$(legend_x+30)\" y=\"$(top+48)\" font-family=\"sans-serif\" font-size=\"12\">Optimized control $(design.control_id)</text>")

        scenario_ids = [entry.scenario for entry in scenario_entries]
        scenario_top = top + 82
        for (index, entry) in enumerate(scenario_entries)
            y = scenario_top + 25 * (index - 1)
            color = source_colors[entry.source]
            has_point = any(item -> item.scenario == entry.scenario, points)
            if has_point
                _svg_marker(io, _scenario_marker(index), legend_x + 13, y, color; size = 6)
            else
                println(io, "<line x1=\"$(legend_x+7)\" y1=\"$(y-6)\" x2=\"$(legend_x+19)\" y2=\"$(y+6)\" stroke=\"$color\" stroke-width=\"2\"/>")
                println(io, "<line x1=\"$(legend_x+7)\" y1=\"$(y+6)\" x2=\"$(legend_x+19)\" y2=\"$(y-6)\" stroke=\"$color\" stroke-width=\"2\"/>")
            end
            source_label = entry.source == :held_out ? "held-out" : "training"
            availability_label = has_point ? "" : "; no operating point"
            println(io, "<text x=\"$(legend_x+30)\" y=\"$(_svg_number(y+4))\" font-family=\"sans-serif\" font-size=\"12\">$(_svg_escape(string(entry.scenario))) ($source_label$availability_label)</text>")
        end

        for item in points
            scenario_index = findfirst(==(item.scenario), scenario_ids)
            x = xscale(item.point.voltage)
            y = yscale(item.point.reactive_power)
            _svg_marker(
                io,
                _scenario_marker(scenario_index),
                x,
                y,
                source_colors[item.source];
                size = 7,
            )
        end

        details_top = scenario_top + 25 * length(scenario_ids) + 24
        objective_change = iszero(design.reference_objective) ? "n/a" : string(
            _svg_number(
                100 * (design.result.objective - design.reference_objective) /
                abs(design.reference_objective),
            ),
            "%",
        )
        reference_low = design.reference_settings.v_ref - design.reference_settings.deadband_low
        optimized_low = design.settings.v_ref - design.settings.deadband_low
        reference_high = design.reference_settings.v_ref + design.reference_settings.deadband_high
        optimized_high = design.settings.v_ref + design.settings.deadband_high
        println(io, "<text x=\"$legend_x\" y=\"$details_top\" font-family=\"sans-serif\" font-size=\"12\" font-weight=\"600\">Design change</text>")
        println(io, "<text x=\"$legend_x\" y=\"$(details_top+20)\" font-family=\"sans-serif\" font-size=\"11\">slope: $(_svg_number(design.reference_settings.slope)) → $(_svg_number(design.settings.slope))</text>")
        println(io, "<text x=\"$legend_x\" y=\"$(details_top+38)\" font-family=\"sans-serif\" font-size=\"11\">v_ref: $(_svg_number(design.reference_settings.v_ref)) → $(_svg_number(design.settings.v_ref))</text>")
        println(io, "<text x=\"$legend_x\" y=\"$(details_top+56)\" font-family=\"sans-serif\" font-size=\"11\">low edge: $(_svg_number(reference_low)) → $(_svg_number(optimized_low))</text>")
        println(io, "<text x=\"$legend_x\" y=\"$(details_top+74)\" font-family=\"sans-serif\" font-size=\"11\">high edge: $(_svg_number(reference_high)) → $(_svg_number(optimized_high))</text>")
        println(io, "<text x=\"$legend_x\" y=\"$(details_top+92)\" font-family=\"sans-serif\" font-size=\"11\">objective change: $objective_change</text>")
        println(io, "</svg>")
    end
    return path
end
