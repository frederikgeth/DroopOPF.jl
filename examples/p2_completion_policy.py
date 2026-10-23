"""Solve-free diagnosis of active-response headroom in public anchors."""
import json
from pathlib import Path
OUT=Path(__file__).resolve().parents[1]/'artifacts/p2_completion'
rows=[]
for p in sorted((OUT/'public_run').glob('*/study.json')):
 d=json.loads(p.read_text())['data'];c=d['case'];s=json.loads((p.parent/'base.json').read_text())
 gs=[(i,g) for i,g in enumerate(c['generators']) if g['available']];n=len(gs)
 rows.append({'id':p.parent.name,'available':n,
  'zero_active_capacity':[g['id'] for i,g in gs if g['p_min']==g['p_max']==0.],
  'base_active_bound_margin_min':min(min(s['pg'][i]-g['p_min'],g['p_max']-s['pg'][i]) for i,g in gs),
  'branch_outage_delta_interval':[max((g['p_min']-s['pg'][i])*n for i,g in gs),min((g['p_max']-s['pg'][i])*n for i,g in gs)]})
(OUT/'response_policy_diagnosis.json').write_text(json.dumps({
 'explanation':'For a surviving generator, Pg_s=Pg_base+alpha*delta. A positive weight on a zero-P-range unit forces delta=0. Tiny bound residuals are numerical tolerance, not a global infeasibility certificate.',
 'cases':rows},indent=2)+'\n')
