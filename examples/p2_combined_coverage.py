"""Combine prior training and new held-out evidence only with identical curves."""
import hashlib,json,os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=Path(os.environ.get('P2_QUALIFICATION_OUTPUT',str(ROOT/'artifacts/p2_remaining_qualification_20261022')))
load=lambda p:json.loads(p.read_text())
prior=load(ROOT/'artifacts/p2_s2_multidemand_20261022/s2-allowance/cross-demand-audit.json')
new=load(OUT/'heldout-500/cross-demand-audit.json')
assert prior['common_controller_verified'] and new['common_controller_verified']
assert prior['controller_sha256']==new['controller_sha256']
assert not (set(prior['accepted_factors'])&set(new['accepted_factors']))
large=sorted(prior['accepted_factors']+new['accepted_factors'])
source=ROOT/'artifacts/p2_s2_implementation_20261022/14/full'
assert load(source/'summary.json')['accepted']
curves=load(source/'controller-solve.json')['data']['case']['controls']
smallheld=load(OUT/'heldout-14/RESULTS.json');sf=[]
for r in smallheld['rows']:
 if not r['accepted']:continue
 assert load(ROOT/r['path']/'controller-solve.json')['data']['case']['controls']==curves
 sf.append(r['factor'])
training=load(source/'contract.json')['factors'];assert not(set(training)&set(sf))
small=sorted(training+sf)
r={'case14':{'controller_sha256':hashlib.sha256(json.dumps(curves,sort_keys=True).encode()).hexdigest(),'factors':small,'states':25*len(small),'connected_outages_per_demand':24,'relief_permitted':False},'case500':{'controller_sha256':new['controller_sha256'],'factors':large,'states':390*len(large),'connected_outages_per_demand':389,'relief_permitted':True,'shedding_cap_mw':10},'interpretation':'Prior training evidence plus fresh held-out evidence, with exact curve identity. Distinct from new independent designs or a continuous demand-range certificate.'}
(OUT/'COMBINED_DEMAND_COVERAGE.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
