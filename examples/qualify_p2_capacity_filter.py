"""Replay the fail-closed capacity filter against sealed S2-compatible evidence."""
import json,sys,hashlib
from pathlib import Path
from p2_s2_capacity_filter import capacity_certificate
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'artifacts/p2_open_gates_20261022/capacity-filter'
load=lambda p:json.loads(Path(p).read_text())
events=load(ROOT/'artifacts/p2_s2_implementation_20261022/500/catalogue.json')
sources=[]
for lane in (ROOT/'artifacts/p2_s2_multidemand_20261022/s2-allowance',ROOT/'artifacts/p2_remaining_qualification_20261022/heldout-500'):
 for row in load(lane/'RESULTS.json')['rows']:
  if not row['result']['accepted']:continue
  rnd=row['result']['rounds'][-1]
  sources.append(ROOT/rnd['master']['folder'])
rows=[];hashes={}
for folder in sources:
 study=load(folder/'controller-solve.json')['data'];point=load(folder/'point-solve.json')
 assert load(folder/'summary.json')['accepted']
 for name in ('controller-solve.json','point-solve.json','summary.json'):
  hashes[str((folder/name).relative_to(ROOT))]=hashlib.sha256((folder/name).read_bytes()).hexdigest()
 for base in point['states']:
  if base['id']!='base':continue
  results=[dict(event=e['id'],**capacity_certificate(study,base,e,base['factor'],active_response='s2_proportional_v1')) for e in events]
  excluded=[r['event'] for r in results if r['certified_infeasible']]
  assert not excluded,('False exclusion of exhaustively feasible reference',base['factor'],excluded)
  rows.append(dict(factor=base['factor'],source=str(folder.relative_to(ROOT)),outages=len(results),false_exclusions=excluded,results=results))
stress=[]
for label in ('generator-14','generator-14-max'):
 folder=ROOT/'artifacts/p2_open_gates_20261022/stress-base'/label
 study=load(folder/'controller-solve.json')['data'];point=load(folder/'point-solve.json');assert load(folder/'summary.json')['accepted']
 base=point['states'][0];results=[dict(event=e['id'],**capacity_certificate(study,base,e,active_response='s2_proportional_v1')) for e in events]
 stress.append(dict(base=str(folder.relative_to(ROOT)),certified_failures=sum(r['certified_infeasible'] for r in results),results=results))
 assert stress[-1]['certified_failures']>0
out=dict(positive_references=rows,stress_references=stress,source_hashes=hashes,
 policy='Exact S2 proportional fixed-preventive-base necessary condition; nonpositive gap routes to exact AC; no safe-outage skips',
 qualification='Certificate correctness under passive network and stated response bounds; no empirical failure recall for inconclusive cases',
 production_default_changed=False,s2_campaign_resumed=False)
OUT.mkdir(exist_ok=True);(OUT/'RESULTS.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps(dict(demands=len(rows),positive_outages=sum(r['outages'] for r in rows),false_exclusions=0,stress_certificates=sum(r['certified_failures'] for r in stress))))
