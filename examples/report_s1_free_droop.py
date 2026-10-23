"""Generate loss, qualification, and failure/recovery tables from checkpointed runs."""
from pathlib import Path
from collections import defaultdict
import json
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'artifacts/s1_free_droop'
load=lambda p:json.loads(p.read_text())
labels={'droop':'Droops','droop_tap':'Droops + taps','droop_shunt':'Droops + shunts','droop_tap_shunt':'Droops + taps + shunts','tap':'Taps only','shunt':'Shunts only','fixed':'None'}
factors=(.9,.95,1.,1.05,1.1)
def key(r):
 p=r['contract']['policy']
 p={k:[{a:b for a,b in x.items() if a!='initial'} for x in v] for k,v in p.items()}
 return json.dumps([r['contract']['case'],p,r['objective_kind']],sort_keys=True)
allsummary=[];allfailures=[]
for size in (14,500):
 out=OUT/str(size);rows=[load(p) for p in sorted((out/'attempts').glob('*.json'))]
 keys={r['name']:key(r) for r in rows};summary=[];groups=defaultdict(list)
 for r in rows:
  if r['tags']['stage'] in ('design','frozen','equipment_baseline'):groups[(r['tags']['stage'],r['tags']['family'],r['tags']['factor'])].append(r)
 for (stage,family,f),rs in sorted(groups.items()):
  physical_keys={keys[r['name']] for r in rs};extra=[r for r in rows if r['tags']['stage']=='recovery' and keys[r['name']] in physical_keys]
  good=[r for r in rs+extra if r['accepted']];physical=[r for r in rs+extra if r['point_pass']]
  best=min(good,key=lambda r:r['loss_mw']) if good else None
  summary.append(dict(size=size,stage=stage,family=family,factor=f,direct_attempts=len(rs),direct_accepted=sum(r['accepted'] for r in rs),physical=sum(r['point_pass'] for r in rs),model_gate='feasible' if physical or stage=='design' else 'unresolved',accepted_solvers=sorted({r['solver'] for r in good}),best=best['name'] if best else None,loss_mw=best['loss_mw'] if best else None,economic_cost=best['economic_cost'] if best else None))
 failures=[];badgroups=defaultdict(list)
 for r in rows:
  if not r['accepted'] and r['tags']['stage']!='recovery':badgroups[(r['tags']['stage'],r['tags']['family'],r['tags']['factor'],r['solver'],keys[r['name']])].append(r)
 for (stage,family,f,solver,k),bad in sorted(badgroups.items()):
  witnesses=[r for r in rows if keys[r['name']]==k and r['point_pass']]
  wins=[r for r in witnesses if r['accepted'] and r['solver']==solver]
  wins.sort(key=lambda r:(r['tags']['stage']!='recovery',r['name']))
  win=wins[0] if wins else None
  failures.append(dict(size=size,stage=stage,family=family,factor=f,solver=solver,failed_attempts=[r['name'] for r in bad],initializations=sorted({r['tags'].get('init','') for r in bad}),statuses=sorted({r.get('solver_status',r.get('error','error')) for r in bad}),recovered=win is not None,recovery=win['name'] if win else None,method=win['tags'].get('method','alternate direct start') if win else 'unresolved solver outcome',seed=win['tags'].get('seed') if win else None,model_gate='feasible' if witnesses or stage=='design' else 'unresolved'))
 if (out/'legacy_failures.json').exists():
  legacy=load(out/'legacy_failures.json');trials=[r for r in rows if r['tags'].get('target_stage')=='legacy_fixed'];wins=[r for r in trials if r['accepted']];win=wins[0] if wins else None
  failures.append(dict(size=size,stage='legacy_fixed',family='fixed',factor=.9,solver='ccopt',failed_attempts=[r['name'] for r in legacy],initializations=[r['tags'].get('init','') for r in legacy],statuses=sorted({r['solver_status'] for r in legacy}),recovered=win is not None,recovery=win['name'] if win else None,method=win['tags']['method'] if win else 'unresolved native solver outcome',seed=win['tags']['seed'] if win else None,model_gate='feasible'))
 allsummary.extend(summary);allfailures.extend(failures)
 (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');(out/'failed_combinations.json').write_text(json.dumps(failures,indent=2)+'\n')
 lines=[f'# {size}-bus free-droop failure and recovery table','','Recovery requires the same solver, objective and mathematical constraints. Warm starts or numerical settings may change. Direct failures remain in the direct acceptance denominator.','','| Stage | Family | Demand | Solver | Failed starts | Native outcomes | Recovered? | Method and evidence |','|---|---|---:|---|---|---|---|---|']
 for r in failures:
  evidence=f"{r['method']}; [result](attempts/{r['recovery']}.json); seed `{r['seed']}`" if r['recovered'] else r['method']+'; model gate '+r['model_gate']
  lines.append(f"| {r['stage']} | {labels[r['family']]} | {r['factor']:.0%} | {r['solver']} | {', '.join(r['initializations'])} ({len(r['failed_attempts'])}) | {', '.join(r['statuses'])} | {'Yes' if r['recovered'] else 'No'} | {evidence} |")
 if not failures:lines+=['','No failed direct solver/model combinations in the saved runs.']
 lines+=['','## Retained unsuccessful attempts, including retries','','| Attempt | Stage | Native status | Physical point valid? | Max balance pu | Max exact droop pu |','|---|---|---|---|---:|---:|']
 for r in rows:
  if not r['accepted']:
   ph=r.get('point_checks',{}).get('physical',{})
   lines.append(f"| [{r['name']}](attempts/{r['name']}.json) | {r['tags']['stage']} | {r.get('solver_status',r.get('error','error'))} | {r['point_pass']} | {ph.get('power_balance_max','—')} | {ph.get('droop_residual_max','—')} |")
 (out/'FAILED_AND_RECOVERED.md').write_text('\n'.join(lines)+'\n')
lines=['# S1 free-droop extension: 14 and 500 buses','','This extends the selected joint loss-reference studies; it does not replace their saved fixed-droop results. All new runs are base-case S1, with study Pmin=0 and symmetric Q limits. Original-limit sensitivities and SCOPF are outside this extension.','','## Definition and comparisons','','Each online controlled generator has an independent full-Q-span droop percentage between 2% and 8% and voltage reference within ±0.02 pu of its original calibrated reference. Deadband remains zero and Q at the reference remains zero. These are declared study design bounds, not hardware claims. The exact curve is Q(V)=clip((Vref−V)/m,Qmin,Qmax), with m=d/(Qmax−Qmin) and d between 0.02 and 0.08. References need not coincide with operating voltages. Equipment selection uses the same ±5%-of-source tap envelopes and continuous bank-specific susceptance limits; unselected equipment stays at the nominal joint reference.','','Four families are tested: droops only, droops+taps, droops+shunts, and all three. At every demand, design runs may retune selected controls. Separately, the best accepted nominal candidate per family is selected, with a 1e−6 MW loss tie tolerance and preference for smaller normalized slope/reference changes among tested candidates. All its curves, taps and shunts are then frozen for the demand matrix. The candidate pool consists of the new solver-returned designs; the original calibrated design remains a separate comparator. This selection is not a global secondary optimization and nominal co-optimal curves are not unique.','','Both matrices use 90/95/100/105/110% demand, nominal joint and demand-matched loss/cost OPF starts, and Ipopt/MadNLP/CCOpt: 180 design + 180 frozen attempts per network. No flat starts. The direct design runs initialize droop parameters from the calibrated 8% curves and reference voltages; the three starts vary the AC state. Selected equipment starts at the joint-reference settings. Recovery initializes optimized parameters and equipment from its named verified witness. Direct budgets match the earlier studies (14 buses:600 iterations/20s;500 buses:1000/60s; Ipopt CPU limit, other solvers wall limit). Failures get verified warm starts, then expanded-budget CCOpt barrier tuning or smooth bounds normalization. Some small comparison/recovery jobs overlapped the main campaign. Numerical timing and time-limit counts are therefore not a strictly serial, matched wall-time benchmark.','','## Acceptance and losses','','Loss columns show best accepted local points, including separately recorded retries. Frozen columns concern the newly designed nominal candidate; do not confuse them with adaptive design at each demand.','','| Buses | Stage | Family | Direct passes | Feasible demand points | Solver/demand combinations accepted after recovery | Loss90 MW | Loss95 | Loss100 | Loss105 | Loss110 |','|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|']
for size in (14,500):
 for stage in ('design','frozen','equipment_baseline'):
  for family in labels:
   rs=sorted([r for r in allsummary if r['size']==size and r['stage']==stage and r['family']==family],key=lambda r:r['factor'])
   if not rs:continue
   values=' | '.join('—' if r['loss_mw'] is None else f"{r['loss_mw']:.6f}" for r in rs)
   lines.append(f"| {size} | {stage} | {labels[family]} | {sum(r['direct_accepted'] for r in rs)}/{sum(r['direct_attempts'] for r in rs)} | {sum(r['model_gate']=='feasible' for r in rs)}/{len(rs)} | {sum(len(r['accepted_solvers']) for r in rs)}/{3*len(rs)} | {values} |")
# Matched equipment-only baselines use the same final calibration and bounds.
old500=load(ROOT/'artifacts/s1_arpae500/qualification.json')['scorecard']
old14=load(ROOT/'artifacts/s1_arpae14_closeout/demand_witnesses.json')
old14rows=[]
for fn in ('rows.jsonl','joint_anchor_rows.jsonl'):
 old14rows += [json.loads(x) for x in (ROOT/'artifacts/s1_arpae14_joint_reference'/fn).read_text().splitlines()]
baselines={}
for r in old500:baselines[(500,r['family'],r['factor'])]=r['loss_mw']
for r in old14:baselines[(14,'fixed',r['tags']['factor'])]=r['loss_mw']
for f in factors:
 good=[r for r in old14rows if r['accepted'] and r['tags'].get('arm')=='joint_free' and r['tags'].get('range')=='relative5' and r['tags']['factor']==f]
 if good:baselines[(14,'tap_shunt',f)]=min(r['loss_mw'] for r in good)
for r in allsummary:
 if r['stage']=='equipment_baseline' and r['loss_mw'] is not None:baselines[(r['size'],r['family'],r['factor'])]=r['loss_mw']
comparisons=[]
for r in allsummary:
 if r['stage'] not in ('design','frozen') or r['loss_mw'] is None:continue
 family='fixed' if r['stage']=='frozen' or r['family']=='droop' else r['family'].replace('droop_','',1)
 old=baselines.get((r['size'],family,r['factor']))
 if old is None:continue
 comparisons.append(dict(size=r['size'],stage=r['stage'],family=r['family'],factor=r['factor'],baseline_equipment=family,baseline_loss_mw=old,new_loss_mw=r['loss_mw'],loss_change_percent=100*(r['loss_mw']/old-1)))
(OUT/'comparisons.json').write_text(json.dumps(comparisons,indent=2)+'\n')
lines+=['','## Comparison with fixed-droop results','','Adaptive design is compared with fixed curves and the same equipment freedom. Frozen candidates are compared with the old fully frozen nominal design. Negative percentages mean lower best-found local loss. This compares both slope and voltage-reference freedom; it does not isolate slope-only effects.','','| Buses | Stage | Family | Demand | Comparable baseline loss MW | New loss MW | Change % |','|---:|---|---|---:|---:|---:|---:|']
for r in comparisons:
 if r['factor'] in (.9,1.1):lines.append(f"| {r['size']} | {r['stage']} | {labels[r['family']]} | {r['factor']:.0%} | {r['baseline_loss_mw']:.6f} | {r['new_loss_mw']:.6f} | {r['loss_change_percent']:+.2f}% |")
lines+=['','## Failed and recovered combinations','','| Buses | Stage | Family | Demand | Solver | Failed direct attempts | Same-model recovery | Method |','|---:|---|---|---:|---|---:|---|---|']
for r in allfailures:lines.append(f"| {r['size']} | {r['stage']} | {labels[r['family']]} | {r['factor']:.0%} | {r['solver']} | {len(r['failed_attempts'])} | {'Recovered' if r['recovered'] else 'Not recovered'} | {r['method']} |")
if not allfailures:lines+=['','No failed combinations in saved completed cells.']
lines+=['','Complete tables with failed initializations, native statuses, evidence links and retained unsuccessful retries are in `14/FAILED_AND_RECOVERED.md` and `500/FAILED_AND_RECOVERED.md` beside this report. Historical 500-bus fixed-droop failures remain in `artifacts/s1_arpae500/FAILED_COMBINATIONS.md`; original-Q fixed-equipment contracts there remain unresolved and are not requalified by symmetric-Q free-droop tests. Historical 14-bus free-slope experiments used earlier references; they are not substituted for the new selected-reference runs.','','## Gates and reproducibility','','All design-family feasibility gates inherit independently verified incumbent fixed-8% witnesses lying inside the free-design bounds. This establishes a feasible numerical witness at each demand under the declared acceptance tolerances, but does not count as a solver pass or establish off-nominal feasibility of an optimized frozen candidate. Frozen-candidate gates use their own physical witnesses. Acceptance requires successful native termination, design-policy bounds, exact droop, AC balances, generator/voltage/branch/angle limits and equipment policy. Tolerances are unchanged. No failed local solve is treated as global infeasibility.','','Every attempt stores the source model, optimized curve model, parameter/equipment policies, initialization identity/hash, solver settings, full voltages/dispatch/flows, limits and margins. Initial states are reproducible from the pinned OPF artifacts and runner. `selected-*-study.json` stores each frozen nominal candidate. Independent Python replay checks complex branch flows, balances, exact curves and design bounds; `independent_audit.json` records its coverage. Source hashes in the parent protocol preserve the old studies.','','```sh','julia --project=. examples/s1_free_droop.jl 14','julia --project=. examples/s1_free_droop.jl 500','julia --project=. examples/s1_free_droop_baselines.jl','julia --project=. examples/s1_free_droop_recovery.jl','python3 examples/audit_s1_free_droop.py','python3 examples/report_s1_free_droop.py','python3 examples/finalize_s1_free_droop.py','```','','Qualification is limited to sampled steady-state demand points. Per-demand retuning is not one installed robust controller, and successful solves do not establish dynamics, N−1 security or global optimality.','']
(OUT/'REPORT.md').write_text('\n'.join(lines)+'\n')
(OUT/'summary.json').write_text(json.dumps(dict(groups=allsummary,failures=allfailures),indent=2)+'\n')
print('Reported',len(allsummary),'stage/family/demand cells;',len(allfailures),'failed solver/model combinations')

# Preserve the separately scored zero-deadband numerical follow-up.
from s1_zero_deadband_reporting import append_followup
append_followup(OUT/'REPORT.md', doc=False)

from control_figure_reporting import attach_s1
attach_s1(OUT/'REPORT.md', figures=True)
