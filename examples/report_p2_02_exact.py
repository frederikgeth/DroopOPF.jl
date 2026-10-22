"""Summarize preserved measurements and fresh exhaustive comparisons."""
import json,statistics
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; OUT=ROOT/'artifacts/p2_02_exact_profile'
load=lambda p:json.loads(p.read_text())
def main():
 fresh=OUT/'fresh'; rows=load(fresh/'heldout/summary.json');audit=load(fresh/'heldout_audit.json')
 policies=['dense_exhaustive','sparse_exhaustive','dense_guarded','sparse_guarded']
 times={p:0. for p in policies};details=[];differences=[];maxdiff=0.;common=0
 for row in rows:
  if not row['base_valid'] or len(row['attempts'])!=16: continue
  directory=fresh/'heldout'/row['id'];study=load(directory/'input.json')['data'];raw=load(fresh/'planned_cases'/(row['id']+'.json'))['data']
  assert study['case']['network']==raw['case']['network'] and study['case']['generators']==raw['case']['generators']
  assert all(v==1 for v in study['participation'].values())
  data={(a['repetition'],a['policy']):load(directory/a['path']) for a in row['attempts']}
  timing={p:statistics.median(a['elapsed'] for a in row['attempts'] if a['policy']==p and a['repetition']>1) for p in policies}
  for p in policies:times[p]+=timing[p]
  for rep in range(1,5):
   maps={p:{a['entry']['contingency']['id']:a for a in data[rep,p]['assessments']} for p in policies}
   assert all(a['complete'] for a in row['attempts'])
   assert {k for k,a in maps['dense_guarded'].items() if a['decision']['action']=='screened'}=={k for k,a in maps['sparse_guarded'].items() if a['decision']['action']=='screened'}
   for id,a in maps['dense_exhaustive'].items():
    b=maps['sparse_exhaustive'][id]
    if a['rank']['classification']!=b['rank']['classification']:differences.append([row['id'],rep,id,a['rank']['classification'],b['rank']['classification']])
    if a['rank']['classification']==b['rank']['classification']=='accepted':
     sa=a['exact_assessment']['result']['states'][id];sb=b['exact_assessment']['result']['states'][id]
     maxdiff=max(maxdiff,max(abs(x-y) for field in ['vm','va','pg','qg'] for x,y in zip(sa[field],sb[field])));common+=1
  details.append({'id':row['id'],'warm_medians':timing})
 families=audit['families'];misses={p:sum(f['misses'] for f in families if f['policy']==p) for p in policies};screened={p:sum(f['screened'] for f in families if f['policy']==p) for p in policies}
 exhaustive_saving=1-times['sparse_exhaustive']/times['dense_exhaustive'];guarded_saving=1-times['sparse_guarded']/times['dense_guarded']
 passed=len(details)==4 and not any(misses.values()) and not differences and maxdiff<=1e-5 and exhaustive_saving>0 and guarded_saving>0
 result={'status':'FINITE_SCOPE_GATE_PASSED' if passed else 'NOT_QUALIFIED','complete_inputs':len(details),'planned_inputs':4,'unique_outages':sum(f['total'] for f in families if f['policy']=='dense_exhaustive'),'timings':times,'exhaustive_saving':exhaustive_saving,'guarded_saving':guarded_saving,'screened':screened,'misses':misses,'paired_classification_differences':differences,'common_accepted_pairs':common,'max_accepted_state_difference':maxdiff,'replayed_states':audit['replayed_states'],'replay_discrepancies':len(audit['discrepancies']),'details':details,'production_defaults_changed':False,'screening_safety_evidence': 'No screening decisions' if not any(screened.values()) else 'Finite screened set only','configuration':'fixed supplied taps/shunts, zero movement, frozen shared droop, preventive equal-weight active response'}
 (OUT/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
def figure():
 import matplotlib
 matplotlib.use('Agg')
 import matplotlib.pyplot as plt
 result=load(OUT/'RESULTS.json');dev=load(OUT/'development_results.json')
 fig,axes=plt.subplots(1,2,figsize=(12,4.5),layout='constrained')
 phases=['build','optimize','extract','validation'];labels=[];bottom=[0.]*4
 for phase in phases:
  values=[r['warm_medians'][s][phase] for r in dev for s in ['False','True']]
  axes[0].bar(range(4),values,bottom=bottom,label=phase)
  bottom=[a+b for a,b in zip(bottom,values)]
 axes[0].set_xticks(range(4),['Light\nDense','Light\nSparse','Negative Q\nDense','Negative Q\nSparse'])
 axes[0].set_title('Development phase medians');axes[0].legend();axes[0].set_ylabel('Seconds per complete outage set')
 values=result['timings'];axes[1].bar(range(4),list(values.values()),color=['#48657f','#4a9f85','#48657f','#4a9f85'])
 axes[1].set_xticks(range(4),['Exhaustive\nDense','Exhaustive\nSparse','Guard enabled\nDense','Guard enabled\nSparse'])
 axes[1].set_title('Fresh cases: summed warm medians');axes[1].set_ylabel('Seconds, four cases')
 fig.suptitle('Fixed equipment AC evaluation: dense versus sparse balance')
 fig.savefig(OUT/'performance.png',dpi=160);plt.close(fig)
if __name__=='__main__':
 main()
 figure()
