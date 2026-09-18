"""Metrics and solver status for one fixed droop slope in an M3 parameter sweep."""
struct DroopSlopeSweepPoint
    slope::Float64
    objective::Float64
    max_voltage_deviation::Float64
    max_branch_loading_percent::Float64
    max_exact_droop_residual::Float64
    valid::Bool
    termination_status::Symbol
end

"""A reference-anchored sweep of one control's positive droop slope."""
struct DroopSlopeSweep
    control_id::Int
    reference_slope::Float64
    points::Vector{DroopSlopeSweepPoint}
end

function _study_with_control_slope(study::Study, control_id::Integer, slope::Real)
    1 <= control_id <= length(study.case.controls) ||
        throw(ArgumentError("control_id is out of range"))
    isfinite(slope) && slope > 0 ||
        throw(ArgumentError("droop slope must be positive and finite"))
    controls = copy(study.case.controls)
    control = controls[control_id]
    controls[control_id] = VoltVarDroop(
        control.schedule,
        Float64(slope),
        control.q_at_deadband,
        control.capability,
    )
    case = Case(
        study.case.id;
        base_power = study.case.base_power,
        base_frequency = study.case.base_frequency,
        network = study.case.network,
        loads = study.case.loads,
        generators = study.case.generators,
        controls = controls,
        attachments = study.case.attachments,
    )
    return Study(
        case;
        contingencies = study.contingencies,
        mode = study.mode,
        participation = study.participation,
        redispatch_limits = study.redispatch_limits,
    )
end

function _sweep_point(study::Study, slope::Real, result::SCOPFResult)
    report = equilibrium_report(study, result)
    max_voltage_deviation = 0.0
    max_branch_loading_percent = 0.0
    complete = true
    ids = [:base; [contingency.id for contingency in study.contingencies]]
    cases = [study.case; [scenario_case(study.case, contingency) for contingency in study.contingencies]]
    for (id, case) in zip(ids, cases)
        state = get(result.states, id, nothing)
        if isnothing(state)
            complete = false
            break
        end
        max_voltage_deviation = max(max_voltage_deviation, maximum(abs.(state.vm .- 1.0)))
        flows = branch_flows(case.network, state)
        for (index, branch) in enumerate(case.network.branches)
            branch.available || continue
            loading = 100 * max(abs(flows.from[index]), abs(flows.to[index])) /
                branch.thermal_limit
            max_branch_loading_percent = max(max_branch_loading_percent, loading)
        end
    end
    max_exact_droop_residual = isempty(report.scenarios) ? NaN :
        maximum(scenario.droop_residual_max for scenario in values(report.scenarios))
    return DroopSlopeSweepPoint(
        Float64(slope),
        result.objective,
        complete ? max_voltage_deviation : NaN,
        complete ? max_branch_loading_percent : NaN,
        max_exact_droop_residual,
        report.valid,
        result.termination_status,
    )
end

"""Evaluate bounded fixed-slope M2 studies, anchored and warm-started at a reference slope."""
function sweep_droop_slope(
    study::Study,
    control_id::Integer,
    slopes;
    reference_slope::Union{Nothing,Real} = nothing,
    solver_kwargs...,
)
    1 <= control_id <= length(study.case.controls) ||
        throw(ArgumentError("control_id is out of range"))
    reference_slope = isnothing(reference_slope) ?
        study.case.controls[control_id].slope : reference_slope
    haskey(solver_kwargs, :initial_states) &&
        throw(ArgumentError("initial_states are managed by the reference-anchored sweep"))
    isfinite(reference_slope) && reference_slope > 0 ||
        throw(ArgumentError("reference_slope must be positive and finite"))
    slope_values = Float64[Float64(slope) for slope in slopes]
    all(slope -> isfinite(slope) && slope > 0, slope_values) ||
        throw(ArgumentError("all droop slopes must be positive and finite"))
    push!(slope_values, Float64(reference_slope))
    slope_values = sort!(unique!(slope_values))
    solve_order = sort(slope_values; by = slope -> (abs(slope - reference_slope), slope))
    solved = Dict{Float64,SCOPFResult}()
    points = Dict{Float64,DroopSlopeSweepPoint}()
    for slope in solve_order
        candidate = _study_with_control_slope(study, control_id, slope)
        nearest = isempty(solved) ? nothing :
            argmin(value -> abs(value - slope), collect(keys(solved)))
        initial_states = isnothing(nearest) ? Dict() : Dict(
            id => state for (id, state) in solved[nearest].states if !isnothing(state)
        )
        result = solve_scopf(candidate; initial_states = initial_states, solver_kwargs...)
        point = _sweep_point(candidate, slope, result)
        points[slope] = point
        point.valid && (solved[slope] = result)
    end
    return DroopSlopeSweep(
        Int(control_id),
        Float64(reference_slope),
        [points[slope] for slope in slope_values],
    )
end

"""Return the valid sweep point with the smallest M2 dispatch objective."""
function best_droop_slope(sweep::DroopSlopeSweep)
    candidates = [point for point in sweep.points if point.valid && isfinite(point.objective)]
    isempty(candidates) && throw(ArgumentError("the sweep has no valid points"))
    return argmin(point -> point.objective, candidates)
end

_json_data(point::DroopSlopeSweepPoint) = Dict(
    string(field) => _json_data(getfield(point, field)) for field in fieldnames(typeof(point))
)
_json_data(sweep::DroopSlopeSweep) = Dict(
    "control_id" => sweep.control_id,
    "reference_slope" => sweep.reference_slope,
    "points" => _json_data(sweep.points),
)

"""Write a versioned, machine-readable droop-slope sweep."""
write_droop_slope_sweep(path::AbstractString, sweep::DroopSlopeSweep) =
    _write_scopf_json(path, "DroopOPF.DroopSlopeSweep", sweep)

"""Read a droop-slope sweep written by [`write_droop_slope_sweep`](@ref)."""
function read_droop_slope_sweep(path::AbstractString)
    data = _read_scopf_json(path, "DroopOPF.DroopSlopeSweep")
    points = DroopSlopeSweepPoint[
        DroopSlopeSweepPoint(
            Float64(point["slope"]),
            isnothing(point["objective"]) ? NaN : Float64(point["objective"]),
            isnothing(point["max_voltage_deviation"]) ? NaN :
                Float64(point["max_voltage_deviation"]),
            isnothing(point["max_branch_loading_percent"]) ? NaN :
                Float64(point["max_branch_loading_percent"]),
            isnothing(point["max_exact_droop_residual"]) ? NaN :
                Float64(point["max_exact_droop_residual"]),
            Bool(point["valid"]),
            Symbol(point["termination_status"]),
        ) for point in data["points"]
    ]
    return DroopSlopeSweep(
        Int(data["control_id"]),
        Float64(data["reference_slope"]),
        points,
    )
end

function _sweep_limits(values)
    low, high = extrema(values)
    padding = max(0.08 * (high - low), 0.05 * max(abs(low), abs(high)), 1e-10)
    return low - padding, high + padding
end

"""Write a three-panel SVG of objective, voltage deviation, and branch loading."""
function write_droop_slope_sweep_plot(
    path::AbstractString,
    sweep::DroopSlopeSweep;
    title::AbstractString = "M3 fixed-slope security trade-off",
)
    isempty(sweep.points) && throw(ArgumentError("cannot plot an empty sweep"))
    points = sort(sweep.points; by = point -> point.slope)
    valid = [point for point in points if point.valid]
    isempty(valid) && throw(ArgumentError("cannot plot a sweep with no valid points"))
    metrics = [
        ("Base dispatch objective", point -> point.objective, "#2563eb"),
        ("Worst |V - 1| (pu)", point -> point.max_voltage_deviation, "#d97706"),
        ("Maximum branch loading (%)", point -> point.max_branch_loading_percent, "#059669"),
    ]
    width, height = 1160, 900
    left, top, plot_width, panel_height, gap = 105, 70, 820, 205, 58
    slope_min, slope_max = extrema(point.slope for point in points)
    slope_padding = max(0.05 * (slope_max - slope_min), 0.0025)
    slope_min -= slope_padding
    slope_max += slope_padding
    xscale(slope) = left + plot_width * (slope - slope_min) / (slope_max - slope_min)
    best = best_droop_slope(sweep)
    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<title>$(_svg_escape(title))</title><desc>Reference-anchored M3 sweep of one fixed droop slope through the validated M2 SCOPF.</desc>")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
        println(io, "<text x=\"$left\" y=\"32\" font-family=\"sans-serif\" font-size=\"22\" font-weight=\"600\">$(_svg_escape(title))</text>")
        for (panel_index, (label, accessor, color)) in enumerate(metrics)
            panel_top = top + (panel_index - 1) * (panel_height + gap)
            values = [accessor(point) for point in valid]
            y_min, y_max = _sweep_limits(values)
            yscale(value) = panel_top + panel_height * (y_max - value) / (y_max - y_min)
            for tick in range(y_min, y_max, length = 5)
                y = yscale(tick)
                println(io, "<line x1=\"$left\" y1=\"$(_svg_number(y))\" x2=\"$(left+plot_width)\" y2=\"$(_svg_number(y))\" stroke=\"#e5e7eb\"/>")
                println(io, "<text x=\"$(left-10)\" y=\"$(_svg_number(y+4))\" text-anchor=\"end\" font-family=\"sans-serif\" font-size=\"11\">$(_svg_number(tick))</text>")
            end
            reference_x = xscale(sweep.reference_slope)
            println(io, "<line x1=\"$(_svg_number(reference_x))\" y1=\"$panel_top\" x2=\"$(_svg_number(reference_x))\" y2=\"$(panel_top+panel_height)\" stroke=\"#6b7280\" stroke-dasharray=\"5,4\"/>")
            coordinates = join(("$(_svg_number(xscale(point.slope))),$(_svg_number(yscale(accessor(point))))" for point in valid), " ")
            println(io, "<polyline points=\"$coordinates\" fill=\"none\" stroke=\"$color\" stroke-width=\"3\"/>")
            for point in valid
                radius = point.slope == best.slope ? 7 : 5
                println(io, "<circle cx=\"$(_svg_number(xscale(point.slope)))\" cy=\"$(_svg_number(yscale(accessor(point))))\" r=\"$radius\" fill=\"$color\" stroke=\"#111827\" stroke-width=\"1.5\"/>")
            end
            for point in points
                point.valid && continue
                x, y = xscale(point.slope), panel_top + panel_height - 9
                println(io, "<line x1=\"$(_svg_number(x-6))\" y1=\"$(_svg_number(y-6))\" x2=\"$(_svg_number(x+6))\" y2=\"$(_svg_number(y+6))\" stroke=\"#dc2626\" stroke-width=\"2\"/>")
                println(io, "<line x1=\"$(_svg_number(x-6))\" y1=\"$(_svg_number(y+6))\" x2=\"$(_svg_number(x+6))\" y2=\"$(_svg_number(y-6))\" stroke=\"#dc2626\" stroke-width=\"2\"/>")
            end
            println(io, "<rect x=\"$left\" y=\"$panel_top\" width=\"$plot_width\" height=\"$panel_height\" fill=\"none\" stroke=\"#374151\"/>")
            println(io, "<text x=\"18\" y=\"$(panel_top+panel_height/2)\" transform=\"rotate(-90 18 $(panel_top+panel_height/2))\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"13\">$(_svg_escape(label))</text>")
        end
        bottom = top + 2 * (panel_height + gap) + panel_height
        for point in points
            x = xscale(point.slope)
            println(io, "<text x=\"$(_svg_number(x))\" y=\"$(bottom+24)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"11\">$(_svg_number(point.slope))</text>")
        end
        println(io, "<text x=\"$(left+plot_width/2)\" y=\"$(height-22)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\">Droop slope ΔV/ΔQ (pu/pu)</text>")
        println(io, "<text x=\"$(left+plot_width+30)\" y=\"$(top+20)\" font-family=\"sans-serif\" font-size=\"12\" font-weight=\"600\">Reference</text>")
        println(io, "<text x=\"$(left+plot_width+30)\" y=\"$(top+40)\" font-family=\"sans-serif\" font-size=\"12\">$(_svg_number(sweep.reference_slope))</text>")
        println(io, "<text x=\"$(left+plot_width+30)\" y=\"$(top+78)\" font-family=\"sans-serif\" font-size=\"12\" font-weight=\"600\">Best valid objective</text>")
        println(io, "<text x=\"$(left+plot_width+30)\" y=\"$(top+98)\" font-family=\"sans-serif\" font-size=\"12\">slope $(_svg_number(best.slope))</text>")
        println(io, "<text x=\"$(left+plot_width+30)\" y=\"$(top+116)\" font-family=\"sans-serif\" font-size=\"12\">objective $(_svg_number(best.objective))</text>")
        println(io, "</svg>")
    end
    return path
end
