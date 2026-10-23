from pathlib import Path
import json
from collections import defaultdict
root=Path(__file__).resolve().parents[1];out=root/'artifacts/s1_arpae14_confirmation'
rows=[json.loads(x) for x in (out/'rows.jsonl').read_text().splitlines()]
assert len(rows)==len({r['name'] for r in rows})==72
assert not any('error' in r for r in rows)
checks=json.loads((out/'source_precursors.json').read_text());assert len(checks)==4 and all(r['check']['valid'] for r in checks)
g=defaultdict(list)
for r in rows:g[(r['tags']['profile'],r['tags']['deadband_total_width_pu'])].append(r)
lines=['# Additional-demand confirmation','',
'Four fresh source cost/loss OPFs at 95/105% demand passed independent source feasibility checks. Candidate curves were selected from the earlier grid and copied unchanged from nominal loss calibration. No reference, slope or deadband was retuned to these demands. Taps/shunts remain fixed; all three solvers and both demand-matched OPF initializations are included. Absolute reactive and voltage smoothing are each 1e-6 pu for the smooth lanes.','',
'| G1–G5 profile | Total deadband, pu | Verified | Solver-accepted |','|---|---:|---:|---:|']
for (profile,width),rs in sorted(g.items()):lines.append(f"| {profile} | {width} | {sum(r['point_pass'] for r in rs)}/12 | {sum(r['accepted'] for r in rs)}/12 |")
lines+=['',f"Total: {sum(r['point_pass'] for r in rows)}/72 verified and {sum(r['accepted'] for r in rows)}/72 solver-accepted.",'',
'This is confirmation at two previously untested demand levels on the same 14-bus network, not validation on a new network or a guarantee between/beyond the sampled demands. Serialized-state replay is recorded separately in serialization_audit.json.','']
(out/'report.md').write_text('\n'.join(lines))
(out/'summary.json').write_text(json.dumps(dict(cells=72,verified=sum(r['point_pass'] for r in rows),accepted=sum(r['accepted'] for r in rows)),indent=2)+'\n')
