import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]; out=root/'artifacts/s1_arpae14_joint_reference'
rows=[json.loads(l) for l in (out/'rows.jsonl').read_text().splitlines()]
old=[json.loads(l) for l in (root/'artifacts/s1_arpae14_performance_controls/design_rows.jsonl').read_text().splitlines()]
groups={}
for r in rows:
 t=r['tags']
 if t['stage']=='evaluation': groups.setdefault((t['range'],t['arm']),[]).append(r)
for fam,arm in [('fixed','old_fixed'),('tap_shunt','old_free')]:
 groups[('relative5',arm)]=[r for r in old if r['tags']['objective']=='loss' and r['tags']['family']==fam]
def summary(rs):
 good=[r for r in rs if r['accepted']]; best={}
 for f in [.9,.95,1.,1.05,1.1]:
  gs=[r for r in good if r['tags']['factor']==f]
  if gs:
   r=min(gs,key=lambda x:x['loss_mw'])
   best[str(f)]={'loss_mw':r['loss_mw'],'cost':r['economic_cost'],'name':r['name'],
    'voltage_min':min(b['vm'] for b in r['buses']),'voltage_max':max(b['vm'] for b in r['buses']),
    'thermal_margin_mva':min(b['thermal_margin_mva'] for b in r['branches'] if b['thermal_margin_mva'] is not None)}
 return {'accepted':len(good),'total':len(rs),'feasible':sum(r['point_pass'] for r in rs),'best':best}
res={f'{a}/{b}':summary(v) for (a,b),v in groups.items()}
refs={}
for range in ['relative5','relative10','absolute10']:
 rs=[r for r in rows if r['tags']['stage']=='reference' and r['tags']['range']==range and r['accepted']]
 r=min(rs,key=lambda x:x['loss_mw']);refs[range]={'loss_mw':r['loss_mw'],'cost':r['economic_cost'],'taps':r['taps'],'B':r['susceptances']}
extra=[json.loads(l) for l in (out/'joint_anchor_rows.jsonl').read_text().splitlines()] if (out/'joint_anchor_rows.jsonl').exists() else []
anchor_groups={}
for r in extra:
 t=r['tags'];anchor_groups.setdefault(f"{t['range']}/{t['arm']}",[]).append(r)
anchor_summary={k:summary(v) for k,v in anchor_groups.items()}
(out/'joint_anchor_summary.json').write_text(json.dumps(anchor_summary,indent=2))
(out/'summary.json').write_text(json.dumps({'groups':res,'references':refs},indent=2))
print(json.dumps({'groups':res,'references':refs},indent=2))
