"""Independent replay of the open-gate continuation; never accepts initializers."""
import ast,cmath,hashlib,json,os
from pathlib import Path
from audit_p2_s2_numerics import audit
ROOT=Path(__file__).resolve().parents[1]
OUT=Path(os.environ.get('P2_QUALIFICATION_OUTPUT',str(ROOT/'artifacts/p2_open_gates_20261022')))
load=lambda p:json.loads(Path(p).read_text())
# Reuse the independently implemented terminal-flow resource calculation without
# importing the older campaign's top-level runner or writing into its sealed root.
source=ROOT/'examples/audit_p2_remaining_qualification.py'
node=next(n for n in ast.parse(source.read_text()).body if isinstance(n,ast.FunctionDef) and n.name=='resource_totals')
space={'cmath':cmath};exec(compile(ast.Module(body=[node],type_ignores=[]),str(source),'exec'),space)
resource_totals=space['resource_totals']
def check_attempt(p):
 p=Path(p)
 if not (p/'summary.json').exists():return {'accepted':False,'incomplete':True,'caps_checked':False}
 c=load(p/'contract.json');summary=load(p/'summary.json')
 if not (p/'point-solve.json').exists():
  assert not summary['accepted'];return {'accepted':False,'incomplete':False,'caps_checked':False}
 try:point=load(p/'point-solve.json')
 except json.JSONDecodeError:
  assert not summary['accepted'];return {'accepted':False,'incomplete':True,'caps_checked':False}
 record=point['record']
 assert record==summary['record']==load(p/'stages.json')[-1],str(p)
 assert record['native_success']==(record['status'] in ('LOCALLY_SOLVED','OPTIMAL','ALMOST_LOCALLY_SOLVED')),str(p)
 checked=audit(p);assert checked['accepted']==summary['accepted'],str(p)
 caps_checked=False
 if summary['accepted']:
  totals=resource_totals(load(p/'controller-solve.json')['data'],point)
  if c.get('resource_caps'):
   assert all(totals[k]<=cap+1e-6 for k,cap in c['resource_caps'].items()),str(p)
   caps_checked=True
  if c.get('objective_kind') in ('shedding','dr'):
   assert abs(record['objective']-totals[c['objective_kind']])<=1e-7,str(p)
 return {'accepted':summary['accepted'],'incomplete':False,'caps_checked':caps_checked}

def main():
 result={'accepted_replayed':0,'unresolved_replayed':0,'incomplete_attempts':[],'resource_caps_checked':0,'native_status_consistent':True,'cold_catalogues':{}}
 for contract_path in sorted(OUT.rglob('contract.json')):
  p=contract_path.parent;checked=check_attempt(p)
  if checked['incomplete']:result['incomplete_attempts'].append(str(p.relative_to(ROOT)))
  elif checked['accepted']:result['accepted_replayed']+=1
  else:result['unresolved_replayed']+=1
  result['resource_caps_checked']+=checked['caps_checked']
 for name in ('cold-catalogue','cold-hybrid-catalogue'):
  p=OUT/name/'RESULTS.json'
  if not p.exists():continue
  d=load(p);observed=[];accepted=[];base_reference=None;curve_reference=None
  for row in d['rows']:
   observed.extend(row['events'])
   assert not row['post_outage_oracle_used']
   if not row['accepted']:continue
   accepted.extend(row['events'])
   selected=next(ROOT/q for q in reversed(row['paths']) if load(ROOT/q/'summary.json')['accepted'])
   c=load(selected/'contract.json');point=load(selected/'point-solve.json')
   assert c['fixed_base'] and c['fixed_controller'] and c['factors']==[1.]
   assert set(c['outages'])==set(row['events'])
   base=next(r for r in point['states'] if r['id']=='base')
   base={k:base[k] for k in ('state','taps','banks')}
   curves=load(selected/'controller-solve.json')['data']['case']['controls']
   if base_reference is None:base_reference=base;curve_reference=curves
   assert base==base_reference and curves==curve_reference
  assert len(observed)==len(set(observed)),name
  expected=set(load(OUT/name/'protocol.json')['events'])
  assert set(observed)<=expected
  if d['complete']:assert set(observed)==expected and len(expected)==389
  result['cold_catalogues'][name]={'attempted':len(observed),'accepted':len(accepted),'complete':d['complete'],
   'full_native_physical_pass':d['complete'] and set(accepted)==expected,'post_outage_oracle_used':False}
 result['resource_auditor_sha256']=hashlib.sha256(source.read_bytes()).hexdigest()
 (OUT/'validation-summary.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result,indent=2))

if __name__=='__main__':main()
