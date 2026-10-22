"""Report direct failed combinations and all unsuccessful retries from saved evidence."""
from pathlib import Path
from collections import defaultdict
import json
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'artifacts/s1_arpae500'
rows={p.stem:json.loads(p.read_text()) for p in sorted((OUT/'attempts').glob('*.json'))}
resolution={r['failed_attempt']:r for r in json.loads((OUT/'failure_resolution.json').read_text())}
groups=defaultdict(list)
for r in rows.values():
 if not r['accepted'] and r['tags']['stage'] in ('frozen','equipment','original_limits'):
  groups[(r['tags']['family'],r['tags']['factor'],r['solver'])].append(r)
labels={'fixed':'None (study limits)','tap':'Taps (study limits)','shunt':'Shunts (study limits)','tap_shunt':'Taps + shunts (study limits)','original_p':'None, original Pmin','original_q':'None, original Q','original_pq':'None, original P and Q'}
records=[]
for (family,factor,solver),failed in sorted(groups.items()):
 candidates=set.intersection(*(set(resolution[r['name']]['same_solver_objective_recovery']) for r in failed))
 candidates=[rows[n] for n in candidates if rows[n]['tags']['stage'] in ('recovery','ccopt_fix') and rows[n]['accepted']]
 candidates.sort(key=lambda r:(r['tags']['stage']!='ccopt_fix',r['name']))
 win=candidates[0] if candidates else None
 fixes=[r['name'] for r in rows.values() if r['tags']['stage']=='original_equipment_fix' and r['tags']['family']==family and r['tags']['factor']==factor and r['accepted']]
 rec=dict(family=family,factor=factor,solver=solver,failed_attempts=[r['name'] for r in failed],initializations=sorted({r['tags'].get('init','') for r in failed}),native_statuses=sorted({r['solver_status'] for r in failed}),recovered_same_model_solver_objective=win is not None,recovery_attempt=win['name'] if win else None,method=win['tags']['method'] if win else 'Unresolved on fixed equipment; no verified infeasibility certificate',seed=win['tags'].get('witness',win['tags'].get('seed')) if win else None,contract=win['contract'] if win else None,changed_equipment_fix_attempts=fixes)
 records.append(rec)
assert len(records)==43 and sum(len(x['failed_attempts']) for x in records)==49
assert sum(x['recovered_same_model_solver_objective'] for x in records)==13
assert sum(len(x['failed_attempts']) for x in records if x['recovered_same_model_solver_objective'])==19
(OUT/'failed_combinations.json').write_text(json.dumps(records,indent=2)+'\n')
lines=['# 500-bus failed combinations and recovery','','Scope: fixed 8% droops, no deadband. Free-droop design was not run. A recovery below requires successful termination and independent physical replay, with the same solver, loss objective and mathematical constraints. Initialization and numerical settings may change; the failed original start is not retroactively counted as passing.','','49 direct unsuccessful attempts form 43 solver/model/demand combinations. The main study has 17 failures across 11 combinations, all recovered. Original-Pmin adds two failures/combinations, both recovered. Original-Q and original-PQ add 30 failed combinations, still unresolved with equipment fixed. Their ten model/demand contracts have separate Ipopt solutions after freeing taps and shunts. These are changed-model fixes, not recoveries of the original fixed-equipment models.','','| Model / free equipment | Demand | Solver | Failed starts | Native outcomes | Same-model recovery | Method / evidence |','|---|---:|---|---|---|---|---|']
for x in records:
 win=rows.get(x['recovery_attempt']);method=x['method']
 if win:
  method+=f"; seed `{x['seed']}`"
  if 'ccopt_mu_init' in win['contract']:method+=f"; initial barrier {win['contract']['ccopt_mu_init']:g}, bound_push=bound_fac=1e-8; {win['contract']['iterations']} iterations/{win['contract']['seconds']:g}s"
  method+=f"; [accepted result](attempts/{win['name']}.json)"
 elif x['changed_equipment_fix_attempts']:
  n=x['changed_equipment_fix_attempts'][0];method+=f'; separate [Ipopt free-equipment fix](attempts/{n}.json)'
 lines.append(f"| {labels[x['family']]} | {x['factor']:.0%} | {x['solver']} | {', '.join(x['initializations'])} ({len(x['failed_attempts'])}) | {', '.join(x['native_statuses'])} | {'Recovered' if win else 'Unresolved'} | {method} |")
lines+=['','## Every unsuccessful attempt, including retries','','There are 61 unsuccessful attempts in total: 49 direct and 12 unsuccessful recovery/tuning attempts. Historical failures are retained. Physical feasibility and native solver acceptance remain separate.','','| Attempt | Stage | Native outcome | Physical witness itself? | Model gate | Same-solver/objective accepted witness exists? |','|---|---|---|---|---|---|']
for name,r in rows.items():
 if r['accepted']:continue
 x=resolution[name]
 lines.append(f"| [{name}](attempts/{name}.json) | {r['tags']['stage']} | {r.get('solver_status','error')} | {r['point_pass']} | {x['model_gate']} | {'Yes' if x['same_solver_objective_recovery'] else 'No'} |")
lines+=['','The 95% CCOpt constant-objective retry is physically valid but has unsuccessful native termination. Its loss-objective counterpart recovered later; this does not turn the constant-objective attempt into a native pass. For unresolved original-Q contracts, bounded sparse outer-LP checks found no certificate. Freeing equipment changes the model; Ipopt success there does not establish MadNLP or CCOpt success on that changed model.','']
(OUT/'FAILED_COMBINATIONS.md').write_text('\n'.join(lines))
print('Validated: 43 direct failed combinations, 49 failed attempts; 13 combinations / 19 attempts recovered on same solver/model/objective; 30 unresolved; all 61 failures retained.')
