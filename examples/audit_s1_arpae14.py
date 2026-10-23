"""Independent complex-arithmetic AC replay of accepted S1 results; no solver calls."""
from pathlib import Path
import json, cmath, math
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/s1_arpae14_stress'
c=json.loads((OUT/'source-study.json').read_text())['data']['case']; net=c['network']; base=c['base_power']
def audit(path,load_factor=1.0):
 d=json.loads(path.read_text());st=d['opf']['state']; v={b['id']:cmath.rect(m,a) for b,m,a in zip(net['buses'],st['vm'],st['va'])}; balance={k:0j for k in v}
 gen=[]
 for g,p,q in zip(c['generators'],st['pg'],st['qg']):
  balance[g['bus_id']]+=complex(p,q)
  gen.append(dict(id=g['id'],bus=g['bus_id'],online=g['available'],Pmin_MW=g['p_min']*base,Pmax_MW=g['p_max']*base,Pg_MW=p*base,Qmin_Mvar=g['q_min']*base,Qmax_Mvar=g['q_max']*base,Qg_Mvar=q*base))
 for l in c['loads']:balance[l['bus_id']]-=load_factor*complex(l['p'],l['q'])
 for s in net['shunts']:
  if s['available']:balance[s['bus_id']]-=complex(s['conductance'],-s['susceptance'])*abs(v[s['bus_id']])**2
 for b in net['banks']:
  if b['available']:
   bs=d['susceptances'].get(str(b['id']),sum(x*y for x,y in zip(b['state'],b['step_susceptances'])))
   balance[b['bus_id']]+=1j*bs*abs(v[b['bus_id']])**2
 branches=[]
 for b in net['branches']:
  if not b['available']:continue
  vf,vt=v[b['from_bus']],v[b['to_bus']]; t=cmath.rect(d['taps'][str(b['id'])],b['phase_shift']); y=1/complex(b['resistance'],b['reactance']); yc=1j*b['charging']/2
  sf=vf*((y+yc)/abs(t)**2*vf-y/t.conjugate()*vt).conjugate(); stt=vt*((y+yc)*vt-y/t*vf).conjugate()
  balance[b['from_bus']]-=sf;balance[b['to_bus']]-=stt
  branches.append(dict(id=b['id'],kind=b['kind'],from_bus=b['from_bus'],to_bus=b['to_bus'],rating_MVA=b['thermal_limit']*base,from_MVA=abs(sf)*base,to_MVA=abs(stt)*base,margin_MVA=(b['thermal_limit']-max(abs(sf),abs(stt)))*base,tap=abs(t)))
 buses=[dict(id=b['id'],Vmin=b['v_min'],Vmax=b['v_max'],V=abs(v[b['id']]),lower_margin=abs(v[b['id']])-b['v_min'],upper_margin=b['v_max']-abs(v[b['id']])) for b in net['buses']]
 generator_violation=max(max(g['Pmin_MW']-g['Pg_MW'],g['Pg_MW']-g['Pmax_MW'],g['Qmin_Mvar']-g['Qg_Mvar'],g['Qg_Mvar']-g['Qmax_Mvar'],0.)/base if g['online'] else max(abs(g['Pg_MW']),abs(g['Qg_Mvar']))/base for g in gen)
 residual=max(max(abs(z.real),abs(z.imag)) for z in balance.values()); thermal=min(b['margin_MVA']/base for b in branches); voltage=min(min(b['lower_margin'],b['upper_margin']) for b in buses)
 return dict(generator_violation_pu=generator_violation,power_balance_max_pu=residual,branch_min_margin_MVA=thermal*base,voltage_min_margin_pu=voltage,valid=generator_violation<=1e-5 and residual<=1e-5 and thermal>=-1e-5 and voltage>=-1e-5,generators=gen,buses=buses,branches=branches)
records=[]
for folder in [OUT,OUT/'followup']:
 if not (folder/'summary.json').exists():continue
 for r in json.loads((folder/'summary.json').read_text()):
  if not r['valid']:continue
  a=audit(folder/(r['name']+'-design.json'),r['tags'].get('load_factor',1.0));records.append(dict(name=r['name'],block=folder.name,**{k:v for k,v in a.items() if k not in ['generators','buses','branches']}))
assert all(r['valid'] for r in records),[r for r in records if not r['valid']]
(OUT/'independent_ac_replay.json').write_text(json.dumps(records,indent=2)+'\n')
rows=json.loads((OUT/'summary.json').read_text());best=min((r for r in rows if r['valid'] and r['tags']['block']=='matrix' and r['tags']['family']=='joint' and r['tags']['load_factor']==1),key=lambda r:r['objective'])
a=audit(OUT/(best['name']+'-design.json'));a['run']=best['name'];a['objective']=best['objective'];(OUT/'nominal_joint_thresholds.json').write_text(json.dumps(a,indent=2)+'\n')
print(f"Independent AC replay passed {len(records)}/{len(records)} accepted results. Worst power balance: {max(r['power_balance_max_pu'] for r in records):.3g} pu")
print('Nominal joint active limits:',[b['id'] for b in a['buses'] if b['upper_margin']<1e-5],[b['id'] for b in a['branches'] if b['margin_MVA']<1e-3])
