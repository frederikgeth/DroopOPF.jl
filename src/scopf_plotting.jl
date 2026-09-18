const _SCOPF_COLORS = ["#2563eb", "#d97706", "#059669", "#9333ea", "#dc2626", "#0891b2"]

function _scopf_scenario_cases(study::Study)
    ids = [:base; [contingency.id for contingency in study.contingencies]]
    cases = [study.case; [scenario_case(study.case, contingency) for contingency in study.contingencies]]
    return ids, cases
end

function _scopf_plot_data(study::Study, result::SCOPFResult)
    ids, cases = _scopf_scenario_cases(_validated_study(study))
    Set(keys(result.states)) == Set(ids) ||
        throw(ArgumentError("result scenario set does not match the study"))
    states = ACState[]
    for id in ids
        state = result.states[id]
        isnothing(state) && throw(ArgumentError("scenario $id has no state to plot"))
        push!(states, state)
    end
    return ids, cases, states
end

"""Return all available-generator droop operating points grouped by scenario."""
function scopf_operating_points(study::Study, result::SCOPFResult)
    ids, cases, states = _scopf_plot_data(study, result)
    return [
        (scenario = id, point = point)
        for (id, case, state) in zip(ids, cases, states)
        for point in droop_operating_points(case, state)
    ]
end

function _svg_marker(io, marker::Symbol, x, y, color; size = 7, fill = color)
    if marker == :square
        println(io, "<rect x=\"$(_svg_number(x - size))\" y=\"$(_svg_number(y - size))\" width=\"$(2size)\" height=\"$(2size)\" fill=\"$fill\" stroke=\"#111827\" stroke-width=\"2\"/>")
    elseif marker == :diamond
        println(io, "<polygon points=\"$(_svg_number(x)),$(_svg_number(y-size-1)) $(_svg_number(x+size+1)),$(_svg_number(y)) $(_svg_number(x)),$(_svg_number(y+size+1)) $(_svg_number(x-size-1)),$(_svg_number(y))\" fill=\"$fill\" stroke=\"#111827\" stroke-width=\"2\"/>")
    elseif marker == :triangle
        println(io, "<polygon points=\"$(_svg_number(x)),$(_svg_number(y-size-2)) $(_svg_number(x+size+1)),$(_svg_number(y+size)) $(_svg_number(x-size-1)),$(_svg_number(y+size))\" fill=\"$fill\" stroke=\"#111827\" stroke-width=\"2\"/>")
    else
        println(io, "<circle cx=\"$(_svg_number(x))\" cy=\"$(_svg_number(y))\" r=\"$size\" fill=\"$fill\" stroke=\"#111827\" stroke-width=\"2\"/>")
    end
end

_scenario_marker(index) = (:circle, :square, :diamond, :triangle)[mod1(index, 4)]

"""Write exact droop curves with base and contingency operating points."""
function write_scopf_droop_plot(
    path::AbstractString,
    study::Study,
    result::SCOPFResult;
    samples::Integer = 300,
    title::AbstractString = "M2 droop operating points by scenario",
)
    samples >= 2 || throw(ArgumentError("samples must be at least 2"))
    points = scopf_operating_points(study, result)
    isempty(study.case.controls) && throw(ArgumentError("at least one control is required"))
    curve_voltages = reduce(vcat, (control.curve.breakpoints for control in study.case.controls))
    curve_q = reduce(vcat, (control.curve.values for control in study.case.controls))
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
    width, height = 1180, 680
    left, top, plot_width, plot_height = 90, 58, 820, 520
    xscale(v) = left + plot_width * (v - voltage_min) / (voltage_max - voltage_min)
    yscale(q) = top + plot_height * (q_max - q) / (q_max - q_min)
    ids, _ = _scopf_scenario_cases(study)

    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<title>$(_svg_escape(title))</title><desc>Exact volt-var curves with operating points for the base case and every M2 contingency.</desc>")
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
        for (control_id, control) in enumerate(study.case.controls)
            color = _SCOPF_COLORS[mod1(control_id, length(_SCOPF_COLORS))]
            for deadband in (control.schedule.v_db_low, control.schedule.v_db_high)
                x = xscale(deadband)
                println(io, "<line x1=\"$(_svg_number(x))\" y1=\"$top\" x2=\"$(_svg_number(x))\" y2=\"$(top+plot_height)\" stroke=\"$color\" stroke-dasharray=\"5,4\" opacity=\"0.45\"/>")
            end
            data = IOBuffer()
            for (index, voltage) in enumerate(range(voltage_min, voltage_max, length = samples))
                print(data, index == 1 ? "M" : "L", _svg_number(xscale(voltage)), " ",
                    _svg_number(yscale(evaluate(control.curve, voltage))), " ")
            end
            dash = isodd(control_id) ? "" : " stroke-dasharray=\"10,6\""
            println(io, "<path d=\"$(String(take!(data)))\" fill=\"none\" stroke=\"$color\" stroke-width=\"3\"$dash/>")
            legend_y = top + 22 * (control_id - 1) + 18
            println(io, "<line x1=\"$(left+plot_width+25)\" y1=\"$legend_y\" x2=\"$(left+plot_width+48)\" y2=\"$legend_y\" stroke=\"$color\" stroke-width=\"3\"/>")
            println(io, "<text x=\"$(left+plot_width+55)\" y=\"$(legend_y+4)\" font-family=\"sans-serif\" font-size=\"12\">Control $control_id</text>")
        end
        scenario_top = top + 22 * length(study.case.controls) + 34
        for (index, id) in enumerate(ids)
            y = scenario_top + 25 * (index - 1)
            _svg_marker(io, _scenario_marker(index), left + plot_width + 38, y, "#6b7280"; size = 6, fill = "#9ca3af")
            println(io, "<text x=\"$(left+plot_width+55)\" y=\"$(_svg_number(y+4))\" font-family=\"sans-serif\" font-size=\"12\">$(_svg_escape(string(id)))</text>")
        end
        for item in points
            scenario_index = findfirst(==(item.scenario), ids)
            point = item.point
            color = _SCOPF_COLORS[mod1(point.control_id, length(_SCOPF_COLORS))]
            x, y = xscale(point.voltage), yscale(point.reactive_power)
            marker_size = max(5, 10 - 2 * (point.control_id - 1))
            _svg_marker(io, _scenario_marker(scenario_index), x, y, color; size = marker_size)
        end
        details_top = scenario_top + 25 * length(ids) + 24
        println(io, "<text x=\"$(left+plot_width+25)\" y=\"$details_top\" font-family=\"sans-serif\" font-size=\"12\" font-weight=\"600\">Operating points</text>")
        for (index, item) in enumerate(points)
            point = item.point
            label = "G$(point.generator_id) $(item.scenario) — $(point.regime)"
            y = details_top + 20 * index
            println(io, "<text x=\"$(left+plot_width+25)\" y=\"$y\" font-family=\"sans-serif\" font-size=\"11\">$(_svg_escape(label))</text>")
        end
        println(io, "</svg>")
    end
    return path
end

"""Write bus-voltage trajectories and their limits for every scenario."""
function write_scopf_voltage_plot(path::AbstractString, study::Study, result::SCOPFResult;
    title::AbstractString = "M2 bus voltages by scenario")
    ids, cases, states = _scopf_plot_data(study, result)
    buses = study.case.network.buses
    values = vcat([state.vm for state in states]...)
    limits = vcat([bus.v_min for bus in buses], [bus.v_max for bus in buses])
    y_min, y_max = extrema(vcat(values, limits))
    pad = max(0.005, 0.08 * (y_max-y_min))
    y_min -= pad; y_max += pad
    width, height = 1080, 620
    left, top, plot_width, plot_height = 90, 58, 790, 450
    xscale(i) = length(ids) == 1 ? left + plot_width/2 : left + plot_width*(i-1)/(length(ids)-1)
    xpos(i,bus_index) = xscale(i) + 7 * (bus_index - (length(buses)+1)/2)
    yscale(v) = top + plot_height*(y_max-v)/(y_max-y_min)
    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<title>$(_svg_escape(title))</title><desc>Bus voltage magnitudes across the base case and contingencies, with bus limits.</desc>")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
        println(io, "<text x=\"$left\" y=\"28\" font-family=\"sans-serif\" font-size=\"20\" font-weight=\"600\">$(_svg_escape(title))</text>")
        for tick in range(y_min, y_max, length=6)
            y=yscale(tick)
            println(io, "<line x1=\"$left\" y1=\"$(_svg_number(y))\" x2=\"$(left+plot_width)\" y2=\"$(_svg_number(y))\" stroke=\"#e5e7eb\"/>")
            println(io, "<text x=\"$(left-10)\" y=\"$(_svg_number(y+4))\" text-anchor=\"end\" font-family=\"sans-serif\" font-size=\"12\">$(_svg_number(tick))</text>")
        end
        println(io, "<rect x=\"$left\" y=\"$top\" width=\"$plot_width\" height=\"$plot_height\" fill=\"none\" stroke=\"#374151\"/>")
        println(io, "<text x=\"18\" y=\"$(top+plot_height/2)\" transform=\"rotate(-90 18 $(top+plot_height/2))\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\">Voltage magnitude (pu)</text>")
        for (index,id) in enumerate(ids)
            x=xscale(index)
            println(io, "<text x=\"$(_svg_number(x))\" y=\"$(top+plot_height+25)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"12\">$(_svg_escape(string(id)))</text>")
        end
        for (bus_index,bus) in enumerate(buses)
            color=_SCOPF_COLORS[mod1(bus_index,length(_SCOPF_COLORS))]
            points=join(("$(_svg_number(xpos(i,bus_index))),$(_svg_number(yscale(states[i].vm[bus_index])))" for i in eachindex(ids))," ")
            println(io, "<polyline points=\"$points\" fill=\"none\" stroke=\"$color\" stroke-width=\"2.5\"/>")
            for i in eachindex(ids)
                x=xpos(i,bus_index); v=states[i].vm[bus_index]
                println(io, "<line x1=\"$(_svg_number(x))\" y1=\"$(_svg_number(yscale(cases[i].network.buses[bus_index].v_min)))\" x2=\"$(_svg_number(x))\" y2=\"$(_svg_number(yscale(cases[i].network.buses[bus_index].v_max)))\" stroke=\"$color\" opacity=\"0.22\" stroke-width=\"5\"/>")
                println(io, "<circle cx=\"$(_svg_number(x))\" cy=\"$(_svg_number(yscale(v)))\" r=\"6\" fill=\"$color\" stroke=\"#111827\"/>")
            end
            legend_y=top+22*(bus_index-1)+18
            println(io, "<line x1=\"$(left+plot_width+25)\" y1=\"$legend_y\" x2=\"$(left+plot_width+48)\" y2=\"$legend_y\" stroke=\"$color\" stroke-width=\"3\"/>")
            println(io, "<text x=\"$(left+plot_width+55)\" y=\"$(legend_y+4)\" font-family=\"sans-serif\" font-size=\"12\">Bus $(bus.id)</text>")
        end
        println(io,"</svg>")
    end
    return path
end

"""Write branch loading percentages, marking unavailable branches as outages."""
function write_scopf_branch_loading_plot(path::AbstractString, study::Study, result::SCOPFResult;
    title::AbstractString = "M2 branch loading by scenario")
    ids,cases,states=_scopf_plot_data(study,result)
    nbranch=length(study.case.network.branches)
    loading=zeros(Float64,length(ids),nbranch)
    available=trues(length(ids),nbranch)
    for i in eachindex(ids)
        flows=branch_flows(cases[i].network,states[i])
        for j in 1:nbranch
            branch=cases[i].network.branches[j]
            available[i,j]=branch.available
            loading[i,j]=branch.available ? 100max(abs(flows.from[j]),abs(flows.to[j]))/branch.thermal_limit : 0.0
        end
    end
    y_max=max(110.0,1.12maximum(loading))
    width,height=1180,650
    left,top,plot_width,plot_height=90,58,880,470
    groups=length(ids); group_width=plot_width/groups; bar_width=0.72group_width/max(nbranch,1)
    yscale(v)=top+plot_height*(y_max-v)/y_max
    open(path,"w") do io
        println(io,"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io,"<title>$(_svg_escape(title))</title><desc>Branch apparent-power loading as a percentage of rating, with outages marked.</desc>")
        println(io,"<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
        println(io,"<text x=\"$left\" y=\"28\" font-family=\"sans-serif\" font-size=\"20\" font-weight=\"600\">$(_svg_escape(title))</text>")
        for tick in range(0,y_max,length=6)
            y=yscale(tick)
            println(io,"<line x1=\"$left\" y1=\"$(_svg_number(y))\" x2=\"$(left+plot_width)\" y2=\"$(_svg_number(y))\" stroke=\"#e5e7eb\"/>")
            println(io,"<text x=\"$(left-10)\" y=\"$(_svg_number(y+4))\" text-anchor=\"end\" font-family=\"sans-serif\" font-size=\"12\">$(_svg_number(tick))</text>")
        end
        limit_y=yscale(100)
        println(io,"<line x1=\"$left\" y1=\"$(_svg_number(limit_y))\" x2=\"$(left+plot_width)\" y2=\"$(_svg_number(limit_y))\" stroke=\"#dc2626\" stroke-width=\"2\" stroke-dasharray=\"6,4\"/>")
        println(io,"<text x=\"$(left+plot_width+8)\" y=\"$(_svg_number(limit_y+4))\" font-family=\"sans-serif\" font-size=\"12\">rating</text>")
        println(io,"<rect x=\"$left\" y=\"$top\" width=\"$plot_width\" height=\"$plot_height\" fill=\"none\" stroke=\"#374151\"/>")
        println(io,"<text x=\"18\" y=\"$(top+plot_height/2)\" transform=\"rotate(-90 18 $(top+plot_height/2))\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\">Loading (% of rating)</text>")
        for i in eachindex(ids)
            center=left+(i-0.5)group_width
            println(io,"<text x=\"$(_svg_number(center))\" y=\"$(top+plot_height+27)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"12\">$(_svg_escape(string(ids[i])))</text>")
            for j in 1:nbranch
                x=center-0.36group_width+(j-1)bar_width
                color=_SCOPF_COLORS[mod1(j,length(_SCOPF_COLORS))]
                if available[i,j]
                    y=yscale(loading[i,j]); h=top+plot_height-y
                    println(io,"<rect x=\"$(_svg_number(x))\" y=\"$(_svg_number(y))\" width=\"$(_svg_number(0.82bar_width))\" height=\"$(_svg_number(h))\" fill=\"$color\"/>")
                else
                    y=top+plot_height-8
                    println(io,"<line x1=\"$(_svg_number(x))\" y1=\"$(_svg_number(y-7))\" x2=\"$(_svg_number(x+0.82bar_width))\" y2=\"$(_svg_number(y+7))\" stroke=\"$color\" stroke-width=\"2\"/>")
                    println(io,"<line x1=\"$(_svg_number(x))\" y1=\"$(_svg_number(y+7))\" x2=\"$(_svg_number(x+0.82bar_width))\" y2=\"$(_svg_number(y-7))\" stroke=\"$color\" stroke-width=\"2\"/>")
                end
            end
        end
        for (j,branch) in enumerate(study.case.network.branches)
            color=_SCOPF_COLORS[mod1(j,length(_SCOPF_COLORS))]; y=top+22*(j-1)+18
            println(io,"<rect x=\"$(left+plot_width+28)\" y=\"$(y-7)\" width=\"14\" height=\"14\" fill=\"$color\"/>")
            println(io,"<text x=\"$(left+plot_width+50)\" y=\"$(y+4)\" font-family=\"sans-serif\" font-size=\"12\">Branch $(branch.id)</text>")
        end
        println(io,"<text x=\"$(left+plot_width+28)\" y=\"$(top+22nbranch+22)\" font-family=\"sans-serif\" font-size=\"12\">× = outaged</text></svg>")
    end
    return path
end

"""Write active and reactive generator dispatch for every scenario."""
function write_scopf_dispatch_plot(path::AbstractString, study::Study, result::SCOPFResult;
    title::AbstractString = "M2 generator dispatch response")
    ids,cases,states=_scopf_plot_data(study,result)
    ngen=length(study.case.generators)
    all_values=vcat([vcat(state.pg,state.qg) for state in states]..., [0.0])
    y_min,y_max=extrema(all_values); pad=max(0.05,0.12(y_max-y_min)); y_min-=pad; y_max+=pad
    width,height=1240,670
    left,top,plot_width,plot_height=90,58,940,480
    groups=length(ids); group_width=plot_width/groups; unit_width=0.78group_width/max(ngen,1)
    yscale(v)=top+plot_height*(y_max-v)/(y_max-y_min); zero_y=yscale(0)
    open(path,"w") do io
        println(io,"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io,"<title>$(_svg_escape(title))</title><desc>Active and reactive generator dispatch in the base case and contingencies; outaged generators are marked.</desc>")
        println(io,"<rect width=\"100%\" height=\"100%\" fill=\"white\"/><text x=\"$left\" y=\"28\" font-family=\"sans-serif\" font-size=\"20\" font-weight=\"600\">$(_svg_escape(title))</text>")
        for tick in range(y_min,y_max,length=6)
            y=yscale(tick)
            println(io,"<line x1=\"$left\" y1=\"$(_svg_number(y))\" x2=\"$(left+plot_width)\" y2=\"$(_svg_number(y))\" stroke=\"#e5e7eb\"/><text x=\"$(left-10)\" y=\"$(_svg_number(y+4))\" text-anchor=\"end\" font-family=\"sans-serif\" font-size=\"12\">$(_svg_number(tick))</text>")
        end
        println(io,"<line x1=\"$left\" y1=\"$(_svg_number(zero_y))\" x2=\"$(left+plot_width)\" y2=\"$(_svg_number(zero_y))\" stroke=\"#374151\"/><rect x=\"$left\" y=\"$top\" width=\"$plot_width\" height=\"$plot_height\" fill=\"none\" stroke=\"#374151\"/>")
        println(io,"<text x=\"18\" y=\"$(top+plot_height/2)\" transform=\"rotate(-90 18 $(top+plot_height/2))\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\">Dispatch (pu)</text>")
        for i in eachindex(ids)
            center=left+(i-0.5)group_width
            println(io,"<text x=\"$(_svg_number(center))\" y=\"$(top+plot_height+43)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"12\">$(_svg_escape(string(ids[i])))</text>")
            for j in 1:ngen
                x=center-0.39group_width+(j-1)unit_width
                gen=cases[i].generators[j]
                if gen.available
                    for (offset,value,color) in ((0.0,states[i].pg[j],"#2563eb"),(0.43unit_width,states[i].qg[j],"#d97706"))
                        y=yscale(value); height_value=abs(zero_y-y)
                        println(io,"<rect x=\"$(_svg_number(x+offset))\" y=\"$(_svg_number(min(y,zero_y)))\" width=\"$(_svg_number(0.38unit_width))\" height=\"$(_svg_number(height_value))\" fill=\"$color\"/>")
                    end
                else
                    println(io,"<line x1=\"$(_svg_number(x))\" y1=\"$(_svg_number(zero_y-8))\" x2=\"$(_svg_number(x+0.8unit_width))\" y2=\"$(_svg_number(zero_y+8))\" stroke=\"#dc2626\" stroke-width=\"2\"/>")
                    println(io,"<line x1=\"$(_svg_number(x))\" y1=\"$(_svg_number(zero_y+8))\" x2=\"$(_svg_number(x+0.8unit_width))\" y2=\"$(_svg_number(zero_y-8))\" stroke=\"#dc2626\" stroke-width=\"2\"/>")
                end
                println(io,"<text x=\"$(_svg_number(x+0.4unit_width))\" y=\"$(top+plot_height+20)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"11\">G$(gen.id)</text>")
            end
        end
        println(io,"<rect x=\"$(left+plot_width+28)\" y=\"$(top+10)\" width=\"14\" height=\"14\" fill=\"#2563eb\"/><text x=\"$(left+plot_width+50)\" y=\"$(top+22)\" font-family=\"sans-serif\" font-size=\"12\">Active P</text>")
        println(io,"<rect x=\"$(left+plot_width+28)\" y=\"$(top+36)\" width=\"14\" height=\"14\" fill=\"#d97706\"/><text x=\"$(left+plot_width+50)\" y=\"$(top+48)\" font-family=\"sans-serif\" font-size=\"12\">Reactive Q</text>")
        println(io,"<text x=\"$(left+plot_width+28)\" y=\"$(top+78)\" font-family=\"sans-serif\" font-size=\"12\">× = outaged</text></svg>")
    end
    return path
end

"""Write residual-to-tolerance ratios for AC balance, exact droop, and coupling."""
function write_scopf_residual_plot(path::AbstractString, study::Study, result::SCOPFResult;
    title::AbstractString = "M2 independent validation residuals")
    report=equilibrium_report(study,result)
    ids=report.scenario_ids
    all(id -> haskey(report.scenarios,id),ids) || throw(ArgumentError("every scenario needs a validation report"))
    metrics=[
        ("AC balance", [report.scenarios[id].power_balance_max/report.tolerances.power_tolerance for id in ids], "#2563eb"),
        ("Exact droop", [report.scenarios[id].droop_residual_max/report.tolerances.droop_tolerance for id in ids], "#d97706"),
        ("Response", [get(report.coupling_violation,id,0.0)/report.tolerances.coupling_tolerance for id in ids], "#059669"),
    ]
    ratios=vcat([metric[2] for metric in metrics]...)
    lower=-6.0; upper=max(1.0,ceil(maximum(log10(max(value,1e-6)) for value in ratios)))
    width,height=1120,650
    left,top,plot_width,plot_height=95,58,820,470
    groups=length(ids); group_width=plot_width/groups; bar_width=0.72group_width/length(metrics)
    yscale(logratio)=top+plot_height*(upper-logratio)/(upper-lower)
    open(path,"w") do io
        println(io,"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io,"<title>$(_svg_escape(title))</title><desc>Independent residuals divided by their acceptance tolerances. Values below one pass.</desc>")
        println(io,"<rect width=\"100%\" height=\"100%\" fill=\"white\"/><text x=\"$left\" y=\"28\" font-family=\"sans-serif\" font-size=\"20\" font-weight=\"600\">$(_svg_escape(title))</text>")
        for exponent in Int(lower):Int(upper)
            y=yscale(exponent)
            println(io,"<line x1=\"$left\" y1=\"$(_svg_number(y))\" x2=\"$(left+plot_width)\" y2=\"$(_svg_number(y))\" stroke=\"#e5e7eb\"/><text x=\"$(left-10)\" y=\"$(_svg_number(y+4))\" text-anchor=\"end\" font-family=\"sans-serif\" font-size=\"12\">10^$exponent</text>")
        end
        pass_y=yscale(0)
        println(io,"<line x1=\"$left\" y1=\"$(_svg_number(pass_y))\" x2=\"$(left+plot_width)\" y2=\"$(_svg_number(pass_y))\" stroke=\"#dc2626\" stroke-width=\"2\" stroke-dasharray=\"6,4\"/><text x=\"$(left+plot_width+8)\" y=\"$(_svg_number(pass_y+4))\" font-family=\"sans-serif\" font-size=\"12\">tolerance</text>")
        println(io,"<rect x=\"$left\" y=\"$top\" width=\"$plot_width\" height=\"$plot_height\" fill=\"none\" stroke=\"#374151\"/><text x=\"18\" y=\"$(top+plot_height/2)\" transform=\"rotate(-90 18 $(top+plot_height/2))\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"14\">Residual / tolerance (log scale)</text>")
        for i in eachindex(ids)
            center=left+(i-0.5)group_width
            println(io,"<text x=\"$(_svg_number(center))\" y=\"$(top+plot_height+27)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"12\">$(_svg_escape(string(ids[i])))</text>")
            for (j,(_,values,color)) in enumerate(metrics)
                logratio=clamp(log10(max(values[i],1e-6)),lower,upper)
                x=center-0.36group_width+(j-1)bar_width; y=yscale(logratio)
                bar_height=max(2.0,yscale(lower)-y)
                println(io,"<rect x=\"$(_svg_number(x))\" y=\"$(_svg_number(yscale(lower)-bar_height))\" width=\"$(_svg_number(0.82bar_width))\" height=\"$(_svg_number(bar_height))\" fill=\"$color\"/>")
            end
        end
        for (j,(name,_,color)) in enumerate(metrics)
            y=top+24*(j-1)+18
            println(io,"<rect x=\"$(left+plot_width+28)\" y=\"$(y-7)\" width=\"14\" height=\"14\" fill=\"$color\"/><text x=\"$(left+plot_width+50)\" y=\"$(y+4)\" font-family=\"sans-serif\" font-size=\"12\">$name</text>")
        end
        status=report.valid ? "PASS" : "FAIL"; status_color=report.valid ? "#059669" : "#dc2626"
        println(io,"<text x=\"$(left+plot_width+28)\" y=\"$(top+108)\" font-family=\"sans-serif\" font-size=\"16\" font-weight=\"600\" fill=\"$status_color\">$status</text></svg>")
    end
    return path
end

"""Write the complete M2 visual-validation bundle and return its file paths."""
function write_scopf_validation_plots(directory::AbstractString, study::Study, result::SCOPFResult)
    mkpath(directory)
    paths = (
        droop = joinpath(directory,"m2_droop_operating_points.svg"),
        voltage = joinpath(directory,"m2_bus_voltages.svg"),
        branch_loading = joinpath(directory,"m2_branch_loading.svg"),
        dispatch = joinpath(directory,"m2_generator_dispatch.svg"),
        residuals = joinpath(directory,"m2_validation_residuals.svg"),
    )
    write_scopf_droop_plot(paths.droop,study,result)
    write_scopf_voltage_plot(paths.voltage,study,result)
    write_scopf_branch_loading_plot(paths.branch_loading,study,result)
    write_scopf_dispatch_plot(paths.dispatch,study,result)
    write_scopf_residual_plot(paths.residuals,study,result)
    return paths
end
