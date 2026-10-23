"""Rank diagnostic candidates from rejected iterates; no infeasibility inference."""
import json,math
from pathlib import Path
from s2_followup_physics import check_case
repo=Path(__file__).resolve().parents[1];prior=repo/'artifacts/p2_mixed_limit_aware_20261023';root=repo/'artifacts/p2_targeted_relaxations_20261023'
rows={}
for eid,rel in [('branch_21','resolutions-full-topology/branch_21-full-topology-start'),('branch_36','resolutions/branch_36-topology-start'),('branch_562','resolutions/branch_562-topology-start')]:
 folder=prior/rel;r=json.loads((folder/'result.json').read_text())['data'];contract=json.loads((folder/'contract.json').read_text())
 therm={};volt={};circles={};balances=[]
 for t in [1,2]:
  study=json.loads((folder/f'period-{t+1}.json').read_text())['data'];c=study['case'];event=next(e for e in study['contingencies'] if e['id']==eid)
  for b in c['network']['branches']:
   if b['id'] in event['branch_ids']:b['available']=False
  p=r['periods'][t];state=p['states'][eid]
  a=check_case(c,state,p['tap_settings'][eid],p['shunt_settings'][eid],contract['angles'])
  ranked=sorted([dict(id=b['id'],kind=b['kind'],loading=a['branch_max_terminal_s_pu'][str(b['id'])]/b['thermal_limit']) for b in c['network']['branches'] if b['available']],key=lambda x:-x['loading'])
  for x in ranked[:5]:
   if x['loading']>.995 and x['loading']>therm.get(x['id'],{}).get('loading',0):therm[x['id']]=x
  for i,b in enumerate(c['network']['buses']):
   margin=min(state['vm'][i]-b['v_min'],b['v_max']-state['vm'][i])
   if margin<1e-4:volt[b['id']]=dict(id=b['id'],margin=margin,vm=state['vm'][i],lower=b['v_min'],upper=b['v_max'])
  for i,g in enumerate(c['generators']):
   if g['available'] and g.get('s_rated'):
    excess=math.hypot(state['pg'][i],state['qg'][i])-g['s_rated']
    if excess>1e-6:circles[g['id']]=dict(id=g['id'],excess_pu=excess,rating=g['s_rated'])
  balances.append(dict(period=t+1,top_bus_mismatches=sorted(a['bus_balance'],key=lambda x:-max(abs(x['p_pu']),abs(x['q_pu'])))[:8]))
 rows[eid]=dict(thermal_candidates=list(therm.values()),voltage_candidates=list(volt.values()),generator_candidates=list(circles.values()),balance_diagnostics=balances)
root.mkdir(exist_ok=True)
(root/'relaxation-candidates.json').write_text(json.dumps(dict(role='Candidate selection from unconverged states, not proof of necessary relaxation',outages=rows),indent=2)+'\n')
print(json.dumps({k:{name:[x['id'] for x in v[name]] for name in ['thermal_candidates','voltage_candidates','generator_candidates']} for k,v in rows.items()},indent=2))
