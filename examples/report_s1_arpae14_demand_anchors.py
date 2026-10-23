"""Compare fixed-droop S1 solves from nominal and demand-matched OPF seeds."""
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
out=root/'artifacts/s1_arpae14_demand_anchors'
load=lambda p:json.loads(p.read_text())
new=load(out/'matrix_summary.json')
old=load(root/'artifacts/s1_anchor_only/arpae14_anchor_rows.json')
assert len(new)==18 and all(r['tags']['start']=='demand_anchor' for r in new)
key=lambda r:(r['tags']['variant'],r['tags']['factor'],r['solver'])
old={key(r):r for r in old}
variants=('no_deadband','with_deadband');solvers=('ipopt','madnlp','ccopt')
new.sort(key=lambda r:(variants.index(r['tags']['variant']),r['tags']['factor'],solvers.index(r['solver'])))
checks=load(out/'precursor_checks.json')
assert len(checks)==6 and all(x['source_gate']=='feasible' for x in checks)
opf=load(out/'opf_summary.json')
lines=['# S1 14-bus demand-matched OPF initialization','',
'Each demand scenario first receives a fresh source economic AC OPF with fixed source transformer taps and shunts, Pmin = 0, and the preserved symmetric study Q limits. All three OPF solutions pass independent AC and equipment-limit replay, including source branch-angle limits. The original source solution files are unchanged.','',
'Only the initial voltage, angle, Pg and Qg are replaced in S1. The fixed 4% droop curves retain their references calibrated to the original 100% OPF. No droop reference, slope, deadband, tap, shunt or dispatch-reference parameter is retuned. Both demand components scale together. S1 still minimizes its original dispatch-deviation objective; the economic objective is used only to generate the source OPF seed.','',
'The S1 budget remains 600 iterations / 20 native solver seconds per cell, with the same smooth epsilon and CCOpt tight profile as the prior comparison. No contingencies are used. A fresh 100% OPF is included as a numerical control; its tolerance is 1e-8, so it can differ slightly from the preserved original OPF.','',
'| Demand | Source OPF status | Economic objective | Independent replay |','|---|---|---:|---|']
for r in opf['rows']:lines.append(f"| {100*r['factor']:.0f}% | {r['status']} | {r['economic_objective']:.6f} | Pass |")
lines+=['','| Curve | Demand | Solver | Original nominal anchor | Demand-matched anchor | New termination |','|---|---:|---|---|---|---|']
comparison=[]
for r in new:
 b=old[key(r)];passed=bool(r.get('point_pass',False))
 lines.append(f"| {r['tags']['variant'].replace('_',' ')} | {100*r['tags']['factor']:.0f}% | {r['solver']} | {'Verified' if b.get('point_pass') else 'Unresolved'} | {'Verified' if passed else 'Unresolved'} | {r.get('solver_status',r.get('error','ERROR'))} |")
 comparison.append({'variant':r['tags']['variant'],'factor':r['tags']['factor'],'solver':r['solver'],'original_point_pass':b.get('point_pass',False),'new_point_pass':passed,'new_solver_status':r.get('solver_status'),'new_solver_success':r.get('solver_success'),'new_objective':r.get('objective')})
lines+=['','| Curve | Original verified | Demand-matched verified |','|---|---:|---:|']
for v in variants:
 group=[r for r in comparison if r['variant']==v]
 lines.append(f"| {v.replace('_',' ')} | {sum(r['original_point_pass'] for r in group)}/9 | {sum(r['new_point_pass'] for r in group)}/9 |")
lines+=['','A verified source OPF seed need not satisfy the added fixed droop curves. Unresolved S1 points and locally infeasible solver terminations do not prove global infeasibility. These results test initialization alone; recalibrating droop references separately at each demand would define different controller models.','']
(out/'comparison.json').write_text(json.dumps(comparison,indent=2)+'\n')
(out/'report.md').write_text('\n'.join(lines))
print('\n'.join(lines))
