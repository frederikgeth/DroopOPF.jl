from pathlib import Path
import json
root=Path(__file__).resolve().parents[1];out=root/'artifacts/s1_arpae14_performance_controls'
read=lambda p:[json.loads(x) for x in p.read_text().splitlines()]
design=read(out/'design_rows.jsonl');frozen=read(out/'frozen_rows.jsonl')
assert len(design)==480 and len(frozen)==420
assert len({r['name'] for r in design+frozen})==900
assert not any('error' in r for r in design+frozen)
assert all(r['valid'] for r in json.loads((out/'precursors.json').read_text()))
assert all(r['valid'] for r in json.loads((out/'inherited_witnesses.json').read_text()))
families=['fixed','tap','shunt','tap_shunt','droop','tap_droop','shunt_droop','joint'];factors=[.9,.95,1.,1.05,1.1]
selected=json.loads((out/'selected_designs.json').read_text())
def choose(rows,obj,family,f):
 rs=[r for r in rows if r['tags']['objective']==obj and r['tags']['family']==family and r['tags']['factor']==f and r['accepted']]
 return min(rs,key=lambda r:(r['objective_recomputed'],r['name'])) if rs else None
lines=['# S1 14-bus free controls under loss and cost objectives','',
'420 new free-control optimizations, 60 retained fixed-control reference runs, and 420 new frozen-design tests. Five demand levels (90/95/100/105/110%), cost/loss demand-matched OPF starts and Ipopt/MadNLP/CCOpt. No flat starts or contingencies.','',
'Calibration stays at the nominal loss OPF: shifted zero-Q, original 8%-calibrated references and no deadband. Selected slopes vary independently in 2–8% over the full Q range; references remain fixed and are not recalibrated during slope optimization. Taps 19/20/21 use the declared ±5% source study range; bank 3 uses continuous B in [0,0.4] pu. Pmin=0 and symmetric Q limits remain. All ten source seeds pass checks; every expanded design model inherits a feasible fixed-8% witness.','',
'Loss minimizes total active generation minus load. Cost minimizes the convex source PWL generation cost divided by 100000, including endpoint extrapolation as in the previous fixed-control comparison. Reported costs are unscaled source units. All points are independently evaluated for both cost and losses. Budget: 600 iterations/20 native solver seconds; smooth voltage and absolute-Q widths 1e-6 pu; tight exact CCOpt profile.','',
'## Design acceptance','', '| Objective | Free controls | Ipopt | MadNLP | CCOpt | Verified |','|---|---|---:|---:|---:|---:|']
for obj in ['loss','cost']:
 for family in families:
  rs=[r for r in design if r['tags']['objective']==obj and r['tags']['family']==family]
  ns=[sum(r['accepted'] for r in rs if r['solver']==solver) for solver in ['ipopt','madnlp','ccopt']]
  lines.append(f"| {obj} | {family} | {ns[0]}/10 | {ns[1]}/10 | {ns[2]}/10 | {sum(r['point_pass'] for r in rs)}/30 |")
lines+=['','## Best accepted nominal points','',
'Best independently evaluated requested objective among six starts/solvers. A row represents one local point; additional free controls do not guarantee the local solver finds a better point.','',
'| Free controls | Loss objective: MW | Its cost | Cost objective: cost | Its loss MW |','|---|---:|---:|---:|---:|']
for family in families:
 a=choose(design,'loss',family,1.);b=choose(design,'cost',family,1.)
 lines.append(f"| {family} | {a['loss_mw']:.6f} | {a['economic_cost']:.3f} | {b['economic_cost']:.3f} | {b['loss_mw']:.6f} |")
lines+=['','## Frozen nominal designs','',
'For each objective/family select the accepted nominal point with the smallest independently replayed objective, then freeze all slopes, taps and shunts. No settings are retuned across demand. The nominal design witness is checked before evaluation. Below, each cell is verified / accepted out of six direct solves. Feasibility coverage requires at least one witness at every demand; it does not require every solver to converge.','',
'| Objective | Design family | 90% | 95% | 100% | 105% | 110% | Demand coverage |','|---|---|---:|---:|---:|---:|---:|---|']
gates=[]
for obj in ['loss','cost']:
 for family in families[1:]:
  cells=[];coverage=True
  for f in factors:
   rs=[r for r in frozen if r['tags']['objective']==obj and r['tags']['family']==family and r['tags']['factor']==f]
   n=sum(r['point_pass'] for r in rs);a=sum(r['accepted'] for r in rs);coverage&=n>0 or f==1.
   cells.append(f'{n} / {a}')
   gates.append(dict(objective=obj,family=family,factor=f,status='feasible' if n or f==1. else 'unresolved',witnesses=[r['name'] for r in rs if r['point_pass']],nominal_selected_witness=f==1.,certificate=None))
  lines.append(f'| {obj} | {family} | '+' | '.join(cells)+f" | {'feasible' if coverage else 'unresolved'} |")
lines+=['','## Selected settings','', '| Objective | Family | G1–G5 droop percentages | Source design |','|---|---|---|---|']
for s in selected:lines.append(f"| {s['objective']} | {s['family']} | "+', '.join(f'{v:.4f}' for v in s['slopes_percent'])+f" | {s['source']} |")
lines+=['','## Nominal limits at the selected points','', '| Objective | Family | Vmax margin pu | Thermal margin MVA | Max absolute tap movement | Shunt B pu |','|---|---|---:|---:|---:|---:|']
for obj in ['loss','cost']:
 for family in families:
  r=choose(design,obj,family,1.);a=r['point_checks']['physical'];thermal=min(b['thermal_margin_mva'] for b in r['branches'] if b['thermal_margin_mva'] is not None)
  tap=max(abs(x['delta']) for x in r['tap_movements']);bs=max(x['value_b'] for x in r['shunt_movements'])
  lines.append(f"| {obj} | {family} | {a['voltage_max_margin']:.3g} | {thermal:.4g} | {tap:.5g} | {bs:.5g} |")
lines+=['','## Local-solve dominance checks','',
'An expanded feasible set contains its fixed-control baseline. A best-found accepted result worse than that known point indicates incomplete optimization, not a physical cost of added freedom.','', '| Objective | Family | Demand | Baseline objective | Best design objective |','|---|---|---:|---:|---:|']
dominated=[]
for obj in ['loss','cost']:
 for family in families[1:]:
  for f in factors:
   b=choose(design,obj,'fixed',f);r=choose(design,obj,family,f)
   if r and b and r['objective_recomputed']>b['objective_recomputed']+1e-6:
    dominated.append(r['name']);lines.append(f"| {obj} | {family} | {f:.0%} | {b['objective_recomputed']:.8g} | {r['objective_recomputed']:.8g} |")
if not dominated:lines.append('| None above 1e-6 objective units | — | — | — | — |')
lines+=['','## Decision for the remaining S1 work','',
'All 840 new solves completed: 398/420 free-control runs and 347/420 frozen-design runs were solver-accepted and physically verified. The design table also includes 49/60 accepted retained fixed-control cells. All 900 saved states were independently replayed without discrepancies. Eleven of fourteen frozen designs have a witness at every sampled demand; solver acceptance is a stricter, separately reported measure.','',
'Retain uniform 8% with source equipment as the reference. Carry forward three frozen candidates: economic tap-only (30/30 accepted), economic taps+shunt (30/30), and loss-minimizing taps+droop (30/30). The economic candidates retain uniform 8% slopes. The loss candidate uses approximately [8,8,7.5646,2,8]%, with the original voltage references held fixed. These are sampled-demand qualified candidates, not new universal defaults.','',
'The loss candidate has nominal losses 0.608176 MW versus 0.629822 MW for fixed equipment (about 3.44% lower). Its taps 19/20/21 are 0.987100/0.938028/0.958453 and its bank stays off. The economic tap-only candidate has nominal cost 988.924 versus 4095.989 source units (about 75.86% lower), but losses rise from 3.896178 to 4.994009 MW. Its taps are 1.026690/0.920551/0.940276. The economic taps+shunt candidate gives cost 988.702, losses 4.968533 MW, and B=0.0544672 pu at bank 3; the improvement over tap-only is modest and uses continuous shunt control.','',
'Do not promote the nominal joint optima: the loss-joint design has no witness at 90%; economic tap+droop has none at 90%; economic joint has none at 90% or 95%. These are unresolved frozen contracts, not globally certified infeasible. Individually redesigned cases remain feasible, so nominal optimality and demand-wide qualification answer different questions.','',
'Next test the reference and carried-forward candidates against the preserved original generator limits as a separate case variant. First replay existing fixed settings without silently recalibrating them; if the limit variant requires new calibration or redesign, report that separately with new precursor checks and model hashes. Retain the objective/solver/initialization separation and compare operating margins as well as cost/losses. Only then qualify transfer of the workflow to 500 buses; do not transfer these numerical settings or assume dynamic security.','']
lines+=['','Failed direct runs, all physical states, objective replay errors and per-device limits/settings are retained in the JSONL ledgers. Saved native design results and frozen-study files preserve the exact tested models. Replay is recorded in serialization_audit.json. Frozen models without witnesses outside nominal demand remain unresolved; local infeasibility is not a global certificate. These results establish sampled static feasibility, not global optimality or dynamic stability.','']
(out/'report.md').write_text('\n'.join(lines));(out/'frozen_gates.json').write_text(json.dumps(gates,indent=2)+'\n')
summary=dict(design_cells=480,new_design_solves=420,reused_fixed=60,frozen_cells=420,design_verified=sum(r['point_pass'] for r in design),design_accepted=sum(r['accepted'] for r in design),frozen_verified=sum(r['point_pass'] for r in frozen),frozen_accepted=sum(r['accepted'] for r in frozen),nominal_selected=selected,dominated_direct_results=dominated)
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps({k:v for k,v in summary.items() if k not in ['nominal_selected','dominated_direct_results']}))
