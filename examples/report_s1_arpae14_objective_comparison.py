from pathlib import Path
import json
root=Path(__file__).resolve().parents[1];out=root/'artifacts/s1_arpae14_objective_comparison'
rows=[json.loads(x) for x in (out/'rows.jsonl').read_text().splitlines()]
assert len(rows)==len({r['name'] for r in rows})==90
assert not any('error' in r for r in rows)
assert all(r['valid'] for r in json.loads((out/'precursors.json').read_text()))
objectives=['dispatch','loss','cost'];factors=[.9,.95,1.,1.05,1.1]
lines=['# S1 14-bus objective comparison','',
'Fixed uniform-8% shifted-zero-Q droops, original nominal loss-OPF-calibrated references, no deadband, source taps/shunts, study Pmin=0 and symmetric Q limits. Five demand levels, cost/loss demand-matched OPF initial states, Ipopt/MadNLP/CCOpt. No flat starts, no controller recalibration and no free controls.','',
'60 new loss/cost solves plus 30 reused dispatch-deviation solves. All objectives have the same physical feasible set and retain baseline feasibility witnesses. The budget is 600 iterations/20 native solver seconds; smooth voltage and absolute-Q epsilon 1e-6 pu; tight exact CCOpt profile.','',
'- Dispatch: sum((Pg−Pg_initial)^2 + 0.001(Qg−Qg_initial)^2), with fixed case reference dispatch.\n- Loss: sum(Pg)−sum(Pd), in pu; reported losses multiply by baseMVA.\n- Cost: source convex piecewise-linear generation cost, including first/last-segment extrapolation where study bounds extend beyond source knots. Convexity is checked. The optimizer minimizes cost/100000 for numerical scaling; tables report unscaled source cost units. This positive scaling preserves the mathematical minimizer but can affect numerical stopping behavior.','',
'All ten source OPFs passed physical checks and independent objective replay against their saved objectives. Saved economic OPF epigraph values differ from direct curve evaluation by approximately 0.0029 source cost units; source cost replay allows 0.01 absolute units plus 1e-6 relative tolerance, while source loss replay uses 1e-6 absolute/relative tolerance. This small source numerical discrepancy is retained, not treated as a change in the cost model. Physical gates and objective replay are separate. The same final state supplies all three performance metrics in each table row.','',
'## Solver acceptance','', '| Objective | Ipopt | MadNLP | CCOpt | Physically verified |','|---|---:|---:|---:|---:|']
for obj in objectives:
 rs=[r for r in rows if r['tags']['objective']==obj];ns=[sum(r['accepted'] for r in rs if r['solver']==s) for s in ['ipopt','madnlp','ccopt']]
 lines.append(f"| {obj} | {ns[0]}/10 | {ns[1]}/10 | {ns[2]}/10 | {sum(r['point_pass'] for r in rs)}/30 |")
lines+=['','## Best accepted point for each objective and demand','',
'Each row selects the smallest independently recomputed requested objective among six direct runs. These are best-found local points, not global optima. Cost uses source units, not an assumed currency/time unit.','',
'| Demand | Objective | Dispatch deviation | Loss MW | Generation cost | Vmax margin pu | Thermal margin MVA |','|---|---|---:|---:|---:|---:|---:|']
best=[]
for f in factors:
 for obj in objectives:
  rs=[r for r in rows if r['tags']['factor']==f and r['tags']['objective']==obj and r['accepted']]
  if not rs:continue
  r=min(rs,key=lambda r:r['objective_recomputed']);a=r['point_checks']['physical'];thermal=min(b['thermal_margin_mva'] for b in r['branches'] if b['thermal_margin_mva'] is not None)
  best.append(dict(factor=f,objective=obj,name=r['name'],dispatch_deviation=r['dispatch_deviation'],loss_mw=r['loss_mw'],economic_cost=r['economic_cost'],voltage_upper_margin=a['voltage_max_margin'],thermal_margin_mva=thermal))
  lines.append(f"| {f:.0%} | {obj} | {r['dispatch_deviation']:.7g} | {r['loss_mw']:.6f} | {r['economic_cost']:.3f} | {a['voltage_max_margin']:.3g} | {thermal:.3g} |")
lines+=['','## Generator margins at the same selected points','', '| Demand | Objective | Pg−Pmin MW | Pmax−Pg MW | Qg−Qmin MVAr | Qmax−Qg MVAr |','|---|---|---:|---:|---:|---:|']
lookup={r['name']:r for r in rows}
for b in best:
 gs=[g for g in lookup[b['name']]['generators'] if g['available']]
 ms=[min(g[a]-g[z] for g in gs) for a,z in [('pg_mw','pmin_mw'),('pmax_mw','pg_mw'),('qg_mvar','qmin_mvar'),('qmax_mvar','qg_mvar')]]
 lines.append(f"| {b['factor']:.0%} | {b['objective']} | "+' | '.join(f'{v:.5g}' for v in ms)+' |')
lines+=['','## Direct failures','', '| Run | Status | Physical witness |','|---|---|---|']
failed=[r for r in rows if not r['accepted']]
for r in failed:lines.append(f"| {r['name']} | {r.get('solver_status')} | {r['point_pass']} |")
if not failed:lines.append('| None | — | — |')
lines+=['','## S1 decision','',
'Keep the same loss-OPF-calibrated uniform-8% controller as the common fixed-controls baseline. Objective changes did not require a new controller: Ipopt and MadNLP each accepted all 30 objective/demand/start cells. All 11 failures are CCOpt iteration limits on known-feasible physical models; the cost lane also adds a scaled PWL epigraph, so this is not an isolated benchmark of solver quality.','',
'At nominal demand, dispatch deviation gives 7.295622 MW losses and 94207.130 source cost units; loss minimization gives 0.629822 MW and 29444.435; cost minimization gives 3.896178 MW and 4095.989. Reducing dispatch deviation is not an efficiency or economic objective. The loss-OPF anchor used for calibration does not force the subsequent S1 solve to minimize losses.','',
'The active constraints change as well: at nominal demand, dispatch deviation binds line 2; loss minimization binds line 11 and the bus-6 voltage ceiling; cost minimization has about 16 MVA minimum thermal headroom but still binds bus 6 at 1.1 pu. Loss minimization therefore does not universally create thermal headroom, and cost minimization does not eliminate voltage saturation.','',
'For the remaining S1 studies, retain dispatch deviation as the historical solver-regression lane, use source generation cost for the economic-performance lane, and retain active-loss minimization as the efficiency comparator. Keep the calibration objective separate and unchanged. Compare free controls under those performance objectives before attributing physical value to slope/tap tuning; then select common settings using feasibility across all demand scenarios, not nominal objective alone. Report all three metrics and limit margins for every candidate. Finally rerun the qualified workflow under original generator limits before transferring to 500 buses.','',
'These best-found local points establish achievable performance and feasibility, not global optimality, dynamic security or guaranteed behavior between sampled demand levels.','']
lines+=['','Every physical model here is known feasible from the retained dispatch baseline. A failed direct solve is not evidence of physical infeasibility. Detailed bus/generator/branch limits, flows, residuals and all three objective metrics are saved per run in rows.jsonl. Independent saved-state replay is recorded in serialization_audit.json.','']
(out/'report.md').write_text('\n'.join(lines))
summary=dict(cells=90,new_solves=60,reused=30,verified=sum(r['point_pass'] for r in rows),accepted=sum(r['accepted'] for r in rows),best=best)
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print('\n'.join(lines[:lines.index('## Generator margins at the same selected points')]))
