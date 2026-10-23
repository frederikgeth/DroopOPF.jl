"""Compare loss-minimized and cost-minimized demand-matched S1 seeds."""
import json, hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[1]
out=root/'artifacts/s1_arpae14_loss_anchors'
prior=root/'artifacts/s1_arpae14_demand_anchors'
load=lambda p:json.loads(p.read_text())
rows=load(out/'matrix_summary.json');costrows=load(prior/'matrix_summary.json')
assert len(rows)==18 and all(r['tags']['start']=='loss_anchor' and 'error' not in r and r['calibration_pass'] for r in rows)
checks=load(out/'precursor_checks.json')
assert len(checks)==6 and all(r['source_gate']=='feasible' for r in checks)
meta=load(out/'opf_summary.json')
original=root/'test/data/arpae/c1_network01/results/scenario_01_pmin0_qsym/opf_ac.json'
assert hashlib.sha256(original.read_bytes()).hexdigest()==meta['original_sha256']
net=load(original.parent/'network_model.json');bm=net['baseMVA']
key=lambda r:(r['tags']['variant'],r['tags']['factor'],r['solver'])
costrows={key(r):r for r in costrows}
variants=('no_deadband','with_deadband');solvers=('ipopt','madnlp','ccopt')
rows.sort(key=lambda r:(variants.index(r['tags']['variant']),r['tags']['factor'],solvers.index(r['solver'])))
lines=['# S1 14-bus loss-minimized OPF anchors','',
'At 90%, 100% and 110% demand, the source AC OPF minimizes total active-power losses: sum(Pg) − sum(Pd). Demand is fixed within each solve, so minimizing total generation is equivalent. Active power accounting independently confirms the result equals branch-terminal losses plus fixed-shunt conductance consumption. This is a locally optimized AC solution, not a certificate of the global minimum.','',
'Source taps and shunts are fixed. Study generator Pmin remains zero and Q bounds remain symmetric. Each source OPF point passes the independent AC, voltage, generator, thermal and angle-limit gate before being used as the S1 initial state. The preserved source OPF file checksum is unchanged.','',
'S1 changes only its initial voltage, angle, Pg and Qg. The original nominally calibrated 4% droop curves, deadband settings, fixed equipment and dispatch-deviation objective remain unchanged. All three solvers use the preceding 600-iteration / 20-native-second budget and unchanged solver profiles. No contingencies are included.','',
'| Demand | Cost-minimized OPF losses, MW | Loss-minimized OPF losses, MW | Reduction | Source gate |','|---|---:|---:|---:|---|']
loss_comparison=[]
for r in meta['rows']:
 f=r['factor'];s=load(prior/f'opf-{f}.json')['solution']
 old=sum(g['pg'] for g in s['gen'].values())*bm-r['load_mw']
 reduction=100*(old-r['loss_mw'])/old
 loss_comparison.append(dict(r,cost_opf_loss_mw=old,reduction_percent=reduction))
 lines.append(f"| {100*f:.0f}% | {old:.6f} | {r['loss_mw']:.6f} | {reduction:.2f}% | Pass |")
lines+=['','| Curve | Demand | Solver | Cost anchor gate | Loss anchor gate | Loss-anchor termination |','|---|---:|---|---|---|---|']
comparison=[]
for r in rows:
 b=costrows[key(r)];good=bool(r['point_pass'])
 assert r['frozen_curve_fingerprint']==b['frozen_curve_fingerprint'], 'fixed model changed'
 comparison.append(dict(variant=r['tags']['variant'],factor=r['tags']['factor'],solver=r['solver'],cost_anchor_pass=b['point_pass'],loss_anchor_pass=good,solver_status=r['solver_status'],solver_success=r['solver_success']))
 lines.append(f"| {r['tags']['variant'].replace('_',' ')} | {100*r['tags']['factor']:.0f}% | {r['solver']} | {'Verified' if b['point_pass'] else 'Unresolved'} | {'Verified' if good else 'Unresolved'} | {r['solver_status']} |")
lines+=['','| Curve | Cost anchor verified | Loss anchor verified |','|---|---:|---:|']
for v in variants:
 g=[r for r in comparison if r['variant']==v]
 lines.append(f"| {v.replace('_',' ')} | {sum(r['cost_anchor_pass'] for r in g)}/9 | {sum(r['loss_anchor_pass'] for r in g)}/9 |")
lines+=['','The 100% deadband Ipopt run regresses from a verified cost-anchor solution to LOCALLY_INFEASIBLE with the loss anchor. Its fixed-case fingerprint matches the earlier verified run. The earlier point therefore establishes feasibility of this model, and this new failure is initialization-sensitive solver behavior.','']
lines+=['','## Generator starting points','', '| Demand | Generator | Cost Pg, MW | Loss Pg, MW | Cost Qg, MVAr | Loss Qg, MVAr |','|---|---|---:|---:|---:|---:|']
for f in (.9,1.,1.1):
 c=load(prior/f'opf-{f}.json')['solution'];l=load(out/f'opf-{f}.json')['solution']
 for k,g in sorted(net['gen'].items(),key=lambda x:int(x[0])):
  if g['gen_status']!=1:continue
  a,b=c['gen'][k],l['gen'][k]
  lines.append(f"| {100*f:.0f}% | G{k} | {a['pg']*bm:.6f} | {b['pg']*bm:.6f} | {a['qg']*bm:.6f} | {b['qg']*bm:.6f} |")
lines+=['','The source loss optimum can violate the added frozen droop curves. Local infeasibility and iteration limits in S1 are solver outcomes, not global infeasibility proofs. Loss minimization is used only to construct the starting point in this experiment.','']
(out/'report.md').write_text('\n'.join(lines))
(out/'comparison.json').write_text(json.dumps(dict(losses=loss_comparison,s1=comparison),indent=2)+'\n')
print('\n'.join(lines))
