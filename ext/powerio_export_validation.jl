# Validate the public constructor in O(buses + equipment) storage and work.
# Aggregate Ybus equality alone can hide swapped identities or compensating
# errors, and allocating a dense Ybus makes ordinary large cases impractical.
function _check_export_construction(n, data, c)
    function check(actual, expected, label)
        good = if actual isa Integer && expected isa Integer
            actual == expected
        elseif actual isa Real && expected isa Real
            isapprox(actual, expected; atol=1e-12, rtol=1e-10)
        else
            actual == expected
        end
        good || D._io_error(:export_construction_mismatch, :export,
            "PowerIO construction changed $label")
    end
    base = c.base_power
    check(n.base_mva, base, "base MVA")
    function rows(table, expected, label)
        check(length(table), length(expected), "$label count")
        # Explicit numeric dictionary indices establish constructor row order.
        # Public component_id values are generated identities, not those indices.
        check(length(unique(r.component_id for r in table)), length(expected), "$label identities")
        mapped = Dict(string(i) => r for (i,r) in enumerate(table))
        all(haskey(mapped, id) for id in keys(expected)) ||
            D._io_error(:export_construction_mismatch, :export, "PowerIO construction changed $label identities")
        mapped
    end
    check(length(n.buses), length(data["bus"]), "bus count")
    buses = Dict(b.id => b for b in n.buses)
    check(length(buses), length(data["bus"]), "bus identities")
    for (id, e) in data["bus"]
        b = get(buses, e["bus_i"], nothing)
        isnothing(b) && D._io_error(:export_construction_mismatch, :export, "missing bus $id")
        for (actual, key) in ((b.vm_pu,"vm"), (deg2rad(b.va_degrees),"va"),
            (b.vmin_pu,"vmin"), (b.vmax_pu,"vmax"), (b.base_kv,"base_kv"),
            (b.area,"area"), (b.zone,"zone"))
            check(actual, e[key], "bus $id $key")
        end
        check(b.bus_type == "REF", e["bus_type"] == 3, "bus $id reference")
    end
    generators = rows(n.generators, data["gen"], "generator")
    for (id,e) in data["gen"]
        g = generators[id]
        check(g.bus_id, e["gen_bus"], "generator $id bus")
        check(g.in_service, e["gen_status"] == 1, "generator $id status")
        for (actual,key) in ((g.active_power_mw,"pg"), (g.reactive_power_mvar,"qg"),
            (g.active_power_min_mw,"pmin"), (g.active_power_max_mw,"pmax"),
            (g.reactive_power_min_mvar,"qmin"), (g.reactive_power_max_mvar,"qmax"))
            check(actual/base, e[key], "generator $id $key")
        end
        check(g.machine_base_mva, e["mbase"], "generator $id machine base")
    end
    loads = rows(n.loads, data["load"], "load")
    for (id,e) in data["load"]
        l = loads[id]
        check(l.bus_id, e["load_bus"], "load $id bus")
        check(l.in_service, e["status"] == 1, "load $id status")
        check(l.voltage_model.p_constant_power_mw/base, e["pd"], "load $id P")
        check(l.voltage_model.q_constant_power_mvar/base, e["qd"], "load $id Q")
    end
    shunts = rows(n.shunts, data["shunt"], "shunt")
    for (id,e) in data["shunt"]
        s = shunts[id]
        check(s.bus_id, e["shunt_bus"], "shunt $id bus")
        check(s.in_service, e["status"] == 1, "shunt $id status")
        check(s.conductance_mw/base, e["gs"], "shunt $id G")
        check(s.susceptance_mvar/base, e["bs"], "shunt $id B")
    end
    branches = rows(n.branches, data["branch"], "branch")
    for (id,e) in data["branch"]
        b = branches[id]
        for (actual,key) in ((b.from_bus_id,"f_bus"), (b.to_bus_id,"t_bus"),
            (b.resistance_pu,"br_r"), (b.reactance_pu,"br_x"),
            (b.from_conductance_pu,"g_fr"), (b.to_conductance_pu,"g_to"),
            (b.from_susceptance_pu,"b_fr"), (b.to_susceptance_pu,"b_to"),
            (b.effective_tap_ratio,"tap"), (deg2rad(b.phase_shift_degrees),"shift"),
            (b.rate_a_mva/base,"rate_a"))
            check(actual, e[key], "branch $id $key")
        end
        check(b.in_service, e["br_status"] == 1, "branch $id status")
    end
    # Independently check the four terminal coefficients, including tap and
    # charging placement; table comparisons above also cover out-of-service rows.
    actual = P.calc_branch_admittances(n)
    expected = [D._branch_admittances(b) for b in c.network.branches if b.available]
    check(length(actual), length(expected), "terminal admittance count")
    for (a,e) in zip(actual, expected), (x,y) in zip(a,e)
        isapprox(x,y; atol=1e-12,rtol=1e-10) ||
            D._io_error(:export_construction_mismatch,:export,"PowerIO construction changed terminal admittance")
    end
    nothing
end
