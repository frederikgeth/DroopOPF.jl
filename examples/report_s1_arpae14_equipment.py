"""Equipment-only S1 scorecard, with explicit reuse and independent replay."""
from pathlib import Path
from collections import defaultdict
import json
root=Path(__file__).resolve().parents[1];out=root/'artifacts/s1_arpae14_equipment'
rows=[json.loads(x) for x in (out/'rows.jsonl').read_text().splitlines()]
assert len(rows)==len({r['name'] for r in rows})==120
assert not any('error' in r for r in rows), 'execution errors need resolution'
assert all(r.get('replayed') for r in rows)
assert len(json.loads((out/'source_precursors.json').read_text()))==10
assert all(r['valid'] for r in json.loads((out/'inherited_witnesses.json').read_text()))
protocol=json.loads((out/'protocol.json').read_text())
families=['fixed','tap','shunt','tap_shunt'];demands=[.9,.95,1.,1.05,1.1]
g=defaultdict(list)
for r in rows:g[r['tags']['family']].append(r)
lines=['# S1 14-bus equipment-only controls','',
'Baseline: nominal loss-OPF calibration, shifted zero-Q droops, uniform 8%, no deadband, Pmin=0 and symmetric Q limits. Five droops remain fixed throughout. The unchanged objective is sum((Pg−Pg_initial)^2 + 0.001(Qg−Qg_initial)^2), using the generator references stored in the case, not the numerical initial state.','',
'90 new equipment solves plus 30 reused fixed-control reference cells; five demands (90/95/100/105/110%), cost/loss demand-matched OPF starts, and Ipopt/MadNLP/CCOpt. No flat starts or contingencies. Smooth voltage and absolute reactive widths are 1e-6 pu; 600 iterations and 20 native solver seconds per direct run. Original results are preserved.','',
'All ten source seeds pass physical precursors. Every fixed-control solution is independently valid in every equipment family (120 inherited-witness checks). Therefore all tested equipment models are already known feasible: a failed direct run is a numerical failure on a model with a retained witness, not evidence of infeasibility.','',
'## Selected equipment','',
'Tap limits below are the declared ±5% source-tap study range, not source nameplate limits. Shunt optimization is continuous susceptance within the bank envelope, not discrete switching. Settings are optimized separately at each demand; this does not establish one common setting for all demands.','',
'| Transformer branch | Lower tap | Source tap | Upper tap |','|---|---:|---:|---:|']
for t in protocol['families']['tap']['tap_controls']:lines.append(f"| {t['branch_id']} | {t['lower']:.6f} | {t['nominal']:.6f} | {t['upper']:.6f} |")
lines+=['','| Shunt bank | Lower B, pu | Upper B, pu |','|---|---:|---:|']
for s in protocol['shunt_bounds']:lines.append(f"| {s['id']} | {s['bounds'][0]:.6f} | {s['bounds'][1]:.6f} |")
lines+=['','## Direct solver results','', '| Free controls | Ipopt accepted | MadNLP accepted | CCOpt accepted | Physical witnesses |','|---|---:|---:|---:|---:|']
for family in families:
 rs=g[family];counts=[sum(r['accepted'] for r in rs if r['solver']==solver) for solver in ('ipopt','madnlp','ccopt')]
 lines.append(f"| {family} | {counts[0]}/10 | {counts[1]}/10 | {counts[2]}/10 | {sum(r['point_pass'] for r in rs)}/30 |")
lines+=['','## Best accepted point per family and demand','',
'The smallest objective among the six direct runs is shown, with that same point used for losses and margins. This is a best-found local result, not a global optimum. Objective improvement is relative to the best accepted fixed-control point at the same demand.','',
'| Demand | Free controls | Objective | Improvement | Loss MW | Min Vmax margin pu | Min thermal margin MVA |','|---|---|---:|---:|---:|---:|---:|']
best=[]
for factor in demands:
 baseline=min((r for r in g['fixed'] if r['tags']['factor']==factor and r['accepted']),key=lambda r:r['objective'])
 for family in families:
  rs=[r for r in g[family] if r['tags']['factor']==factor and r['accepted']]
  if not rs:
   lines.append(f'| {factor:.0%} | {family} | — | — | — | — | — |');continue
  r=min(rs,key=lambda r:r['objective']);a=r['point_checks']['physical']
  change=100*(baseline['objective']-r['objective'])/baseline['objective'] if baseline['objective'] else 0
  thermal=min(b['thermal_margin_mva'] for b in r['branches'] if b['thermal_margin_mva'] is not None)
  best.append(dict(factor=factor,family=family,name=r['name'],objective=r['objective'],improvement_percent=change,loss_mw=r['loss_mw'],voltage_upper_margin=a['voltage_max_margin'],thermal_margin_mva=thermal))
  lines.append(f"| {factor:.0%} | {family} | {r['objective']:.7g} | {change:.2f}% | {r['loss_mw']:.5f} | {a['voltage_max_margin']:.3g} | {thermal:.3g} |")
lines+=['','## Generator limit margins at the reported best points','',
'All values in MW or MVAr. Offline generators are excluded from the minima. Voltage and thermal margins appear above; full angle margins and device values remain in the ledger.','',
'| Demand | Family | Min Pg−Pmin MW | Min Pmax−Pg MW | Min Qg−Qmin MVAr | Min Qmax−Qg MVAr |','|---|---|---:|---:|---:|---:|']
byname={r['name']:r for r in rows}
for b in best:
 r=byname[b['name']];gens=[x for x in r['generators'] if x['available']]
 margins=[min(x[a]-x[z] for x in gens) for a,z in [('pg_mw','pmin_mw'),('pmax_mw','pg_mw'),('qg_mvar','qmin_mvar'),('qmax_mvar','qg_mvar')]]
 lines.append(f"| {b['factor']:.0%} | {b['family']} | "+' | '.join(f'{x:.5g}' for x in margins)+' |')
lines+=['','## Equipment movement ranges across accepted points','', '| Family | Maximum absolute tap change | Maximum absolute B change, pu |','|---|---:|---:|']
for family in families:
 rs=[r for r in g[family] if r['accepted']]
 tap=max((abs(x['delta']) for r in rs for x in r['tap_movements']),default=0)
 shunt=max((abs(x['delta_b']) for r in rs for x in r['shunt_movements']),default=0)
 lines.append(f'| {family} | {tap:.6g} | {shunt:.6g} |')
lines+=['','## Direct runs without solver-accepted feasible points','', '| Run | Native status | Physical point verified |','|---|---|---|']
failed=[r for r in rows if not r['accepted']]
for r in failed:lines.append(f"| {r['name']} | {r.get('solver_status')} | {r['point_pass']} |")
if not failed:lines.append('| None | — | — |')
lines+=['','## Interpretation and next S1 stage','',
'All 120 direct/reference cells pass both solver acceptance and independent physical replay. Free equipment was not needed to recover feasibility on this baseline. Taps reduce the best-found dispatch-deviation objective by 0.67–3.65%; shunt-only results reproduce the fixed-equipment objective to numerical precision, and the joint equipment family reproduces the tap-only result. The available capacitive bank 3 at bus 11 stays effectively at its zero lower bound (largest optimized B below 7e-8 pu). Unavailable bank 4 remains unavailable.','',
'At 100% demand the best fixed-control point has objective 0.5759177 and losses 7.29562 MW; tap optimization gives 0.5700722 and 7.32206 MW. Line 2 remains binding at its 51.6 MVA rating. Buses 6 and 8 reach 1.1 pu, and transformer 20 reaches its declared lower tap bound 0.92055. Transformer taps 19/20/21 are approximately 0.983543/0.920550/0.923013. Better dispatch deviation therefore does not imply lower losses or increased voltage/thermal margin.','',
'The loss-minimizing source OPF supplies controller calibration and initialization; these S1 runs optimize a different objective. Consequently the final S1 losses need not equal the source loss-OPF losses.','',
'Retain fixed controls as the reference, tap-only as the useful equipment comparator, and shunt-only as a tested null-effect comparator for this objective and range. Next run the four droop-design families (droop, tap+droop, shunt+droop, joint), with explicit generator-specific slope bounds and separate reporting of reference movement. Freeze any promising designs and retest across demand before claiming a common controller. Preserve continuous-shunt and exploratory-tap-bound labels. Do not promote equipment freedom as a headroom improvement based on this campaign.','']
lines+=['','Full bus voltage bounds, generator Pg/Qg bounds, branch/transformer ratings and flows, angle limits, tap settings, shunt movements, solver states and gate residuals are retained per run in rows.jsonl. A separate replay from the written ledger is saved in serialization_audit.json. Successful optimization alone does not establish increased headroom or dynamic stability.','']
(out/'report.md').write_text('\n'.join(lines))
(out/'summary.json').write_text(json.dumps(dict(cells=120,new_solves=90,reused_baseline=30,accepted=sum(r['accepted'] for r in rows),verified=sum(r['point_pass'] for r in rows),best=best),indent=2)+'\n')
print('\n'.join(lines[lines.index('## Direct solver results'):lines.index('## Equipment movement ranges across accepted points')]))
