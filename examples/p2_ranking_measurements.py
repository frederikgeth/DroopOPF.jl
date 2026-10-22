import os
"""Descriptive ranking against observed relief; no failure recall from all-pass data."""
import json,hashlib,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=Path(os.environ.get('P2_QUALIFICATION_OUTPUT',str(ROOT/'artifacts/p2_remaining_qualification_20261022')))
load=lambda p:json.loads(p.read_text())
f=OUT/'filtering/RESULTS.json'
if not f.exists():raise SystemExit('Filtering diagnostics not completed')
rows=[]
for diag in load(f)['rows']:
 if not diag['diagnostic_completed']:continue
 size=diag['size'];points=[]
 if size==14:points=[ROOT/'artifacts/p2_s2_implementation_20261022/14/full/point-solve.json']
 else:
  lane=ROOT/'artifacts/p2_s2_multidemand_20261022/s2-allowance';selected=next(r for r in load(lane/'RESULTS.json')['rows'] if r['factor']==1.)
  rnd=selected['result']['rounds'][-1];points=[ROOT/rnd['master']['folder']/'point-solve.json']
  scan=load(lane/f"stage-{selected['stage']}/500/progressive/round-{rnd['round']}/scan/scan.json")
  points += [ROOT/p/'point-solve.json' for p in sorted({r['path'] for r in scan['rows'] if r['path']})]
 values={}
 for p in points:
  for s in load(p)['states']:
   if s['factor']==1. and s['id']!='base':
    values[s['id']]=sum(float(v) for v in s['dr'].values())+sum(float(v) for v in s['shed'].values())
 order=diag['ranking_order'];assert set(order)==set(values)
 severity=sorted(order,key=lambda e:(-values[e],e))
 worst=set(severity[:max(1,math.ceil(.1*len(order)))])
 random_order=sorted(order,key=lambda e:hashlib.sha256(e.encode()).hexdigest())
 budgets=[]
 for fraction in (.1,.25,.5):
  n=math.ceil(fraction*len(order))
  budgets.append({'fraction':fraction,'evaluated':n,'observed_top_relief_recall':len(worst&set(order[:n]))/len(worst) if max(values.values())>min(values.values()) else None,'deterministic_hash_order_recall':len(worst&set(random_order[:n]))/len(worst) if max(values.values())>min(values.values()) else None})
 rows.append({'size':size,'outages':len(order),'failure_examples':0,'failure_recall':None,'relief_ranking_informative':max(values.values())>min(values.values()),'budgets':budgets,'max_observed_relief_pu':max(values.values())})
r={'rows':rows,'interpretation':'All references pass physical validation. Failure recall cannot be estimated. Relief is a feasible-witness observation, not minimum required relief or failure severity; ties can make this metric uninformative. Mixed heuristic scores have different units and remain advisory.'}
(OUT/'ranking-results.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
