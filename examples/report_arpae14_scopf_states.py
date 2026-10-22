#!/usr/bin/env python3
"""Expand the retained all-contingency IEEE-14 SCOPF solution by state."""
import csv
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "test" / "data" / "arpae" / "c1_network01" / "results"


def read(path):
    return json.loads(path.read_text())


def write_csv(path, rows):
    if rows:
        with path.open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)


def process(case):
    out = RESULTS / case
    network = read(out / "network_model.json")
    opf = read(out / "opf_ac.json")
    reference = read(out / "scopf_ac.json")
    result = read(out / "scopf_ac_all_states.json")
    base = network["baseMVA"]
    limit_path = out.parent.parent / case / "generator_limits_original_and_study.csv"
    if limit_path.exists():
        with limit_path.open(newline="") as stream:
            originals = {(r["bus"].strip(), r["id"].strip()): r for r in csv.DictReader(stream)}
    else:
        originals = {}
    states = {"0": ("base", "none")}
    n = 1
    for c in network.get("gen_contingencies", []):
        states[str(n)] = (c["label"], f"generator outage {c['label']}")
        n += 1
    for c in network.get("branch_contingencies", []):
        states[str(n)] = (c["label"], f"branch outage {c['label']}")
        n += 1

    bus_rows, gen_rows, branch_rows, summaries = [], [], [], []
    for sid, state in sorted(result["solution"]["nw"].items(), key=lambda kv: int(kv[0])):
        label, contingency = states.get(sid, (sid, "unknown"))
        sol_buses = state["bus"]
        volts = []
        for bid, v in sol_buses.items():
            b = network["bus"][bid]
            row = {"state_id": sid, "state": label, "contingency": contingency,
                   "bus_id": bid, "vm_pu": v["vm"], "vmin_pu": b["vmin"], "vmax_pu": b["vmax"],
                   "margin_to_vmin_pu": v["vm"]-b["vmin"], "margin_to_vmax_pu": b["vmax"]-v["vm"]}
            bus_rows.append(row); volts.append(row)
        minv, maxv = min(volts, key=lambda x:x["vm_pu"]), max(volts, key=lambda x:x["vm_pu"])

        gen_margins, gen_pq_violations = [], 0
        for gid, gen in network["gen"].items():
            source_id = gen.get("source_id", [None, gen["gen_bus"], "1"])
            original = originals.get((str(source_id[1]), str(source_id[2]).strip()))
            gsol = state["gen"].get(gid)
            outaged = gsol is None and any(str(c["idx"]) == gid and c["label"] == label for c in network.get("gen_contingencies", []))
            if gsol is None and not outaged:
                continue
            pg = None if gsol is None else gsol.get("pg")
            qg = None if gsol is None else gsol.get("qg")
            pmin, pmax, qmin, qmax = [gen[x] for x in ("pmin", "pmax", "qmin", "qmax")]
            margins = {
                "pmin": None if pg is None else (pg-pmin)*base,
                "pmax": None if pg is None else (pmax-pg)*base,
                "qmin": None if qg is None else (qg-qmin)*base,
                "qmax": None if qg is None else (qmax-qg)*base,
            }
            row = {"state_id": sid, "state": label, "contingency": contingency, "gen_id": gid,
                   "bus_id": gen["gen_bus"], "outaged": outaged,
                   "pg_mw": None if pg is None else pg*base, "pmin_mw": pmin*base, "pmax_mw": pmax*base,
                   "qg_mvar": None if qg is None else qg*base, "qmin_mvar": qmin*base, "qmax_mvar": qmax*base,
                   "margin_to_pmin_mw": margins["pmin"], "margin_to_pmax_mw": margins["pmax"],
                   "margin_to_qmin_mvar": margins["qmin"], "margin_to_qmax_mvar": margins["qmax"],
                   "pmin_original_mw": None if original is None else float(original["pmin_original_mw"]),
                   "pmax_original_mw": None if original is None else float(original["pmax_original_mw"]),
                   "qmin_original_mvar": None if original is None else float(original["qmin_original_mvar"]),
                   "qmax_original_mvar": None if original is None else float(original["qmax_original_mvar"]),
                   "margin_to_original_pmin_mw": None if pg is None or original is None else pg*base-float(original["pmin_original_mw"]),
                   "margin_to_original_pmax_mw": None if pg is None or original is None else float(original["pmax_original_mw"])-pg*base,
                   "margin_to_original_qmin_mvar": None if qg is None or original is None else qg*base-float(original["qmin_original_mvar"]),
                   "margin_to_original_qmax_mvar": None if qg is None or original is None else float(original["qmax_original_mvar"])-qg*base}
            gen_rows.append(row)
            if not outaged:
                gen_margins += [(margins[k], gid, k) for k in margins]
                gen_pq_violations += sum(1 for value in margins.values() if value is not None and value < -1e-4)

        flows = []
        for bid, bsol in state["branch"].items():
            b = network["branch"][bid]
            pf, qf, pt, qt = [bsol[k] for k in ("pf", "qf", "pt", "qt")]
            flow = max(math.hypot(pf,qf), math.hypot(pt,qt))*base
            field = "rate_a" if sid == "0" else "rate_c"
            limit = b[field]*base
            va = sol_buses[str(b["f_bus"])]["va"]-sol_buses[str(b["t_bus"])]["va"]
            angle = math.degrees(va)
            amin, amax = math.degrees(b["angmin"]), math.degrees(b["angmax"])
            row = {"state_id": sid, "state": label, "contingency": contingency, "branch_id": bid,
                   "from_bus": b["f_bus"], "to_bus": b["t_bus"], "transformer": b.get("transformer", False),
                   "flow_mva": flow, "thermal_limit_type": "Rate A" if sid == "0" else "Rate C",
                   "thermal_limit_mva": limit, "margin_to_thermal_limit_mva": limit-flow,
                   "loading_pct": 100*flow/limit if limit else None, "angle_difference_deg": angle,
                   "angle_min_deg": amin, "angle_max_deg": amax,
                   "margin_to_angle_min_deg": angle-amin, "margin_to_angle_max_deg": amax-angle}
            branch_rows.append(row); flows.append(row)
        maxflow = max(flows, key=lambda x:x["loading_pct"])
        closest_pg = min((x for x in gen_margins if x[2].startswith("p")), key=lambda x:x[0])
        closest_qg = min((x for x in gen_margins if x[2].startswith("q")), key=lambda x:x[0])
        summaries.append({"state_id": sid, "state": label, "contingency": contingency,
                          "lowest_vm_bus": minv["bus_id"], "lowest_vm_pu": minv["vm_pu"],
                          "margin_to_vmin_pu": minv["margin_to_vmin_pu"], "highest_vm_bus": maxv["bus_id"],
                          "highest_vm_pu": maxv["vm_pu"], "margin_to_vmax_pu": maxv["margin_to_vmax_pu"],
                          "max_loading_branch": maxflow["branch_id"], "max_loading_pct": maxflow["loading_pct"],
                          "max_flow_mva": maxflow["flow_mva"], "thermal_limit_mva": maxflow["thermal_limit_mva"],
                          "closest_p_bound_gen": closest_pg[1], "closest_p_bound": closest_pg[2], "p_margin_mw": closest_pg[0],
                          "closest_q_bound_gen": closest_qg[1], "closest_q_bound": closest_qg[2], "q_margin_mvar": closest_qg[0],
                          "generator_pq_violations_over_1e-4": gen_pq_violations})

    write_csv(out / "scopf_bus_scenarios.csv", bus_rows)
    write_csv(out / "scopf_generator_scenarios.csv", gen_rows)
    write_csv(out / "scopf_branch_scenarios.csv", branch_rows)
    write_csv(out / "scopf_scenario_summary.csv", summaries)
    report = {"case": case, "base_mva": base,
              "fixed_point_scopf": {"status": reference["termination_status"], "objective": reference["objective"], "iterations": reference.get("iterations")},
              "all_declared_contingencies_master": {"status": result["termination_status"], "objective": result["objective"],
                  "objective_difference_vs_fixed_point": result["objective"]-reference["objective"],
                  "matches_fixed_point_within_1e-3": abs(result["objective"]-reference["objective"]) < 1e-3},
              "opf_objective": opf["objective"], "states": summaries}
    (out / "scopf_all_states_summary.json").write_text(json.dumps(report, indent=2)+"\n")
    print(case, json.dumps(report, indent=2))


if __name__ == "__main__":
    process("scenario_01")
    process("scenario_01_pmin0")
    process("scenario_01_pmin0_qsym")
