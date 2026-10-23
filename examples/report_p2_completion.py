"""Summarize saved evidence; never starts or tunes a solver."""
import json, math, statistics
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/p2_completion'
def read(p): return json.loads(p.read_text())
rows=read(OUT/'public_run/summary.json'); results=[]
for row in rows:
 d=OUT/'public_run'/row['id'];r={'id':row['id'],'base_valid':row['base_valid'],'error':row.get('error')}
 datasets={(a['rep'],a['policy']):read(d/a['path']) for a in row['attempts']}
 if len(datasets)!=9:
  r['complete']=False;results.append(r);continue
 r['complete']=True
 unresolved=set();classes={};differences=[];maxdiff=0
 for (rep,policy),data in datasets.items():
  if 'exhaustive' in policy:
   for a in data['assessments']:
    id=a['rank']['contingency_id'];cl=a['rank']['classification'];classes.setdefault(id,set()).add(cl)
    if cl!='accepted': unresolved.add(id)
 for rep in range(1,4):
  for a,b in zip(datasets[rep,'serial_exhaustive']['assessments'],datasets[rep,'threaded_exhaustive']['assessments']):
   if a['rank']['classification']!=b['rank']['classification']:differences.append([rep,a['rank']['contingency_id']])
   if a['rank']['classification']==b['rank']['classification']=='accepted' and a['exact_assessment'] and b['exact_assessment']:
    for id,s in a['exact_assessment']['result']['states'].items():
     t=b['exact_assessment']['result']['states'][id]
     for k in ['vm','va','pg','qg']:
      maxdiff=max(maxdiff,max(abs(x-y) for x,y in zip(s[k],t[k])))
 screened={a['rank']['contingency_id'] for a in datasets[1,'serial_guarded']['assessments'] if a['outcome']=='screened'}
 scores=read(d/'scores.json');eligible={s['contingency_id'] for s in scores};targets=unresolved&eligible
 r.update(total=len(classes),unresolved=len(unresolved),screened=len(screened),misses=sorted(screened&unresolved),unstable=[k for k,v in classes.items() if len(v)>1],parallel_differences=differences,max_accepted_state_difference=maxdiff)
 r['ranking']=[{'fraction':f,'budget':math.ceil(f*len(scores)),'target_count':len(targets),'recall':len({s['contingency_id'] for s in scores[:math.ceil(f*len(scores))]}&targets)/len(targets) if targets else None} for f in [.1,.25,.5,1.]]
 r['performance']={p:{key:statistics.median(a[source] for a in row['attempts'] if a['policy']==p and a['rep']>=2) for key,source in [('seconds','seconds'),('allocated_bytes','bytes')]} for p in ['serial_exhaustive','threaded_exhaustive','serial_guarded']}
 r['process_high_water_rss_bytes']=max(a['maxrss'] for a in row['attempts'])
 if (d/'warm_summary.json').exists():
  warm=read(d/'warm_summary.json');r['warm_starts']={p:{'runs':sum(a['policy']==p for a in warm),'valid':sum(a['valid'] for a in warm if a['policy']==p),'seconds':sum(a['seconds'] for a in warm if a['policy']==p)} for p in ['flat','base','neighbour']}
 if (d/'full_enumeration.json').exists():
  full=read(d/'full_enumeration.json');r['full_enumeration']={'valid':full['report']['valid'],'seconds':full['seconds'],'termination_status':full['result']['termination_status']}
 if (d/'scenario_addition.json').exists():
  a=read(d/'scenario_addition.json');r['scenario_addition']={k:a['result'].get(k) for k in ['status','full_n1_accepted','eligible_accepted']};r['scenario_addition']['seconds']=a['seconds'];r['scenario_addition']['rounds']=len(a['result']['iterations'])
 results.append(r)
(OUT/'RESULTS.json').write_text(json.dumps({'public':results,'timing_note':'Medians of repetitions 2–3; process RSS is cumulative high-water mark, not per-policy peak; allocations are cumulative Julia allocations.','ranking_target':'Union of nonaccepted exhaustive outcomes, not proven infeasibility.'},indent=2)+'\n')
print(json.dumps(results,indent=2))
# Optional follow-up runs have their own frozen protocols and never replace failures.
combined=read(OUT/'RESULTS.json')
scale=[]
for d in sorted((OUT/'scale_run').glob('[0-9]*')) if (OUT/'scale_run').exists() else []:
 r={'buses':int(d.name)}
 if (d/'timings.json').exists():
  ts=read(d/'timings.json');r['performance']={str(w):{'seconds':statistics.median(a['seconds'] for a in ts if a['workers']==w and a['rep']>=2),'allocated_bytes':statistics.median(a['bytes'] for a in ts if a['workers']==w and a['rep']>=2)} for w in [1,2]}
  differences=[];maxdiff=0;outcomes={}
  for rep in [1,2,3]:
   for a,b in zip(read(d/f'{rep}-workers1.json')['assessments'],read(d/f'{rep}-workers2.json')['assessments']):
    id=a['rank']['contingency_id'];outcomes[id]=a['rank']['classification']
    if a['rank']['classification']!=b['rank']['classification']:differences.append([rep,id])
    if a['rank']['classification']==b['rank']['classification']=='accepted':
     for id,s in a['exact_assessment']['result']['states'].items():
      t=b['exact_assessment']['result']['states'][id]
      maxdiff=max(maxdiff,max(abs(x-y) for k in ['vm','va','pg','qg'] for x,y in zip(s[k],t[k])))
  r.update(outages=len(outcomes),accepted=sum(v=='accepted' for v in outcomes.values()),parallel_differences=differences,max_accepted_state_difference=maxdiff,process_high_water_rss_bytes=max(a['maxrss'] for a in ts))
 for file,key,policies in [('warm_summary.json','scenario_warm_starts',['flat','base','neighbour']),('design_warm_summary.json','design_warm_starts',['flat','base_scenario','neighbouring_design'])]:
  if (d/file).exists():
   ws=read(d/file);r[key]={p:{'runs':sum(a['policy']==p for a in ws),'valid':sum(a['valid'] for a in ws if a['policy']==p),'warm_seconds':statistics.median(sum(a['seconds'] for a in ws if a['policy']==p and a['rep']==rep) for rep in [2,3])} for p in policies}
   if key=='design_warm_starts':
    objs=[a['objective'] for a in ws if a['valid']];r['valid_design_objective_spread']=max(objs)-min(objs) if objs else None
 for file,key in [('full_enumeration.json','full_enumeration'),('scenario_addition.json','scenario_addition')]:
  if (d/file).exists():
   a=read(d/file);r[key]={'seconds':a['seconds'],'bytes':a['bytes']}
   if key=='full_enumeration':r[key].update(valid=a['report']['valid'],objective=a['result']['objective'],status=a['result']['termination_status'])
   else:
    r[key].update({k:a['result'].get(k) for k in ['status','full_n1_accepted','eligible_accepted']});r[key]['rounds']=len(a['result']['iterations']);r[key]['final_exhaustive_audit']=a['result']['iterations'][-1]['exhaustive_audit'];r[key]['objective']=a['result']['iterations'][-1]['design']['result']['objective']
 scale.append(r)
combined['scale_regression']=scale
if (OUT/'public_design/full_enumeration.json').exists():
 a=read(OUT/'public_design/full_enumeration.json');combined['public_design']={'full_enumeration':{'valid':a['report']['valid'],'status':a['result']['termination_status'],'seconds':a['seconds']}}
 if (OUT/'public_design/scenario_addition.json').exists():
  a=read(OUT/'public_design/scenario_addition.json');combined['public_design']['scenario_addition']={k:a['result'].get(k) for k in ['status','full_n1_accepted','eligible_accepted']};combined['public_design']['scenario_addition'].update(seconds=a['seconds'],rounds=len(a['result']['iterations']))
(OUT/'RESULTS.json').write_text(json.dumps(combined,indent=2)+'\n')
if (OUT/'scale_challenge/scenario_addition.json').exists():
 f=read(OUT/'scale_challenge/full_enumeration.json');a=read(OUT/'scale_challenge/scenario_addition.json')
 combined['scale_challenge']={'full_enumeration':{'valid':f['report']['valid'],'seconds':f['seconds'],'objective':f['result']['objective'],'status':f['result']['termination_status']},'scenario_addition':{k:a['result'][k] for k in ['status','eligible_accepted','full_n1_accepted']}}
 combined['scale_challenge']['scenario_addition'].update(seconds=a['seconds'],rounds=len(a['result']['iterations']),added_by_round=[x['added_ids'] for x in a['result']['iterations']],final_exhaustive_audit=a['result']['iterations'][-1]['exhaustive_audit'],objective=a['result']['iterations'][-1]['design']['result']['objective'])
 (OUT/'RESULTS.json').write_text(json.dumps(combined,indent=2)+'\n')
(OUT/'RESULTS.json').write_text(json.dumps(combined,indent=2)+'\n')
