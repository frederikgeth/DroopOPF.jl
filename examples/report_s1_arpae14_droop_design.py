from pathlib import Path
import json
from collections import defaultdict
root=Path(__file__).resolve().parents[1];out=root/'artifacts/s1_arpae14_droop_design'
read=lambda p:[json.loads(x) for x in p.read_text().splitlines()]
design=read(out/'design_rows.jsonl');frozen=read(out/'frozen_rows.jsonl');eq=read(root/'artifacts/s1_arpae14_equipment/rows.jsonl')
assert len(design)==len(frozen)==120
assert len({r['name'] for r in design+frozen})==240
assert not any('error' in r for r in design+frozen)
selected=json.loads((out/'selected_designs.json').read_text())
families=['droop','tap_droop','shunt_droop','joint'];factors=[.9,.95,1.,1.05,1.1]
lines=['# S1 14-bus droop design and frozen-design validation','',
'120 design optimizations and 120 frozen-design solves. G1–G5 slope percentages vary independently within 2–8%, defined over the full Qmin-to-Qmax span. References remain fixed at the original nominal loss-OPF-calibrated 8% references; no deadband. A changed slope therefore does not generally reproduce the original calibration OPF. Reference movements are zero. G6 remains offline. Pmin=0, symmetric Q limits, source angle/equipment limits, and dispatch-deviation objective are retained.','',
'Tap/shunt families use all three transformers within the declared ±5% source-tap study envelope and available bank 3 as continuous B in [0,0.4] pu. These are S1 base-case optimizations, not SCOPF or discrete bank switching. Five demand levels, two demand-matched cost/loss OPF starts, three solvers; no flat starts. Smooth voltage/absolute-Q epsilon 1e-6 pu, 600 iterations/20 native seconds; tight exact CCOpt profile.','',
'All ten source OPF seeds pass precursors. All design models contain the verified fixed-8% baseline within their bounds (120 inherited-witness checks). Thus design solver failures cannot establish infeasibility. Frozen models are different contracts: only nominal feasibility is guaranteed by the selected design witness; other demands need their own witnesses.','',
'## Direct results','',
'| Stage | Free-design family | Ipopt accepted | MadNLP accepted | CCOpt accepted | Physically verified |','|---|---|---:|---:|---:|---:|']
for stage,rows in [('Design',design),('Frozen',frozen)]:
 for family in families:
  rs=[r for r in rows if r['tags']['family']==family]
  ns=[sum(r['accepted'] for r in rs if r['solver']==s) for s in ('ipopt','madnlp','ccopt')]
  lines.append(f"| {stage} | {family} | {ns[0]}/10 | {ns[1]}/10 | {ns[2]}/10 | {sum(r['point_pass'] for r in rs)}/30 |")
lines+=['','## Nominal designs selected before demand replay','',
'Choose the smallest objective among accepted 100%-demand designs in each family (name breaks exact ties). Freeze all droop, tap and shunt settings, then test all five demands; no redesign or out-of-demand selection.','',
'| Family | G1–G5 droop percentages | Selected run |','|---|---|---|']
for s in selected:lines.append(f"| {s['family']} | "+', '.join(f'{v:.5f}' for v in s['slopes_percent'])+f" | {s['source']} |")
lines+=['','## Frozen-design demand coverage','',
'Each cell is physically verified / solver-accepted out of six direct runs. A witness establishes feasibility even if another solver fails. Without a witness or certificate, the demand remains unresolved.','',
'| Family | 90% | 95% | 100% | 105% | 110% |','|---|---:|---:|---:|---:|---:|']
for family in families:
 cells=[]
 for f in factors:
  rs=[r for r in frozen if r['tags']['family']==family and r['tags']['factor']==f]
  cells.append(f"{sum(r['point_pass'] for r in rs)} / {sum(r['accepted'] for r in rs)}")
 lines.append('| '+family+' | '+' | '.join(cells)+' |')
lines+=['','## Best accepted design at each demand','',
'This table allows a separate design at each demand; it must not be read as one common controller. Improvement uses the best fixed-8% equipment-fixed objective at the same demand.','',
'| Demand | Family | Objective | Improvement | Loss MW | Vmax margin pu | Thermal margin MVA |','|---|---|---:|---:|---:|---:|---:|']
best=[]
for f in factors:
 baseline=min(r['objective'] for r in eq if r['tags']['family']=='fixed' and r['tags']['factor']==f and r['accepted'])
 for family in families:
  rs=[r for r in design if r['tags']['family']==family and r['tags']['factor']==f and r['accepted']]
  if not rs:continue
  r=min(rs,key=lambda r:r['objective']);a=r['point_checks']['physical'];improvement=100*(baseline-r['objective'])/baseline
  thermal=min(b['thermal_margin_mva'] for b in r['branches'] if b['thermal_margin_mva'] is not None)
  best.append(dict(family=family,factor=f,name=r['name'],objective=r['objective'],improvement_percent=improvement,loss_mw=r['loss_mw']))
  lines.append(f"| {f:.0%} | {family} | {r['objective']:.7g} | {improvement:.2f}% | {r['loss_mw']:.5f} | {a['voltage_max_margin']:.3g} | {thermal:.3g} |")
lines+=['','## Direct runs without accepted feasible points','', '| Run | Status | Physically verified |','|---|---|---|']
failed=[r for r in design+frozen if not r['accepted']]
for r in failed:lines.append(f"| {r['name']} | {r.get('solver_status')} | {r['point_pass']} |")
if not failed:lines.append('| None | — | — |')
lines+=['','## Decision for the remaining S1 work','',
'Keep uniform 8%, no deadband, nominal loss-OPF calibration and source equipment as the production study baseline: it retains 30/30 accepted direct runs over the five sampled demands. The frozen droop-only [8,2,8,8,8]% candidate has witnesses at every demand but only 28/30 direct solver successes. The shunt+droop variant is effectively the same physical design (B near zero); its 29/30 count is numerical sensitivity, not evidence of a useful shunt benefit. References are the original 8%-calibrated references, not recalibrated to this new profile.','',
'The frozen tap+droop and joint designs are not qualified over the required 90–110% range: both are unresolved at 90% (0/6 witnesses) and verified at 95–110%. Their local-infeasible statuses are not global certificates. Do not replace the baseline with these nominal-only designs. A future common-design study should enforce feasibility across the demand scenarios when choosing shared slopes and equipment settings; independently optimizing each scenario does not provide that guarantee.','',
'All 15 unsuccessful design terminations are CCOpt iteration limits; four nevertheless produce independently verified physical points. All design models are known feasible from retained baseline witnesses. The smooth solvers each accept 40/40 design runs. Separate numerical convergence work from physical feasibility.','',
'The best nominal tap+droop objective is 0.5703822, slightly worse than the earlier tap-only 0.5700722 despite containing that solution in its design bounds. This is a local-solve limitation, not a physical penalty from adding freedom. At 105% the joint result also fails to dominate tap+droop. Do not claim global optima or monotone improvement from these direct runs.','',
'Next compare S1 dispatch-deviation, loss and economic objectives on the retained baseline, keeping calibration, starts, limits and gates fixed. Then test any proposed common optimized controller across the full demand set before original-limit variants and the 500-bus transfer. Tight voltage/thermal margins remain part of the acceptance report, not an implication of successful solver termination.','']
lines+=['','Detailed limits, bus voltages, generator Pg/Qg, branch flows, settings and point gates are retained in both JSONL ledgers. Design results are also saved with complete control policies. Frozen-study files contain the actual selected settings. Independent serialized replay is recorded in serialization_audit.json. These static local solutions do not prove global optimality or dynamic stability.','']
(out/'report.md').write_text('\n'.join(lines))
summary=dict(design_verified=sum(r['point_pass'] for r in design),design_accepted=sum(r['accepted'] for r in design),frozen_verified=sum(r['point_pass'] for r in frozen),frozen_accepted=sum(r['accepted'] for r in frozen),selected=selected,best=best)
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({k:v for k,v in summary.items() if k not in ('selected','best')}))
