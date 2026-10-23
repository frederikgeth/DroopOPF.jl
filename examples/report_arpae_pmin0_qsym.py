#!/usr/bin/env python3
"""Report OPF thresholds and margins for the 14/500-bus Pmin0-Qsym variants."""
import csv
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "test/data/arpae/c1_network01/results"
CASES = ("scenario_01_pmin0_qsym", "scenario_02_pmin0_qsym")


def write_csv(path, rows):
    if rows:
        with path.open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)


def report(case):
    out = BASE / case
    network = json.loads((out / "network_model.json").read_text())
    opf = json.loads((out / "opf_ac.json").read_text())
    sol = opf["solution"]
    base = network["baseMVA"]
    bus_rows, gen_rows, branch_rows, transformer_rows, shunt_rows = [], [], [], [], []
    limit_path = ROOT / "test/data/arpae/c1_network01" / case / "generator_limits_original_and_study.csv"
    original_limits = {}
    with limit_path.open(newline="") as f:
        for row in csv.DictReader(f):
            original_limits[(row["bus"].strip(), row["id"].strip())] = row

    for key, bus in sorted(network["bus"].items(), key=lambda kv: int(kv[0])):
        solved = sol["bus"].get(key, {})
        vm = solved.get("vm")
        bus_rows.append({"bus_id": key, "name": bus.get("name", "").strip(), "in_service": vm is not None,
                         "vm_pu": vm, "vmin_pu": bus["vmin"], "vmax_pu": bus["vmax"],
                         "margin_to_vmin_pu": None if vm is None else vm-bus["vmin"],
                         "margin_to_vmax_pu": None if vm is None else bus["vmax"]-vm})

    for key, gen in sorted(network["gen"].items(), key=lambda kv: int(kv[0])):
        solved = sol["gen"].get(key, {})
        pg, qg = solved.get("pg"), solved.get("qg")
        source = gen.get("source_id", [None, gen["gen_bus"], "1"])
        original = original_limits[(str(source[1]), str(source[2]).strip())]
        gen_rows.append({"gen_id": key, "bus_id": gen["gen_bus"], "in_service": bool(gen["gen_status"]),
                         "pg_mw": None if pg is None else pg*base,
                         "pmin_mw": gen["pmin"]*base, "pmax_mw": gen["pmax"]*base,
                         "margin_to_pmin_mw": None if pg is None else (pg-gen["pmin"])*base,
                         "margin_to_pmax_mw": None if pg is None else (gen["pmax"]-pg)*base,
                         "qg_mvar": None if qg is None else qg*base,
                         "qmin_mvar": gen["qmin"]*base, "qmax_mvar": gen["qmax"]*base,
                         "margin_to_qmin_mvar": None if qg is None else (qg-gen["qmin"])*base,
                         "margin_to_qmax_mvar": None if qg is None else (gen["qmax"]-qg)*base,
                         "pmin_original_mw": float(original["pmin_original_mw"]),
                         "pmax_original_mw": float(original["pmax_original_mw"]),
                         "qmin_original_mvar": float(original["qmin_original_mvar"]),
                         "qmax_original_mvar": float(original["qmax_original_mvar"]),
                         "margin_to_original_pmin_mw": None if pg is None else pg*base-float(original["pmin_original_mw"]),
                         "margin_to_original_pmax_mw": None if pg is None else float(original["pmax_original_mw"])-pg*base,
                         "margin_to_original_qmin_mvar": None if qg is None else qg*base-float(original["qmin_original_mvar"]),
                         "margin_to_original_qmax_mvar": None if qg is None else float(original["qmax_original_mvar"])-qg*base})

    for key, branch in sorted(network["branch"].items(), key=lambda kv: int(kv[0])):
        solved = sol["branch"].get(key, {})
        flow = None
        if solved:
            flow = max(math.hypot(solved["pf"], solved["qf"]), math.hypot(solved["pt"], solved["qt"]))*base
        rating = branch["rate_a"]*base
        rating_b = branch["rate_b"]*base
        rating_c = branch["rate_c"]*base
        va = None
        if str(branch["f_bus"]) in sol["bus"] and str(branch["t_bus"]) in sol["bus"]:
            va = math.degrees(sol["bus"][str(branch["f_bus"])]["va"]-sol["bus"][str(branch["t_bus"])]["va"])
        row = {"branch_id": key, "from_bus": branch["f_bus"], "to_bus": branch["t_bus"],
               "transformer": bool(branch.get("transformer", False)), "in_service": bool(branch["br_status"]),
               "max_end_flow_mva": flow, "rate_a_mva": rating,
               "rate_b_mva": rating_b, "rate_c_mva": rating_c,
               "margin_to_rate_a_mva": None if flow is None else rating-flow,
               "loading_rate_a_pct": None if flow is None or rating == 0 else 100*flow/rating,
               "angle_difference_deg": va, "angle_min_deg": math.degrees(branch["angmin"]),
               "angle_max_deg": math.degrees(branch["angmax"]),
               "margin_to_angle_min_deg": None if va is None else va-math.degrees(branch["angmin"]),
               "margin_to_angle_max_deg": None if va is None else math.degrees(branch["angmax"])-va,
               "tap_ratio": branch.get("tap")}
        branch_rows.append(row)
        if row["transformer"]:
            transformer_rows.append(row.copy())

    for key, shunt in sorted(network["shunt"].items(), key=lambda kv: int(kv[0])):
        shunt_rows.append({"shunt_id": key, "bus_id": shunt.get("shunt_bus"),
                           "kind": "switched" if shunt.get("dispatchable", False) else "fixed",
                           "in_service": bool(shunt.get("status", 0)), "b_pu": shunt.get("bs"),
                           "bmin_pu": shunt.get("bmin"), "bmax_pu": shunt.get("bmax"),
                           "setting": "fixed at source value"})

    for filename, rows in (("bus_voltage.csv", bus_rows), ("generator_solution.csv", gen_rows),
                           ("branch_solution.csv", branch_rows), ("transformer_solution.csv", transformer_rows),
                           ("shunt_data.csv", shunt_rows)):
        write_csv(out / filename, rows)

    live_buses = [x for x in bus_rows if x["in_service"]]
    live_gens = [x for x in gen_rows if x["in_service"] and x["pg_mw"] is not None]
    live_branches = [x for x in branch_rows if x["in_service"] and x["loading_rate_a_pct"] is not None]
    live_transformers = [x for x in transformer_rows if x["in_service"] and x["loading_rate_a_pct"] is not None]
    summary = {
        "case": case, "base_mva": base,
        "counts": {"bus_records": len(bus_rows), "buses_solved": len(live_buses),
                   "generator_records": len(gen_rows), "online_generators": sum(x["in_service"] for x in gen_rows),
                   "branch_records": len(branch_rows), "online_branches": sum(x["in_service"] for x in branch_rows),
                   "transformer_records": len(transformer_rows), "online_transformers": sum(x["in_service"] for x in transformer_rows),
                   "fixed_shunts": sum(x["kind"] == "fixed" for x in shunt_rows),
                   "switched_shunts": sum(x["kind"] == "switched" for x in shunt_rows)},
        "thresholds": {"vmin_pu": min(x["vmin_pu"] for x in bus_rows), "vmax_pu": max(x["vmax_pu"] for x in bus_rows),
                       "branch_loading": "apparent flow at the more heavily loaded end against Rate A; Rate B/C and angle limits in CSV"},
        "opf": {"status": opf["termination_status"], "objective": opf["objective"]},
        "scopf": None,
        "margins": {
            "lowest_voltage": min(live_buses, key=lambda x: x["vm_pu"]),
            "highest_voltage": max(live_buses, key=lambda x: x["vm_pu"]),
            "highest_rate_a_loading": max(live_branches, key=lambda x: x["loading_rate_a_pct"]),
            "highest_transformer_rate_a_loading": max(live_transformers, key=lambda x: x["loading_rate_a_pct"]),
            "closest_pmin": min(live_gens, key=lambda x: x["margin_to_pmin_mw"]),
            "closest_pmax": min(live_gens, key=lambda x: x["margin_to_pmax_mw"]),
            "closest_qmin": min(live_gens, key=lambda x: x["margin_to_qmin_mvar"]),
            "closest_qmax": min(live_gens, key=lambda x: x["margin_to_qmax_mvar"]),
        },
        "equipment": "Transformer taps and shunts fixed at source values during OPF.",
    }
    scopf_path = out / "scopf_ac.json"
    if scopf_path.exists():
        scopf = json.loads(scopf_path.read_text())
        summary["scopf"] = {"status": scopf["termination_status"], "objective": scopf["objective"], "iterations": scopf.get("iterations")}
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(case, json.dumps(summary, indent=2))


if __name__ == "__main__":
    for case_id in CASES:
        report(case_id)
