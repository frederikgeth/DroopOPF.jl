"""Local AVR power-flow diagnosis; Q caps relaxed only to measure required Q.
No OPF/SCOPF is run, and these states are never counted as valid study anchors.
"""
from pathlib import Path
import json,numpy as np
from scipy.optimize import root
repo=Path(__file__).resolve().parents[1];old=repo/'artifacts/p2_02_scale_guard';records=[]
for row in json.loads((old/'heldout/summary.json').read_text()):
 if row['base_valid']:continue
 case=json.loads((old/'planned_cases'/(row['id']+'.json')).read_text())['data']['case'];saved=json.loads((old/'heldout'/row['id']/'anchor.json').read_text())['state'];net=case['network'];n=len(net['buses']);index={b['id']:i for i,b in enumerate(net['buses'])};ref=next(i for i,b in enumerate(net['buses']) if b['reference']);gb=[index[g['bus_id']] for g in case['generators']];angles=[i for i in range(n) if i!=ref];pq=[i for i in range(n) if i not in gb];Y=np.zeros((n,n),complex);load=np.zeros(n,complex);generation=np.zeros(n)
 for b in net['branches']:
  if not b['available']:continue
  i,j=index[b['from_bus']],index[b['to_bus']];y=1/complex(b['resistance'],b['reactance']);a=b['tap_ratio']*np.exp(1j*b['phase_shift']);yc=.5j*b['charging'];Y[i,i]+=(y+yc)/abs(a)**2;Y[i,j]-=y/np.conj(a);Y[j,i]-=y/a;Y[j,j]+=y+yc
 for sh in net['shunts']:
  if sh['available']:Y[index[sh['bus_id']],index[sh['bus_id']]]+=complex(sh['conductance'],sh['susceptance'])
 for l in case['loads']:load[index[l['bus_id']]]+=complex(l['p'],l['q'])
 for g,p in zip(case['generators'],saved['pg']):generation[index[g['bus_id']]]+=p
 def state(x):
  va=np.zeros(n);va[angles]=x[:n-1];vm=np.ones(n);vm[pq]=x[n-1:];return vm*np.exp(1j*va)
 def residual(x):
  v=state(x);s=v*np.conj(Y@v);return np.r_[(generation-load.real-s.real)[angles],(-load.imag-s.imag)[pq]]
 initial=np.r_[np.array(saved['va'])[angles],np.array(saved['vm'])[pq]];solution=root(residual,initial,tol=1e-10);v=state(solution.x);s=v*np.conj(Y@v);required=[float(s[i].imag+load[i].imag) for i in gb];excess=[q-g['q_max'] for q,g in zip(required,case['generators'])]
 residual_max=float(np.max(np.abs(residual(solution.x))));assert solution.success and residual_max<1e-8
 records.append(dict(input=row['id'],diagnostic_only=True,solver='scipy nonlinear root, no optimization',relaxation='Only generator Q bounds are omitted; AVR 1.0, nonreference P dispatch, equipment and loads fixed. Reference P balances losses.',root_residual_max=residual_max,required_q=required,qmax=[g['q_max'] for g in case['generators']],max_q_excess=max(excess),violating_generators=[g['id'] for g,e in zip(case['generators'],excess) if e>1e-6],voltage_min=float(min(abs(v))),voltage_max=float(max(abs(v))),reference_p=float(s[ref].real+load[ref].real)))
(repo/'artifacts/p2_02_diagnosis/anchor_restoration.json').write_text(json.dumps(records,indent=2)+'\n');print([(r['input'],r['max_q_excess']) for r in records])
