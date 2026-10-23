"""Compare fixed absolute smoothing against the preserved default-smoothing grid."""
from pathlib import Path
from collections import defaultdict
import json
root=Path(__file__).resolve().parents[1]
out=root/'artifacts/s1_arpae14_matched_sensitivity'
old=root/'artifacts/s1_arpae14_joint_sensitivity'
read=lambda p:[json.loads(s) for s in p.read_text().splitlines() if s.strip()]
rows=read(out/'rows.jsonl');previous=read(old/'rows.jsonl')
assert len(rows)==len({r['name'] for r in rows})==1080
assert not any('error' in r for r in rows)
assert sum('reused_from' in r for r in rows)==360
assert all(c['calibration_pass'] for c in json.loads((out/'configurations.json').read_text()))
count=lambda rs:sum(r['point_pass'] for r in rs)
accepted=lambda rs:sum(r['accepted'] for r in rs)
def groups(rs,keys):
 d=defaultdict(list)
 for r in rs:d[tuple(r['solver'] if k=='solver' else r['tags'][k] for k in keys)].append(r)
 return d
lines=['# S1 14-bus sensitivity with matched reactive smoothing','',
'Follow-up to the 1,080-cell exploratory grid. Ipopt/MadNLP use fixed absolute reactive smoothing of 1e-6 pu and voltage smoothing of 1e-6 pu. All 720 affected cells were rerun; the 360 unchanged exact-complementarity CCOpt cells were reused with explicit provenance. The previous artifacts remain intact.','',
'Factors and physical assumptions are unchanged: two definitions, five slope profiles, three total deadband widths (0/0.005/0.01 pu), nominal cost/loss calibration, demand-matched cost/loss initialization, 90/100/110% demand, three solvers; all five droops, taps and shunts fixed. Pmin=0 and symmetric Q limits; no flat starts. The S1 objective remains dispatch deviation.','',
'All six source seeds and 60 calibration witnesses pass the precursor checks. Six deliberately uncalibrated zero-Q controls are rejected before solving. Local failures remain unresolved; no global infeasibility certificate is claimed. Every nominal configuration has a feasible calibration witness even when a solver fails.','',
f'**Matched smoothing: {count(rows)}/1080 verified physical points; {accepted(rows)}/1080 also have successful solver termination.**','',
'## Calibration and definition','',
'| Definition | Calibration | Default: verified | Matched: verified | Matched: accepted |','|---|---|---:|---:|---:|']
oldgroups=groups(previous,['definition','calibration_objective'])
for k,rs in sorted(groups(rows,['definition','calibration_objective']).items()):
 lines.append(f'| {k[0]} | {k[1]} | {count(oldgroups[k])}/270 | {count(rs)}/270 | {accepted(rs)}/270 |')
lines+=['','## Loss-calibrated slope and deadband comparison','',
'Each cell is verified / solver-accepted out of 18 runs. Slope percentages use voltage change over the full Qmin-to-Qmax span.','',
'| Definition | G1–G5 profile | No deadband | 0.005 pu | 0.01 pu |','|---|---|---:|---:|---:|']
g=groups(rows,['definition','calibration_objective','profile','deadband_total_width_pu'])
for definition in ('zero_q_shifted','opf_q_centered'):
 for profile in ('uniform2','uniform4','uniform8','mixed24842','mixed84248'):
  cells=[g[(definition,'loss',profile,w)] for w in (0.,.005,.01)]
  lines.append('| '+definition+' | '+profile+' | '+' | '.join(f'{count(rs)} / {accepted(rs)}' for rs in cells)+' |')
lines+=['','## Solver and demand','', '| Solver | Demand | Verified | Accepted |','|---|---:|---:|---:|']
for (solver,f),rs in sorted(groups(rows,['solver','factor']).items()):
 lines.append(f'| {solver} | {f:.0%} | {count(rs)}/120 | {accepted(rs)}/120 |')
rank=[]
for (config,),rs in groups(rows,['config']).items():
 byfactor={str(f):count([r for r in rs if r['tags']['factor']==f]) for f in (.9,1.,1.1)}
 rank.append(dict(config=config,verified=count(rs),accepted=accepted(rs),demand_verified=byfactor,coverage=all(byfactor[str(f)]>0 or f==1. for f in (.9,1.,1.1))))
rank.sort(key=lambda r:(-r['coverage'],-r['accepted'],-r['verified'],r['config']))
lines+=['','## All configurations','', '| Configuration | 90% | 100% | 110% | Verified | Accepted |','|---|---:|---:|---:|---:|---:|']
for r in rank:
 lines.append('| '+r['config']+' | '+' | '.join(str(r['demand_verified'][str(f)])+'/6' for f in (.9,1.,1.1))+f" | {r['verified']}/18 | {r['accepted']}/18 |")
lines+=['','With zero deadband the two definitions are identical exact physical laws. Matching absolute smoothing removes the Q-offset-dependent smoothing width, but expression graphs and finite-precision optimization trajectories still differ. Separate numerical results must not be interpreted as two distinct physical controllers. Deadband and slope conclusions apply to this tested grid, not a global controller optimum or held-out validation.','']
(out/'report.md').write_text('\n'.join(lines))
summary=dict(cells=len(rows),new_solves=720,reused_exact_cells=360,verified=count(rows),accepted=accepted(rows),coverage=sum(r['coverage'] for r in rank),ranking=rank)
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({k:v for k,v in summary.items() if k!='ranking'}))
