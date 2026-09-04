using Printf

struct DroopOperatingPoint{T<:Real}
    generator_id::Int
    control_id::Int
    voltage::T
    reactive_power::T
    regime::Symbol
end

function droop_regime(control::VoltVarDroop, voltage::Real)
    breakpoints = control.curve.breakpoints
    if voltage <= breakpoints[1]
        return :saturation_qmax
    elseif voltage < breakpoints[2]
        return :proportional
    elseif voltage <= breakpoints[3]
        return :deadband
    elseif voltage < breakpoints[4]
        return :proportional
    end
    return :saturation_qmin
end

function droop_operating_point(
    control::VoltVarDroop,
    generator_id::Integer,
    control_id::Integer,
    voltage::Real;
    p::Real,
    reactive_power::Union{Nothing,Real} = nothing,
)
    q = isnothing(reactive_power) ? droop_response(control, voltage; p = p) : reactive_power
    return DroopOperatingPoint(
        Int(generator_id),
        Int(control_id),
        Float64(voltage),
        Float64(q),
        droop_regime(control, voltage),
    )
end

function droop_operating_points(case::Case, state::ACState)
    isnothing(case.network) && throw(ArgumentError("case has no AC network"))
    bus_indices = _bus_indices(case.network)
    generator_indices = Dict(generator.id => i for (i, generator) in enumerate(case.generators))
    return [
        begin
            generator_index = generator_indices[attachment.generator_id]
            generator = case.generators[generator_index]
            control = case.controls[attachment.control_id]
            voltage = state.vm[bus_indices[attachment.location.bus_id]]
            droop_operating_point(
                control,
                generator.id,
                attachment.control_id,
                voltage;
                p = state.pg[generator_index],
                reactive_power = state.qg[generator_index],
            )
        end
        for attachment in case.attachments if case.generators[generator_indices[attachment.generator_id]].available
    ]
end

_svg_number(x::Real) = @sprintf("%.7g", Float64(x))
_svg_escape(text::AbstractString) = replace(
    replace(replace(String(text), "&" => "&amp;"), "<" => "&lt;"), ">" => "&gt;",
)

"""Write exact volt-var curves and operating points to a self-contained SVG."""
function write_droop_plot(
    path::AbstractString,
    controls::AbstractVector{<:VoltVarDroop},
    points::AbstractVector{<:DroopOperatingPoint} = DroopOperatingPoint[];
    samples::Integer = 300,
    title::AbstractString = "Volt-var droop operating points",
)
    isempty(controls) && throw(ArgumentError("at least one control is required"))
    samples >= 2 || throw(ArgumentError("samples must be at least 2"))
    all(point -> 1 <= point.control_id <= length(controls), points) ||
        throw(ArgumentError("operating point control_id is out of range"))

    curve_voltages = reduce(vcat, (control.curve.breakpoints for control in controls))
    voltages = vcat(curve_voltages, [point.voltage for point in points])
    reactive_powers = vcat(
        reduce(vcat, (control.curve.values for control in controls)),
        [point.reactive_power for point in points],
    )
    voltage_min, voltage_max = extrema(voltages)
    reactive_min, reactive_max = extrema(reactive_powers)
    voltage_padding = max((voltage_max - voltage_min) * 0.06, 0.005)
    reactive_padding = max((reactive_max - reactive_min) * 0.08, 0.02)
    voltage_min -= voltage_padding
    voltage_max += voltage_padding
    reactive_min -= reactive_padding
    reactive_max += reactive_padding

    width, height = 1100, 650
    left, top, plot_width, plot_height = 90, 58, 820, 500
    xscale(v) = left + plot_width * (v - voltage_min) / (voltage_max - voltage_min)
    yscale(q) = top + plot_height * (reactive_max - q) / (reactive_max - reactive_min)
    colors = ["#2563eb", "#d97706", "#059669", "#9333ea", "#dc2626", "#0891b2"]

    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<title>$(_svg_escape(title))</title>")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
        println(io, "<text x=\"$left\" y=\"28\" font-family=\"sans-serif\" font-size=\"20\" font-weight=\"600\">$(_svg_escape(title))</text>")

        for tick in range(voltage_min, voltage_max, length = 6)
            x = xscale(tick)
            println(io, "<line x1=\"$(_svg_number(x))\" y1=\"$top\" x2=\"$(_svg_number(x))\" y2=\"$(top + plot_height)\" stroke=\"#e5e7eb\"/>")
            println(io, "<text x=\"$(_svg_number(x))\" y=\"$(top + plot_height + 22)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"12\">$(_svg_number(tick))</text>")
        end
        for tick in range(reactive_min, reactive_max, length = 6)
            y = yscale(tick)
            println(io, "<line x1=\"$left\" y1=\"$(_svg_number(y))\" x2=\"$(left + plot_width)\" y2=\"$(_svg_number(y))\" stroke=\"#e5e7eb\"/>")
            println(io, "<text x=\"$(left - 10)\" y=\"$(_svg_number(y + 4))\" text-anchor=\"end\" font-family=\"sans-serif\" font-size=\"12\">$(_svg_number(tick))</text>")
        end
        println(io, "<rect x=\"$left\" y=\"$top\" width=\"$plot_width\" height=\"$plot_height\" fill=\"none\" stroke=\"#374151\"/>")
        println(io, "<text x=\"$(left + plot_width / 2)\" y=\"$(height - 28)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\">Voltage magnitude (pu)</text>")
        println(io, "<text x=\"18\" y=\"$(top + plot_height / 2)\" transform=\"rotate(-90 18 $(top + plot_height / 2))\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\">Reactive power Q (pu)</text>")

        for (control_id, control) in enumerate(controls)
            color = colors[mod1(control_id, length(colors))]
            low_x, high_x = control.schedule.v_db_low, control.schedule.v_db_high
            for deadband_voltage in (low_x, high_x)
                x = xscale(deadband_voltage)
                println(io, "<line x1=\"$(_svg_number(x))\" y1=\"$top\" x2=\"$(_svg_number(x))\" y2=\"$(top + plot_height)\" stroke=\"$color\" stroke-dasharray=\"5,4\" opacity=\"0.45\"/>")
            end
            path_data = IOBuffer()
            for (index, voltage) in enumerate(range(voltage_min, voltage_max, length = samples))
                x, y = xscale(voltage), yscale(evaluate(control.curve, voltage))
                print(path_data, index == 1 ? "M" : "L", _svg_number(x), " ", _svg_number(y), " ")
            end
            println(io, "<path d=\"$(String(take!(path_data)))\" fill=\"none\" stroke=\"$color\" stroke-width=\"3\"/>")
            legend_y = top + 22 * (control_id - 1) + 18
            println(io, "<line x1=\"$(left + plot_width + 25)\" y1=\"$legend_y\" x2=\"$(left + plot_width + 48)\" y2=\"$legend_y\" stroke=\"$color\" stroke-width=\"3\"/>")
            println(io, "<text x=\"$(left + plot_width + 55)\" y=\"$(legend_y + 4)\" font-family=\"sans-serif\" font-size=\"12\">Control $control_id</text>")
        end

        for point in points
            color = colors[mod1(point.control_id, length(colors))]
            x, y = xscale(point.voltage), yscale(point.reactive_power)
            println(io, "<circle cx=\"$(_svg_number(x))\" cy=\"$(_svg_number(y))\" r=\"7\" fill=\"$color\" stroke=\"#111827\" stroke-width=\"2\"/>")
            label = "G$(point.generator_id): $(point.regime)"
            label_y = y - 10 - 16 * (point.generator_id - 1)
            println(io, "<text x=\"$(_svg_number(x + 10))\" y=\"$(_svg_number(label_y))\" font-family=\"sans-serif\" font-size=\"12\">$(_svg_escape(label))</text>")
        end
        println(io, "</svg>")
    end
    return path
end

function write_droop_plot(path::AbstractString, case::Case, state::ACState; kwargs...)
    controls = case.controls
    points = droop_operating_points(case, state)
    return write_droop_plot(path, controls, points; kwargs...)
end
