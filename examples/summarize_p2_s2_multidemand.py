"""Combine only demand witnesses with byte-equivalent shared control values."""
import json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/p2_s2_multidemand_20261022'
load=lambda p:json.loads(Path(p).read_text())
lanes={};groups={}
for name in ('frozen-zero','high-controller-zero','s2-allowance','retuned-allowance'):
    folder=OUT/name
    if not folder.exists():continue
    subprocess.run([sys.executable,'-B',str(ROOT/'examples/report_p2_s2_multidemand.py'),str(folder)],check=True,stdout=subprocess.DEVNULL)
    lane=load(folder/'SUMMARY.json');lanes[name]=lane
    cross=lane.get('cross_demand_audit')
    if not cross:continue
    group=groups.setdefault(cross['controller_sha256'],{})
    for stage in lane['stages']:
        if stage['accepted']:
            for d in stage.get('by_demand',[]):
                if d['factor'] in cross['accepted_factors']:
                    # Prefer the stronger zero-shedding witness if both exist.
                    if d['factor'] not in group or cross['zero_shedding']:
                        group[d['factor']]=dict(d,lane=name,zero_shedding_required=cross['zero_shedding'])
shared=[dict(controller_sha256=k,demands=[v[f] for f in sorted(v)]) for k,v in groups.items() if v]
result=dict(shared_designs=shared,lanes=lanes,
            s2_reference=dict(shared_master=[.9,.95,1.],exhaustive_independent=1.05,nonexhaustive_shedding_allowed_master=1.0625),
            s2_equipment_and_operating_bounds_preserved=True,physical_validation_tolerances_changed=False,
            shedding_caps_mw={name:(0 if load(OUT/name/'protocol.json')['zero_shedding'] else 10) for name in lanes},
            native_stopping_rule_adjusted=True,objective='feasibility only',p2_closed=False,s2_resumed=False)
extension_path=OUT/'free-1065/summary.json'
result['free_curve_extension']=load(extension_path) if extension_path.exists() else None
(OUT/'FINAL_RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
lines=['# P2 500-bus multi-demand results','',
       'One shared controller is required across each listed demand set. Every accepted demand has a fixed preventive base and all 389 connected outages independently validated.','',
       'S2 previously had an accepted shared 90/95/100% master, an exhaustively qualified independent 105% design, and a nonexhaustive six-state 106.25% point using almost 10 MW shedding per tested outage. These are different qualification scopes.','']
for group in shared:
    lines += ['', '## Verified common design '+group['controller_sha256'][:12],'', '| Demand | Connected outages | Maximum DR (MW) | Maximum shedding (MW) | Policy |','|---:|---:|---:|---:|---|']
    for d in group['demands']:
        lines.append(f"| {100*d['factor']:g}% | 389/389 | {d['max_dr_mw']:.5f} | {d['max_shedding_mw']:.5f} | {'Zero shedding' if d['zero_shedding_required'] else 'S2 allowance ≤10 MW'} |")
for name,lane in lanes.items():
    for s in lane['stages']:
        if not s['accepted']:lines += ['',f"{name}: demand {s['factors']} remains {s['status']}. This is not a physical infeasibility certificate."]
if result['free_curve_extension']:
    ext=result['free_curve_extension']
    lines += ['', f"The bounded free-curve 106.5% search: native master accepted={ext['native_master_accepted']}; physically valid candidate available={ext['physical_candidate_available']}. This search alone does not establish exhaustive or multi-demand qualification."]
for name,lane in lanes.items():
    lines += ['', f"{name}: planned demand factors not attempted after stopping: {lane.get('not_attempted_factors',[])}."]
lines += ['', '## Configuration and interpretation','',
          'Exact S2 settings: 131 corrective taps, 11 continuous shunt banks, absolute equipment bounds without extra movement budgets, 102 shared droop parameters within S2 bounds, and stored Pmax proportional active response. The emergency voltage/rating and load-relief limits are unchanged. Continuous controls do not certify discrete switching, actuator timing or transient security.', '',
          'The four-demand joint master timed out twice; its first point passed physical checks but was not counted as accepted. Recovery froze that common candidate controller and solved demand-specific dispatches with fresh exhaustive outage scans. The higher-demand lane instead freezes the original S2 106.25% controller and freshly qualifies all five demands under the original S2 relief allowance. These two controllers remain separate. Raw failed/interrupted attempts remain. Batched scans and a solver restart address computational overhead; completed accepted rows are reused only with independent replay.', '',
          'Native polishing retains strict tol=1e-8 and permits acceptable convergence after one qualifying iteration, with acceptable_tol=1e-6 and acceptable_constr_viol_tol=1e-7. Every returned point still passes the unchanged independent physical gates. This is a feasibility study, not minimum DR/shedding/loss optimization or a controlled speed benchmark.', '',
          'P2 remains open. Security between sampled demands, islanded outages, and transient behavior are outside this finite connected-outage claim. Original S2 evidence and pause status remain unchanged.']
(OUT/'REPORT.md').write_text('\n'.join(lines)+'\n')
print(json.dumps({'shared_factors':[[d['factor'] for d in g['demands']] for g in shared]},indent=2))
