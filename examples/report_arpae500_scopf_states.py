#!/usr/bin/env python3
"""Report state-by-state 500-bus PMSC SCOPF thresholds and limit margins."""
import csv
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "test/data/arpae/c1_network01/results/scenario_02_pmin0_qsym"
STATE_NAMES = {
    "0": ("base", "no outage"),
    "1": ("G_000017SENECA33U1", "generator outage G_000017SENECA33U1"),
    "2": ("L_000162IRMO0-000220UNION30C1", "branch outage L_000162IRMO0-000220UNION30C1"),
    "3": ("L_000246BLACKSBURG10-000332CONVERSE0C1", "branch outage L_000246BLACKSBURG10-000332CONVERSE0C1"),
    "4": ("T_000247BLACKSBURG11-000246BLACKSBURG10C1", "transformer outage T_000247BLACKSBURG11-000246BLACKSBURG10C1"),
}


def write(name, rows):
    with (OUT / name).open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)


def main():
    net = json.loads((OUT / "network_model.json").read_text())
    opf = json.loads((OUT / "opf_ac.json").read_text())
    fixed = json.loads((OUT / "scopf_ac.json").read_text())
    result = json.loads((OUT / "scopf_ac_all_states.json").read_text())
    base = net["baseMVA"]
    case_dir = ROOT / "test/data/arpae/c1_network01/scenario_02_pmin0_qsym"
    with (case_dir / "generator_limits_original_and_study.csv").open(newline="") as stream:
        originals = {(r["bus"].strip(), r["id"].strip()): r for r in csv.DictReader(stream)}
    bus_rows, gen_rows, branch_rows, summary_rows = [], [], [], []
    for sid, state in sorted(result["solution"]["nw"].items(), key=lambda kv: int(kv[0])):
        label, contingency = STATE_NAMES[sid]
        state_bus, state_gen, state_branch = state["bus"], state["gen"], state["branch"]
        voltage = []
        for bid, solved in state_bus.items():
            bus = net["bus"][bid]
            vm = solved["vm"]
            row = {"state_id": sid, "state": label, "contingency": contingency, "bus_id": bid,
                   "vm_pu": vm, "vmin_pu": bus["vmin"], "vmax_pu": bus["vmax"],
                   "margin_to_vmin_pu": vm-bus["vmin"], "margin_to_vmax_pu": bus["vmax"]-vm}
            voltage.append(row); bus_rows.append(row)
        minv = min(voltage, key=lambda x: x["vm_pu"])
        maxv = max(voltage, key=lambda x: x["vm_pu"])
        generator_margins, gen_violations = [], 0
        for gid, gen in net["gen"].items():
            solved = state_gen.get(gid)
            if solved is None:
                continue
            source_id = gen.get("source_id", [None, gen["gen_bus"], "1"])
            original = originals[(str(source_id[1]), str(source_id[2]).strip())]
            pg, qg = solved["pg"]*base, solved["qg"]*base
            pmin, pmax = gen["pmin"]*base, gen["pmax"]*base
            qmin, qmax = gen["qmin"]*base, gen["qmax"]*base
            margins = {"pmin": pg-pmin, "pmax": pmax-pg, "qmin": qg-qmin, "qmax": qmax-qg}
            gen_violations += sum(x < -1e-4 for x in margins.values())
            generator_margins.extend((v, gid, key) for key, v in margins.items())
            row = {"state_id": sid, "state": label, "contingency": contingency, "gen_id": gid,
                   "bus_id": gen["gen_bus"], "outaged": False, "pg_mw": pg, "pmin_mw": pmin,
                   "pmax_mw": pmax, "margin_to_pmin_mw": margins["pmin"], "margin_to_pmax_mw": margins["pmax"],
                   "qg_mvar": qg, "qmin_mvar": qmin, "qmax_mvar": qmax,
                   "margin_to_qmin_mvar": margins["qmin"], "margin_to_qmax_mvar": margins["qmax"],
                   "pmin_original_mw": float(original["pmin_original_mw"]),
                   "pmax_original_mw": float(original["pmax_original_mw"]),
                   "qmin_original_mvar": float(original["qmin_original_mvar"]),
                   "qmax_original_mvar": float(original["qmax_original_mvar"]),
                   "margin_to_original_pmin_mw": pg-float(original["pmin_original_mw"]),
                   "margin_to_original_pmax_mw": float(original["pmax_original_mw"])-pg,
                   "margin_to_original_qmin_mvar": qg-float(original["qmin_original_mvar"]),
                   "margin_to_original_qmax_mvar": float(original["qmax_original_mvar"])-qg}
            gen_rows.append(row)
        online_ids = {gid for gid, gen in net["gen"].items() if gen["gen_status"] > 0}
        if len(state_gen) < len(online_ids):
            outaged = online_ids - set(state_gen)
            for gid in outaged:
                gen = net["gen"][gid]
                source_id = gen.get("source_id", [None, gen["gen_bus"], "1"])
                original = originals[(str(source_id[1]), str(source_id[2]).strip())]
                gen_rows.append({"state_id": sid, "state": label, "contingency": contingency, "gen_id": gid,
                                 "bus_id": gen["gen_bus"], "outaged": True, "pg_mw": None,
                                 "pmin_mw": gen["pmin"]*base, "pmax_mw": gen["pmax"]*base,
                                 "margin_to_pmin_mw": None, "margin_to_pmax_mw": None, "qg_mvar": None,
                                 "qmin_mvar": gen["qmin"]*base, "qmax_mvar": gen["qmax"]*base,
                                 "margin_to_qmin_mvar": None, "margin_to_qmax_mvar": None,
                                 "pmin_original_mw": float(original["pmin_original_mw"]),
                                 "pmax_original_mw": float(original["pmax_original_mw"]),
                                 "qmin_original_mvar": float(original["qmin_original_mvar"]),
                                 "qmax_original_mvar": float(original["qmax_original_mvar"]),
                                 "margin_to_original_pmin_mw": None, "margin_to_original_pmax_mw": None,
                                 "margin_to_original_qmin_mvar": None, "margin_to_original_qmax_mvar": None})

        flows = []
        for bid, solved in state_branch.items():
            branch = net["branch"][bid]
            flow = max(math.hypot(solved["pf"], solved["qf"]), math.hypot(solved["pt"], solved["qt"]))*base
            field = "rate_a" if sid == "0" else "rate_c"
            limit = branch[field]*base
            angles = math.degrees(state_bus[str(branch["f_bus"])]["va"]-state_bus[str(branch["t_bus"])]["va"])
            amin, amax = math.degrees(branch["angmin"]), math.degrees(branch["angmax"])
            row = {"state_id": sid, "state": label, "contingency": contingency, "branch_id": bid,
                   "from_bus": branch["f_bus"], "to_bus": branch["t_bus"],
                   "transformer": bool(branch.get("transformer", False)), "flow_mva": flow,
                   "thermal_limit_type": "Rate A" if sid == "0" else "Rate C", "thermal_limit_mva": limit,
                   "margin_to_thermal_limit_mva": limit-flow, "loading_pct": 100*flow/limit if limit else None,
                   "angle_difference_deg": angles, "angle_min_deg": amin, "angle_max_deg": amax,
                   "margin_to_angle_min_deg": angles-amin, "margin_to_angle_max_deg": amax-angles}
            branch_rows.append(row); flows.append(row)
        maxflow = max(flows, key=lambda x: x["loading_pct"])
        closest_p = min((x for x in generator_margins if x[2].startswith("p")), key=lambda x: x[0])
        closest_q = min((x for x in generator_margins if x[2].startswith("q")), key=lambda x: x[0])
        summary_rows.append({"state_id": sid, "state": label, "contingency": contingency,
                             "lowest_vm_bus": minv["bus_id"], "lowest_vm_pu": minv["vm_pu"],
                             "margin_to_vmin_pu": minv["margin_to_vmin_pu"], "highest_vm_bus": maxv["bus_id"],
                             "highest_vm_pu": maxv["vm_pu"], "margin_to_vmax_pu": maxv["margin_to_vmax_pu"],
                             "max_loading_branch": maxflow["branch_id"], "max_loading_pct": maxflow["loading_pct"],
                             "max_flow_mva": maxflow["flow_mva"], "thermal_limit_type": maxflow["thermal_limit_type"],
                             "thermal_limit_mva": maxflow["thermal_limit_mva"],
                             "closest_p_bound_gen": closest_p[1], "closest_p_bound": closest_p[2], "p_margin_mw": closest_p[0],
                             "closest_q_bound_gen": closest_q[1], "closest_q_bound": closest_q[2], "q_margin_mvar": closest_q[0],
                             "generator_pq_violations_over_1e-4": gen_violations})
    write("scopf_bus_scenarios.csv", bus_rows)
    write("scopf_generator_scenarios.csv", gen_rows)
    write("scopf_branch_scenarios.csv", branch_rows)
    write("scopf_scenario_summary.csv", summary_rows)
    summary = {"case": "scenario_02_pmin0_qsym", "base_mva": base,
               "fixed_point_scopf": {"status": fixed["termination_status"], "objective": fixed["objective"], "iterations": fixed.get("iterations")},
               "all_selected_contingencies_master": {"status": result["termination_status"], "objective": result["objective"],
                   "objective_difference_vs_fixed_point": result["objective"]-fixed["objective"],
                   "matches_fixed_point_within_1e-3": abs(result["objective"]-fixed["objective"]) < 1e-3},
               "opf_objective": opf["objective"], "states": summary_rows,
               "scope_note": "PMSC contingency recourse in this formulation does not enforce generator P/Q capability limits in every outage state; see per-generator state margins."}
    (OUT / "scopf_all_states_summary.json").write_text(json.dumps(summary, indent=2)+"\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
