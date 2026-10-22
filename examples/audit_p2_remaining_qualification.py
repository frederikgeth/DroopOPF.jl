import os
"""Independently replay fresh qualification records and frozen-controller identity."""
import json,sys,cmath
from pathlib import Path
from audit_p2_s2_numerics import audit
ROOT=Path(__file__).resolve().parents[1]
OUT=Path(os.environ.get('P2_QUALIFICATION_OUTPUT',str(ROOT/'artifacts/p2_remaining_qualification_20261022')))
def load(p):return json.loads(p.read_text())
def resource_totals(study,point):
 totals={'shedding':0.,'dr':0.,'emergency':0.}
 for row in point['states']:
  totals['shedding']+=sum(row['shed'].values());totals['dr']+=sum(row['dr'].values())
  if row['id']=='base':continue
  net=study['case']['network'];idx={b['id']:i for i,b in enumerate(net['buses'])}
  totals['emergency']+=sum((max(b['v_min']-row['state']['vm'][i],0)+max(row['state']['vm'][i]-b['v_max'],0))/.05 for i,b in enumerate(net['buses']))
  v=[cmath.rect(m,a) for m,a in zip(row['state']['vm'],row['state']['va'])]
  for b in net['branches']:
   if not b['available'] or row['id']==f"branch_{b['id']}":continue
   i,j=idx[b['from_bus']],idx[b['to_bus']]
   tap=cmath.rect(row['taps'].get(str(b['id']),b['tap_ratio']),b['phase_shift'])
   y=1/complex(b['resistance'],b['reactance']);yc=complex(0,b['charging']/2)
   sf=v[i]*(((y+yc)/abs(tap)**2*v[i]-y/tap.conjugate()*v[j]).conjugate())
   st=v[j]*(((y+yc)*v[j]-y/tap*v[i]).conjugate())
   totals['emergency']+=sum(max(abs(z)/b['thermal_limit']-1,0) for z in (sf,st))
 return totals
def check_folder(p):
 summary=load(p/'summary.json')
 if not (p/'point-solve.json').exists():
  assert not summary['accepted']
  return {'accepted':False,'physical_valid':False,'reason':'No extractable native point'}
 point=load(p/'point-solve.json');record=point['record']
 assert record==summary['record']==load(p/'stages.json')[-1],'Native record mismatch'
 assert record['native_success']==(record['status'] in ('LOCALLY_SOLVED','OPTIMAL','ALMOST_LOCALLY_SOLVED')),'Native success/status mismatch'
 a=audit(p)
 assert a['accepted']==summary['accepted'],str(p)
 c=load(p/'contract.json')
 if a['accepted'] and c.get('resource_caps'):
  totals=resource_totals(load(p/'controller-solve.json')['data'],load(p/'point-solve.json'))
  assert all(totals[k]<=cap+1e-6 for k,cap in c['resource_caps'].items()),'Resource priority cap violated'
 if (p/'initialization.json').exists():
  starts=load(p/'initialization.json');assert starts['policy']==c['initialization']
  if starts['policy']=='flat':
   post=[r for r in starts['states'] if r['id']!='base']
   assert post and any(r['vm'] for r in post)
   assert all(all(v==1. for v in r['vm']) and all(v==0. for v in r['va']) for r in post)
 return a
result={'accepted_replayed':0,'unresolved_replayed':0,'heldout14_controller_verified':False}
paths=set()
for name in ('benchmarks','comparison','progressive-reference','priorities','fullcatalog-repeat','warm-recovery'):
 p=OUT/name/'RESULTS.json'
 if not p.exists():continue
 for r in load(p)['rows']:
  for path in r.get('paths',[r.get('path')]):
   if path:paths.add(ROOT/path)
paths.update(p.parent for p in (OUT/'design-14').rglob('contract.json'))
p=OUT/'heldout-14/RESULTS.json'
if p.exists():
 d=load(p);source=load(Path(d['source'])/'controller-solve.json')['data']['case']['controls']
 for row in d['rows']:
  q=ROOT/row['path'];paths.add(q)
  c=load(q/'contract.json');assert c['fixed_controller'] and c['factors']==[row['factor']]
  if row['accepted']:
   assert load(q/'controller-solve.json')['data']['case']['controls']==source
   states=load(q/'point-solve.json')['states'];assert len(states)==25
   assert {r['factor'] for r in states}=={row['factor']}
 result['heldout14_controller_verified']=True
p=OUT/'fullcatalog-repeat/RESULTS.json'
if p.exists():
 protocol=load(p.parent/'protocol.json');expected=set(protocol['catalogue'])
 assert len(expected)==389
 for row in load(p)['rows']:
  observed=[]
  for path in row['paths']:
   q=ROOT/path;c=load(q/'contract.json')
   if not load(q/'summary.json')['accepted']:continue
   point=load(q/'point-solve.json')
   assert c['fixed_base'] and c['fixed_controller'] and c['factors']==[1.]
   assert load(q/'controller-solve.json')['data']['case']['controls']==protocol['controller_reference']
   for state in point['states']:
    if state['id']=='base':assert all(state[k]==protocol['base_reference'][k] for k in ('state','taps','banks'))
   if load(q/'summary.json')['accepted']:observed.extend(c['outages'])
  assert len(observed)==len(set(observed))
  assert len(observed)==row['accepted_outages']
  if row['accepted']:assert set(observed)==expected
 result['fullcatalog_base_and_controller_verified']=True
for p in sorted(paths):
 a=check_folder(p)
 result['accepted_replayed' if a['accepted'] else 'unresolved_replayed']+=1
result['passed']=True
(OUT/'independent-audit.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
