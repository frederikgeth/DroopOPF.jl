from pathlib import Path
import json,statistics,sys
out=Path(sys.argv[1]).resolve();audit=json.loads((out/'heldout_audit.json').read_text());policies=['legacy','reference','guarded','exhaustive'];complete=[r for r in audit['inputs'] if r['complete']]
screened={p:sum(r['screened'] for r in audit['families'] if r['policy']==p) for p in policies};misses={p:sum(r['misses'] for r in audit['families'] if r['policy']==p) for p in policies};times={p:sum(statistics.median(a['elapsed'] for a in r['timings'] if a['policy']==p and a['repetition']>1) for r in complete) for p in policies};outages=sum(r['total'] for r in audit['families'] if r['policy']=='exhaustive')
for row in complete:
 d=out/'heldout'/row['id'];raw=json.loads((out/'planned_cases'/(row['id']+'.json')).read_text())['data']['case'];study=json.loads((d/'input.json').read_text())['data'];assert study['case']['network']==raw['network'];assert study['case']['generators']==raw['generators'];assert all(v==1 for v in study['participation'].values())
 for rep in range(1,5):
  sets={}
  for p in ['reference','guarded']:
   data=json.loads((d/f'{rep}-{p}.json').read_text());sets[p]={a['entry']['contingency']['id'] for a in data['assessments'] if a['decision']['action']=='screened'}
  assert sets['guarded']<=sets['reference']
status='QUALIFICATION_FAILED' if misses['guarded'] else 'INCOMPLETE_COVERAGE' if len(complete)!=4 else 'NO_OBSERVED_MISSES_FINITE_SCOPE'
r=dict(status=status,complete_inputs=len(complete),planned_inputs=4,outages=outages,screened=screened,misses=misses,timings=times,replayed_states=audit['replayed_states'],replay_discrepancies=len(audit['discrepancies']),candidate_screened_subset_reference_verified=True,fixed_equipment_and_participation_verified=True,configuration='fixed supplied taps/shunts, zero movement, frozen shared droop, preventive equal-weight active response',production_library_changed=False,accepted_control_regimes=audit['accepted_control_regimes'],candidate_saving_vs_reference=1-times['guarded']/times['reference'],candidate_saving_vs_exhaustive=1-times['guarded']/times['exhaustive'])
(out/'RESULTS.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
fig,axes=plt.subplots(1,2,figsize=(10,4))
axes[0].bar(policies,[misses[p] for p in policies]);axes[0].set(ylabel='Screened unresolved outages',title='Fresh 16/32-bus comparison')
axes[1].bar(policies,[times[p] for p in policies]);axes[1].set(ylabel='Summed per-input warm median seconds',title='Four orders; warm repetitions 2–4')
fig.tight_layout();fig.savefig(out/'qualification.png',dpi=160);plt.close(fig)
