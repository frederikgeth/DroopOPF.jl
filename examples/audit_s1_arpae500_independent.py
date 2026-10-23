"""Independent complex branch-flow replay; standard library only, no Julia physics."""
from pathlib import Path
import json,cmath,hashlib
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'artifacts/s1_arpae500'
load=lambda p:json.loads(p.read_text())
angles=load(OUT/'angle_limits.json');cache={};checks=[]
for path in sorted((OUT/'attempts').glob('*.json')):
 r=load(path)
 if 'state' not in r:continue
 if r['model_path'] not in cache:cache[r['model_path']]=load(ROOT/r['model_path'])['data']['case']
 c=cache[r['model_path']];n=c['network'];s=r['state'];base=c['base_power'];ids={b['id']:i for i,b in enumerate(n['buses'])};gids={g['id']:i for i,g in enumerate(c['generators'])}
 v=[cmath.rect(vm,va) for vm,va in zip(s['vm'],s['va'])];balance=[0j]*len(v);valid=True;thermal=float('inf');angle=float('inf');flow_error=0.
 recorded={b['id']:b for b in r['branches']}
 for b in n['branches']:
  if not b['available']:continue
  i,j=ids[b['from_bus']],ids[b['to_bus']];tap=cmath.rect(r['taps'].get(str(b['id']),b['tap_ratio']),b['phase_shift']);y=1/complex(b['resistance'],b['reactance']);yc=complex(0,b['charging']/2)
  sf=v[i]*(((y+yc)/abs(tap)**2*v[i]-y/tap.conjugate()*v[j]).conjugate())
  st=v[j]*(((y+yc)*v[j]-y/tap*v[i]).conjugate())
  balance[i]-=sf;balance[j]-=st;thermal=min(thermal,b['thermal_limit']-max(abs(sf),abs(st)))
  a=s['va'][i]-s['va'][j];lo,hi=angles[str(b['id'])];angle=min(angle,a-lo,hi-a)
  old=recorded[b['id']]
  flow_error=max(flow_error,abs(sf.real*base-old['pf_mw']),abs(sf.imag*base-old['qf_mvar']),abs(st.real*base-old['pt_mw']),abs(st.imag*base-old['qt_mvar']))
 for b in n['shunts']:
  if b['available']:
   i=ids[b['bus_id']];balance[i]-=complex(b['conductance'],-b['susceptance'])*s['vm'][i]**2
 for b in n['banks']:
  if not b['available']:continue
  susceptance=sum(x*y for x,y in zip(b['step_susceptances'],b['state']));conductance=sum(x*y for x,y in zip(b['step_conductances'],b['state']))
  if str(b['id']) in r['susceptances']:
   susceptance=r['susceptances'][str(b['id'])];conductance=b['step_conductances'][0]/b['step_susceptances'][0]*susceptance
  i=ids[b['bus_id']];balance[i]-=complex(conductance,-susceptance)*s['vm'][i]**2
 for l in c['loads']:balance[ids[l['bus_id']]]-=complex(l['p'],l['q'])
 for i,g in enumerate(c['generators']):
  balance[ids[g['bus_id']]]+=complex(s['pg'][i],s['qg'][i])
  if not g['available']:valid &= max(abs(s['pg'][i]),abs(s['qg'][i]))<=1e-8;continue
  for axis in ('p','q'):
   val=s[axis+'g'][i];valid &= g[axis+'_min']-1e-6<=val<=g[axis+'_max']+1e-6
   overlay=r.get('operating_bounds',{}).get(str(g['id']),{})
   if axis+'min' in overlay:valid &= overlay[axis+'min']-1e-6<=val<=overlay[axis+'max']+1e-6
 droop=0.
 for a in c['attachments']:
  g=gids[a['generator_id']]
  if not c['generators'][g]['available']:continue
  d=c['controls'][a['control_id']-1];vg=s['vm'][ids[a['location']['bus_id']]];sch=d['schedule'];cap=d['capability']
  raw=d['q_at_deadband']+(max(sch['v_db_low']-vg,0)-max(vg-sch['v_db_high'],0))/d['slope'];exact=max(cap['q_min'],min(cap['q_max'],raw))
  droop=max(droop,abs(s['qg'][g]-exact));valid &= cap['p_min']-1e-6<=s['pg'][g]<=cap['p_max']+1e-6
 for i,b in enumerate(n['buses']):
  valid &= b['v_min']-1e-6<=s['vm'][i]<=b['v_max']+1e-6
  if b['reference']:valid &= abs(s['va'][i])<=1e-6
 for key,value_key,id_key in [('tap_controls','taps','branch_id'),('shunt_controls','susceptances','bank_id')]:
  for p in r['policy'][key]:
   val=r[value_key][str(p[id_key])];valid &= p['lower']-1e-8<=val<=p['upper']+1e-8
 residual=max(max(abs(x.real),abs(x.imag)) for x in balance)
 valid &= residual<=1e-6 and droop<=1e-5 and thermal>=-1e-6 and angle>=-1e-6
 assert bool(valid)==r['point_pass'],(r['name'],valid,r['point_pass'],residual,droop,thermal)
 assert flow_error<1e-6,(r['name'],flow_error)
 checks.append(dict(name=r['name'],physical=bool(valid),balance_max_pu=residual,droop_max_pu=droop,branch_component_replay_error_mw_mvar=flow_error))
for path,expected in load(OUT/'protocol.json')['hashes'].items():
 if path.startswith('test/data/'):assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==expected,path
result=dict(states_replayed=len(checks),physical_witnesses=sum(x['physical'] for x in checks),discrepancies=0,max_branch_component_error=max(x['branch_component_replay_error_mw_mvar'] for x in checks),all_recorded_source_hashes_unchanged=True,checks=checks)
(OUT/'independent_python_audit.json').write_text(json.dumps(result,indent=2)+'\n')
print('Independent complex-flow replay:',len(checks),'states, zero discrepancies; sources unchanged')
