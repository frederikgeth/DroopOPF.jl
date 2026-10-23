#!/usr/bin/env python3
"""Expand PMSC IEEE-14 OPF/SCOPF JSON results into threshold and margin tables."""
import csv
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CASE_DIR = ROOT / "test" / "data" / "arpae" / "c1_network01"
RESULTS = CASE_DIR / "results"


def read_json(path):
    return json.loads(path.read_text())


def write_csv(path, rows):
    if not rows:
        return
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def result_for(case_name):
    out = RESULTS / case_name
    network = read_json(out / "network_model.json")
    opf = read_json(out / "opf_ac.json")
    scopf = read_json(out / "scopf_ac.json")
    base = network["baseMVA"]
    solution = opf["solution"]

    buses = network["bus"]
    bus_rows = []
    for key, bus in sorted(buses.items(), key=lambda kv: int(kv[0])):
        solved = solution["bus"].get(key, {})
        vm = solved.get("vm")
        bus_rows.append({
            "bus_id": key, "name": bus.get("name", "").strip(),
            "bus_type": bus.get("bus_type"), "in_service_solution": key in solution["bus"],
            "vm_pu": vm, "vmin_pu": bus.get("vmin"), "vmax_pu": bus.get("vmax"),
            "margin_to_vmin_pu": None if vm is None else vm - bus.get("vmin", 0),
            "margin_to_vmax_pu": None if vm is None else bus.get("vmax", 0) - vm,
        })
    write_csv(out / "bus_voltage.csv", bus_rows)

    gen_rows = []
    for key, gen in sorted(network["gen"].items(), key=lambda kv: int(kv[0])):
        solved = solution["gen"].get(key, {})
        pg, qg = solved.get("pg"), solved.get("qg")
        pmin, pmax = gen.get("pmin"), gen.get("pmax")
        qmin, qmax = gen.get("qmin"), gen.get("qmax")
        gen_rows.append({
            "gen_id": key, "bus_id": gen.get("gen_bus"), "source_id": gen.get("source_id"),
            "in_service": bool(gen.get("gen_status", 0)), "pg_mw": None if pg is None else pg * base,
            "pmin_mw": None if pmin is None else pmin * base, "pmax_mw": None if pmax is None else pmax * base,
            "margin_to_pmin_mw": None if pg is None or pmin is None else (pg-pmin) * base,
            "margin_to_pmax_mw": None if pg is None or pmax is None else (pmax-pg) * base,
            "qg_mvar": None if qg is None else qg * base,
            "qmin_mvar": None if qmin is None else qmin * base, "qmax_mvar": None if qmax is None else qmax * base,
            "margin_to_qmin_mvar": None if qg is None or qmin is None else (qg-qmin) * base,
            "margin_to_qmax_mvar": None if qg is None or qmax is None else (qmax-qg) * base,
        })
    write_csv(out / "generator_solution.csv", gen_rows)

    branch_rows, transformer_rows = [], []
    branch_solution = solution["branch"]
    for key, branch in sorted(network["branch"].items(), key=lambda kv: int(kv[0])):
        solved = branch_solution.get(key, {})
        pf, qf = solved.get("pf"), solved.get("qf")
        pt, qt = solved.get("pt"), solved.get("qt")
        flow = None if pf is None or qf is None else max(math.hypot(pf, qf), math.hypot(pt, qt)) * base
        rate = branch.get("rate_a")
        angle_from = solution["bus"].get(str(branch["f_bus"]), {}).get("va")
        angle_to = solution["bus"].get(str(branch["t_bus"]), {}).get("va")
        angle = None if angle_from is None or angle_to is None else angle_from-angle_to
        angmin, angmax = branch.get("angmin"), branch.get("angmax")
        row = {
            "branch_id": key, "from_bus": branch.get("f_bus"), "to_bus": branch.get("t_bus"),
            "source_id": branch.get("source_id"), "transformer": bool(branch.get("transformer", False)),
            "in_service": bool(branch.get("br_status", 0)),
            "pf_mw": None if pf is None else pf*base, "qf_mvar": None if qf is None else qf*base,
            "pt_mw": None if pt is None else pt*base, "qt_mvar": None if qt is None else qt*base,
            "max_end_flow_mva": flow,
            "rate_a_mva": None if rate is None else rate*base,
            "rate_b_mva": None if branch.get("rate_b") is None else branch["rate_b"]*base,
            "rate_c_mva": None if branch.get("rate_c") is None else branch["rate_c"]*base,
            "margin_to_rate_a_mva": None if flow is None or rate is None else rate*base-flow,
            "loading_rate_a_pct": None if flow is None or not rate else 100*flow/(rate*base),
            "angle_difference_deg": None if angle is None else math.degrees(angle),
            "angle_min_deg": None if angmin is None else math.degrees(angmin),
            "angle_max_deg": None if angmax is None else math.degrees(angmax),
            "margin_to_angle_min_deg": None if angle is None or angmin is None else math.degrees(angle-angmin),
            "margin_to_angle_max_deg": None if angle is None or angmax is None else math.degrees(angmax-angle),
            "tap_ratio": branch.get("tap"),
        }
        branch_rows.append(row)
        if row["transformer"]:
            transformer_rows.append(row.copy())
    write_csv(out / "branch_solution.csv", branch_rows)
    write_csv(out / "transformer_solution.csv", transformer_rows)

    shunt_rows = []
    for key, shunt in sorted(network["shunt"].items(), key=lambda kv: int(kv[0])):
        shunt_rows.append({
            "shunt_id": key, "bus_id": shunt.get("shunt_bus"),
            "source_id": shunt.get("source_id"), "kind": "switched" if shunt.get("dispatchable", False) else "fixed",
            "in_service": bool(shunt.get("status", 0)), "g_pu": shunt.get("gs"), "b_pu": shunt.get("bs"),
            "bmin_pu": shunt.get("bmin"), "bmax_pu": shunt.get("bmax"),
            "initial_block_b1": shunt.get("b1"), "initial_blocks_n1": shunt.get("n1"),
            "setting": "fixed at source value in OPF/SCOPF reference",
        })
    write_csv(out / "shunt_data.csv", shunt_rows)

    online_buses = [x for x in bus_rows if x["vm_pu"] is not None]
    online_gens = [x for x in gen_rows if x["in_service"]]
    online_branches = [x for x in branch_rows if x["in_service"]]
    online_transformers = [x for x in transformer_rows if x["in_service"]]
    active_shunts = [x for x in shunt_rows if x["in_service"]]
    vmin_bus = min(online_buses, key=lambda r: r["vm_pu"])
    vmax_bus = max(online_buses, key=lambda r: r["vm_pu"])
    closest_flow = min((x for x in online_branches if x["margin_to_rate_a_mva"] is not None), key=lambda r: r["margin_to_rate_a_mva"])
    highest_loading = max((x for x in online_branches if x["loading_rate_a_pct"] is not None), key=lambda r: r["loading_rate_a_pct"])
    highest_transformer_loading = max((x for x in online_transformers if x["loading_rate_a_pct"] is not None), key=lambda r: r["loading_rate_a_pct"])
    closest_angle = min(
        (x for x in online_branches if x["margin_to_angle_min_deg"] is not None),
        key=lambda r: min(r["margin_to_angle_min_deg"], r["margin_to_angle_max_deg"]),
    )
    closest_pmin = min(online_gens, key=lambda r: r["margin_to_pmin_mw"])
    closest_pmax = min(online_gens, key=lambda r: r["margin_to_pmax_mw"])
    closest_qmin = min(online_gens, key=lambda r: r["margin_to_qmin_mvar"])
    closest_qmax = min(online_gens, key=lambda r: r["margin_to_qmax_mvar"])
    summary = {
        "case": case_name, "base_mva": base,
        "counts": {
            "bus_records": len(buses), "buses_with_solution": len(online_buses),
            "generator_records": len(gen_rows), "online_generators": len(online_gens),
            "branch_records": len(branch_rows), "online_branches": len(online_branches),
            "transformer_records": len(transformer_rows), "online_transformers": len(online_transformers),
            "fixed_shunt_records": sum(x["kind"] == "fixed" for x in shunt_rows),
            "switched_shunt_records": sum(x["kind"] == "switched" for x in shunt_rows),
            "shunts_in_service": len(active_shunts),
        },
        "limits": {
            "bus_vmin_pu": min(b["vmin"] for b in buses.values()),
            "bus_vmax_pu": max(b["vmax"] for b in buses.values()),
            "branch_thermal_basis": "Rate A; apparent flow checked at both ends",
            "branch_angle_limits": "from each branch record, generally +/-60 degrees",
        },
        "opf": {"status": opf["termination_status"], "objective": opf["objective"]},
        "scopf": {"status": scopf["termination_status"], "objective": scopf["objective"], "iterations": scopf.get("iterations")},
        "margins": {
            "min_voltage": {k: vmin_bus[k] for k in ["bus_id", "vm_pu", "vmin_pu", "margin_to_vmin_pu"]},
            "max_voltage": {k: vmax_bus[k] for k in ["bus_id", "vm_pu", "vmax_pu", "margin_to_vmax_pu"]},
            "closest_rate_a": {k: closest_flow[k] for k in ["branch_id", "from_bus", "to_bus", "max_end_flow_mva", "rate_a_mva", "margin_to_rate_a_mva", "loading_rate_a_pct"]},
            "highest_rate_a_loading": {k: highest_loading[k] for k in ["branch_id", "from_bus", "to_bus", "transformer", "max_end_flow_mva", "rate_a_mva", "margin_to_rate_a_mva", "loading_rate_a_pct"]},
            "highest_transformer_rate_a_loading": {k: highest_transformer_loading[k] for k in ["branch_id", "from_bus", "to_bus", "max_end_flow_mva", "rate_a_mva", "margin_to_rate_a_mva", "loading_rate_a_pct"]},
            "closest_branch_angle_bound": {k: closest_angle[k] for k in ["branch_id", "from_bus", "to_bus", "angle_difference_deg", "angle_min_deg", "angle_max_deg", "margin_to_angle_min_deg", "margin_to_angle_max_deg"]},
            "closest_pmin": {k: closest_pmin[k] for k in ["gen_id", "bus_id", "pg_mw", "pmin_mw", "margin_to_pmin_mw"]},
            "closest_pmax": {k: closest_pmax[k] for k in ["gen_id", "bus_id", "pg_mw", "pmax_mw", "margin_to_pmax_mw"]},
            "closest_qmin": {k: closest_qmin[k] for k in ["gen_id", "bus_id", "qg_mvar", "qmin_mvar", "margin_to_qmin_mvar"]},
            "closest_qmax": {k: closest_qmax[k] for k in ["gen_id", "bus_id", "qg_mvar", "qmax_mvar", "margin_to_qmax_mvar"]},
        },
        "equipment_control_policy": "Transformer taps and shunt settings fixed to source-case values in all states; no movement budget.",
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(case_name, json.dumps(summary, indent=2))


if __name__ == "__main__":
    result_for("scenario_01")
    result_for("scenario_01_pmin0")
