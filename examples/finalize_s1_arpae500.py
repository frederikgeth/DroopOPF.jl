"""Package audited 500-bus S1 witnesses and device thresholds; never run a solver."""
from pathlib import Path
import json, hashlib
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/s1_arpae500'
load=lambda p:json.loads(p.read_text())
def save(name,data): (OUT/name).write_text(json.dumps(data,indent=2)+'\n')
rows=[load(p) for p in sorted((OUT/'attempts').glob('*.json'))]
original=load(ROOT/'test/data/arpae/c1_network01/results/network_model.json')
ref=load(OUT/'selected_reference.json')
frozen=load(OUT/'frozen-study.json')['data']['case']
protocol=load(OUT/'protocol.json')
assert load(OUT/'audit.json')['states_replayed']==sum('state' in r for r in rows)
assert load(OUT/'audit.json')['discrepancies']==0
assert all(not r.get('error') for r in rows if r['accepted'])
for path,expected in protocol['hashes'].items():
 if path.startswith('test/data/'):
  assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==expected,path
factors=(.9,.95,1.,1.05,1.1)
primary=[r for r in rows if r['tags']['stage'] in ('frozen','equipment')]
assert len(primary)==180
stages=('frozen','equipment','recovery','ccopt_fix','continuation')
witnesses={};scorecard=[]
for family in ('fixed','tap','shunt','tap_shunt'):
 for factor in factors:
  direct=[r for r in primary if r['tags'].get('family','fixed')==family and r['tags']['factor']==factor]
  assert len(direct)==9
  candidates=[r for r in rows if r['tags']['stage'] in stages and r['tags'].get('family','fixed')==family and r['tags']['factor']==factor and not r.get('operating_bounds') and r['accepted'] and r['objective_kind']=='loss']
  assert {r['solver'] for r in candidates}=={'ipopt','madnlp','ccopt'},(family,factor)
  best=min(candidates,key=lambda r:r['loss_mw'])
  key=f'{family}-{factor}'
  witnesses[key]={'attempt':best['name'],'model_path':best['model_path'],'contract_hash':best['contract_hash'],'state':best['state'],'taps':best['taps'],'susceptances':best['susceptances'],'policy':best['policy'],'checks':best['point_checks']}
  checks=best['point_checks']['physical']
  scorecard.append(dict(family=family,factor=factor,direct_accepted=sum(r['accepted'] for r in direct),direct_physical=sum(r['point_pass'] for r in direct),attempts=9,best_attempt=best['name'],loss_mw=best['loss_mw'],economic_cost=best['economic_cost'],minimum_voltage_upper_margin_pu=checks['voltage_max_margin'],minimum_thermal_margin_mva=checks['branch_thermal_min_margin']*100,maximum_branch_loading_percent=max(max(b['from_mva'],b['to_mva'])/b['rating_mva']*100 for b in best['branches']),solvers_with_loss_witness=sorted({r['solver'] for r in candidates})))
  generators=[]
  for g in best['generators']:
   o=original['gen'][str(g['id'])];entry=dict(g)
   for axis,unit in (('p','mw'),('q','mvar')):
    for side in ('min','max'):entry[f'original_{axis}{side}_{unit}']=o[axis+side]*100
    entry[f'{axis}_lower_margin_{unit}']=g[f'{axis}g_{unit}']-g[f'{axis}min_{unit}']
    entry[f'{axis}_upper_margin_{unit}']=g[f'{axis}max_{unit}']-g[f'{axis}g_{unit}']
   generators.append(entry)
  controls={a['generator_id']:frozen['controls'][a['control_id']-1] for a in frozen['attachments']}
  out=dict(attempt=best['name'],buses=best['buses'],generators=generators,branches=best['branches'],droops=controls,selected_tap_policy=best['policy']['tap_controls'],selected_shunt_policy=best['policy']['shunt_controls'],tap_values=best['taps'],shunt_values=best['susceptances'],frozen_nominal_taps=ref['taps'],frozen_nominal_shunts=ref['susceptances'])
  (OUT/'thresholds').mkdir(exist_ok=True)
  save(f'thresholds/{key}.json',out)
save('demand_witnesses.json',witnesses);save('qualification.json',dict(primary_attempts=180,primary_accepted=sum(r['accepted'] for r in primary),primary_physical=sum(r['point_pass'] for r in primary),contracts_feasible=len(witnesses),scorecard=scorecard))
# Feasibility fingerprints also include starting equipment values. Compare the
# explicit mathematical payload without those starts when classifying recoveries.
model_cache={}
def physical_key(r):
 path=r['model_path']
 if path not in model_cache:model_cache[path]=load(ROOT/path)['data']['case']
 policy={k:[{a:b for a,b in x.items() if a not in ('initial','nominal')} for x in v] for k,v in r['policy'].items()}
 payload=dict(case=model_cache[path],policy=policy,angles=load(OUT/'angle_limits.json'),operating_bounds=r.get('operating_bounds'))
 return hashlib.sha256(json.dumps(payload,sort_keys=True).encode()).hexdigest()
keys={r['name']:physical_key(r) for r in rows}
resolutions=[]
for r in rows:
 if r['accepted']:continue
 compatible=[x for x in rows if keys[x['name']]==keys[r['name']] and x['point_pass']]
 native=[x for x in compatible if x['accepted'] and x['solver']==r['solver'] and x['objective_kind']==r['objective_kind']]
 resolutions.append(dict(failed_attempt=r['name'],model_gate='feasible' if compatible else 'unresolved',physical_witnesses=[x['name'] for x in compatible],same_solver_objective_recovery=[x['name'] for x in native],interpretation='numerical/solver failure on a verified feasible model' if compatible else 'no physical witness or infeasibility certificate for this contract'))
save('failure_resolution.json',resolutions)
# Retain initial recorded code hashes; separately record the scripts used for final replay/reporting.
files=list((ROOT/'examples').glob('*s1_arpae500*'))+[ROOT/'Project.toml',ROOT/'Manifest.toml',ROOT/'examples/global_feasibility_env/Project.toml',ROOT/'examples/global_feasibility_env/Manifest.toml']+list((ROOT/'src').glob('*.jl'))+list((OUT/'global_environment').glob('*.toml'))
manifest={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files if p.is_file()}
save('final_code_manifest.json',manifest)
print('Packaged',len(witnesses),'contracts; primary',sum(r['accepted'] for r in primary),'/180')
for r in scorecard:print(r['family'],r['factor'],round(r['loss_mw'],6),r['solvers_with_loss_witness'])
