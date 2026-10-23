from pathlib import Path
import json
root=Path(__file__).resolve().parents[1];out=root/'artifacts/s1_arpae14_original_limits'
rows=[json.loads(x) for x in (out/'rows.jsonl').read_text().splitlines()]
assert len(rows)==len({r['name'] for r in rows})==450
assert not any('error' in r for r in rows)
protocol=json.loads((out/'protocol.json').read_text());prior=json.loads((out/'prior_point_replay.json').read_text());precursors=json.loads((out/'precursors.json').read_text())
assert len(precursors)==30 and all(r['valid'] for r in precursors)
candidates=protocol['candidates'];variants=['original_p','original_q','original_pq'];factors=[.9,.95,1.,1.05,1.1]
lines=['# S1 14-bus original-generator-limit sensitivity','',
'Four frozen physical candidates are evaluated in five objective lanes: the uniform-8% source-equipment reference under loss and cost, the loss tap+droop candidate, and the two cost tap/tap+shunt candidates. Each lane has three limit variants, five demands, two variant-matched OPF starts and three solvers: 450 new S1 solves plus 30 source OPF precursors.','',
'Only generator operating bounds change. References, numerical dV/dQ slopes, deadbands, saturation curves, taps and shunts are unchanged. Original P limits, original Q limits, and both together are tested separately. The exact study curves are not clipped or recalibrated to the original Q range. This is an unchanged-command compatibility test, not a new capability-clipped controller.','',
'The stored study Case plus the explicit original-limit overlay in protocol.json defines the mathematical model. The hook tightens generator-variable bounds to their intersection with original limits; acceptance requires both the independent base physical check and the independent original-limit check. Offline G6 remains offline and is not required to meet positive original Pmin. The library Case capability metadata is deliberately unchanged so the old droop curves remain exact.','',
'All 30 fresh source cost/loss OPFs satisfy AC and original-limit precursor checks. Numerical starts now come from the appropriate demand/limit-variant OPF; they differ from earlier study-limit starts. This comparison changes limits and updates feasible source initialization accordingly, not an isolated initialization experiment. The original reference calibration point may violate the restored bounds; that is recorded as compatibility evidence, not silently repaired.','',
'## Original limits','', '| Generator | Status | Pmin MW | Pmax MW | Qmin MVAr | Qmax MVAr |','|---|---|---:|---:|---:|---:|']
for id,g in sorted(protocol['original_generators'].items(),key=lambda p:int(p[0])):
 lines.append(f"| {id} | {'online' if g['gen_status'] else 'offline'} | {100*g['pmin']:.5f} | {100*g['pmax']:.5f} | {100*g['qmin']:.5f} | {100*g['qmax']:.5f} |")
lines+=['','## Unchanged numerical slopes expressed over original Q ranges','',
'The controller slopes dV/dQ are preserved, not reset to 8% of the narrower original Q span. The percentages below are 100 × slope × (original Qmax−original Qmin); they describe the same unchanged slopes using a different capability span. Saturation and references are still the study curves.','',
'| Candidate lane | G1 | G2 | G3 | G4 | G5 |','|---|---:|---:|---:|---:|---:|']
for name in candidates:
 c=json.loads((out/f'{name}-study.json').read_text())['data']['case'];vals=[]
 for a in sorted(c['attachments'],key=lambda a:a['generator_id']):
  g=protocol['original_generators'][str(a['generator_id'])];d=c['controls'][a['control_id']-1]
  vals.append(100*d['slope']*(g['qmax']-g['qmin']))
 lines.append('| '+name+' | '+' | '.join(f'{v:.4f}%' for v in vals)+' |')
lines+=['','Earlier study values used Pmin=0 and symmetric Q limits ±max(abs(original Qmin),abs(original Qmax)); Pmax was preserved. Source files and reference solutions remain unchanged.','',
'## Previously verified operating points replayed against restored limits','', '| Candidate lane | Original P | Original Q | Original P and Q |','|---|---:|---:|---:|']
for name in candidates:
 cells=[]
 for v in variants:
  rs=[r for r in prior if r['candidate']==name and r['variant']==v]
  cells.append(f"{sum(r['limits']['valid'] for r in rs)}/{len(rs)}")
 lines.append('| '+name+' | '+' | '.join(cells)+' |')
lines+=['','Only previously physically verified points are included above. A failed replay rejects that operating point, not the existence of another feasible point.','',
'## Fresh solve acceptance','', '| Candidate | Restored limits | Ipopt | MadNLP | CCOpt | Verified |','|---|---|---:|---:|---:|---:|']
for name in candidates:
 for variant in variants:
  rs=[r for r in rows if r['tags']['candidate']==name and r['tags']['variant']==variant]
  ns=[sum(r['accepted'] for r in rs if r['solver']==s) for s in ['ipopt','madnlp','ccopt']]
  lines.append(f"| {name} | {variant} | {ns[0]}/10 | {ns[1]}/10 | {ns[2]}/10 | {sum(r['point_pass'] for r in rs)}/30 |")
lines+=['','## Both original P and Q: demand coverage','',
'Cells show verified / accepted out of six runs. The gate includes retained prior witnesses as well as fresh witnesses.','',
'| Candidate | 90% | 95% | 100% | 105% | 110% |','|---|---:|---:|---:|---:|---:|']
gates=[]
for name in candidates:
 cells=[]
 for f in factors:
  rs=[r for r in rows if r['tags']['candidate']==name and r['tags']['variant']=='original_pq' and r['tags']['factor']==f]
  cells.append(f"{sum(r['point_pass'] for r in rs)} / {sum(r['accepted'] for r in rs)}")
 lines.append('| '+name+' | '+' | '.join(cells)+' |')
for name in candidates:
 for variant in variants:
  for f in factors:
   rs=[r for r in rows if r['tags']['candidate']==name and r['tags']['variant']==variant and r['tags']['factor']==f]
   old=[r['source'] for r in prior if r['candidate']==name and r['variant']==variant and r['factor']==f and r['limits']['valid']]
   new=[r['name'] for r in rs if r['point_pass']]
   gates.append(dict(candidate=name,variant=variant,factor=f,status='feasible' if old or new else 'unresolved',retained_witnesses=old,new_witnesses=new,certificate=None))
lines+=['','## Best nominal points with both original limits','', '| Candidate | Loss MW | Cost units | Minimum restored P margin MW | Minimum restored Q margin MVAr |','|---|---:|---:|---:|---:|']
best=[]
for name in candidates:
 rs=[r for r in rows if r['tags']['candidate']==name and r['tags']['variant']=='original_pq' and r['tags']['factor']==1. and r['accepted']]
 if not rs:
  lines.append(f'| {name} | No accepted point | — | — | — |');continue
 r=min(rs,key=lambda r:r['objective_recomputed']);ms=r['original_limit_checks']['margins']
 p=min(min(m['lower_margin'],m['upper_margin'])*100 for m in ms if m['axis']=='p');q=min(min(m['lower_margin'],m['upper_margin'])*100 for m in ms if m['axis']=='q')
 best.append(dict(candidate=name,name=r['name'],loss_mw=r['loss_mw'],economic_cost=r['economic_cost'],p_margin_mw=p,q_margin_mvar=q))
 lines.append(f"| {name} | {r['loss_mw']:.6f} | {r['economic_cost']:.3f} | {p:.4g} | {q:.4g} |")
lines+=['','## Decision and implications','',
'All 75 candidate/objective-lane × limit-variant × demand contracts are feasible from retained or new witnesses. Fresh solves produce 410/450 accepted and physically verified points; all 450 saved states replay without discrepancies. The 40 failed runs comprise 22 iteration limits and 18 local-infeasible terminations on contracts with known witnesses. No recalibration, slope change, saturation clipping, tap movement or shunt movement was needed to find feasible redispatches.','',
'Every previously verified candidate point violates at least one original active-power bound; all satisfy the original Q limits. This distinguishes a failed saved operating point from an infeasible fixed controller. At nominal demand with both limits restored, the minimum active-power margin is effectively zero while the minimum Q margin is at least about 4.85 MVAr for the reported points.','',
'Performance gains do not transfer unchanged. The loss-tuned tap+droop candidate has 1.108974 MW losses versus 1.080401 MW for the reference (2.64% worse), reversing its advantage under the relaxed study limits. The economic tap-only candidate costs 14677.382 versus 14816.644 source units for the reference, a 0.94% saving rather than the earlier 75.86%. Its losses are 4.759232 versus 4.618602 MW. Cost taps+shunt gives 14677.202 units and 4.735871 MW, a small further cost benefit with one direct solver failure.','',
'Retain the Pmin=0/symmetric-Q setup as the requested main S1 study and preserve this original-limit comparison as a separate qualification case. Keep uniform-8% source equipment as the reference; carry the economic tap-only candidate as the strongest tested operational comparator because it passes all 30 original-P/Q runs. Do not describe the loss-tuned design as an improvement under original limits.','',
'The 14-bus workflow now has checked sensitivity, objective/control comparisons, frozen-demand qualification and original-limit compatibility. Freeze this evidence before the 500-bus phase. Transfer the workflow, not the numerical settings: begin with the 500-bus source OPF and original/study limit audit, calibrate its own controllers, then run a small fixed-controls matrix with all three solvers and the same three-outcome gate before broader control searches. Any capability-clipped or newly recalibrated curves are separate models needing their own qualification.','']
lines+=['','Detailed source limits, initial-state hashes, prior point violations, source OPF solutions, every final state and both layers of physical validation are retained. Original-limit margins are in original_limit_checks; legacy generator tables retain the study bounds and must not be read as the active overlay bounds. Solver failures remain unresolved unless a retained/fresh witness proves feasibility; no global infeasibility certificates were computed.','']
(out/'report.md').write_text('\n'.join(lines));(out/'gates.json').write_text(json.dumps(gates,indent=2)+'\n')
summary=dict(cells=450,source_opfs=30,verified=sum(r['point_pass'] for r in rows),accepted=sum(r['accepted'] for r in rows),models_feasible=sum(g['status']=='feasible' for g in gates),models_unresolved=sum(g['status']=='unresolved' for g in gates),nominal_original_limits=best)
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2))
