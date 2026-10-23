"""Report saved S1 500-bus attempts; no solves, no silent filtering of failures."""
from pathlib import Path
import json
from collections import defaultdict
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/s1_arpae500'
rows=[json.loads(p.read_text()) for p in sorted((OUT/'attempts').glob('*.json'))]
groups=defaultdict(list)
for r in rows:
 t=r['tags'];groups[(t.get('stage','unknown'),t.get('family',r['objective_kind']),t.get('factor',1.0))].append(r)
summary=[]
for (stage,family,f),rs in sorted(groups.items()):
 good=[r for r in rs if r['accepted']]
 best=min(good,key=lambda r:r['economic_cost'] if r['objective_kind']=='cost' else r['loss_mw']) if good else None
 summary.append(dict(stage=stage,family=family,factor=f,attempts=len(rs),accepted=len(good),physical=sum(r['point_pass'] for r in rs),best_name=best['name'] if best else None,loss_mw=best['loss_mw'] if best else None,economic_cost=best['economic_cost'] if best else None))
failures=[dict(name=r['name'],status=r.get('solver_status',r.get('error')),physical=r['point_pass'],checks=r.get('point_checks'),seconds=r.get('solve_wall_seconds')) for r in rows if not r['accepted']]
(OUT/'summary.json').write_text(json.dumps(dict(groups=summary,failures=failures,total_attempts=len(rows),accepted=sum(r['accepted'] for r in rows)),indent=2))
lines=['# S1 500-bus qualification results','','For the selected design, recovery conclusions, original-limit fixes and threshold summary, see the [500-bus qualification report](../../docs/src/s1_500_results.md). This ledger retains every attempt.','','All new runs are base-case S1. Source OPF/SCOPF results are preserved. Study limits use Pmin=0 and symmetric Q; no flat starts. Failed attempts remain visible.','','| Stage | Family / objective | Demand | Accepted / attempts | Physical witnesses | Best accepted loss (MW) | Economic cost |','|---|---|---:|---:|---:|---:|---:|']
for r in summary:
 loss='—' if r['loss_mw'] is None else f"{r['loss_mw']:.6f}"
 cost='—' if r['economic_cost'] is None else f"{r['economic_cost']:.3f}"
 lines.append(f"| {r['stage']} | {r['family']} | {100*r['factor']:g}% | {r['accepted']}/{r['attempts']} | {r['physical']} | {loss} | {cost} |")
lines+=['','## Retained unsuccessful attempts','','| Attempt | Native outcome | Physically verified |','|---|---|---|']
for r in failures:lines.append(f"| {r['name']} | {r['status']} | {r['physical']} |")
lines+=['','A failed local solve is unresolved unless an independent certificate establishes infeasibility. A verified point and successful solver termination are separate outcomes. Every attempt file contains its model/initialization fingerprint, budget, formulation, settings, residuals, bus/generator values and branch/transformer flows and limits.','']
(OUT/'REPORT.md').write_text('\n'.join(lines))
print('Attempts',len(rows),'accepted',sum(r['accepted'] for r in rows),'failures',len(failures))
for r in summary:print(r)

# Preserve the separately scored zero-deadband numerical follow-up.
from s1_zero_deadband_reporting import append_followup
append_followup(OUT/'REPORT.md', doc=False)
