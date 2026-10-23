"""Seal completed P2 assessment, preserving partial qualification honestly."""
import hashlib,json,re,shutil,sys
from pathlib import Path
root=Path(sys.argv[1]).resolve();repo=Path(__file__).resolve().parents[1]
assert not (root/'MANIFEST.json').exists(), 'campaign already sealed'
def load(p):return json.loads(p.read_text())
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
d=load(root/'reserve-aggregate-checks.json');j=load(root/'final-julia-replay.json')
assert d['scanned']==d['catalogue_size']==389 and not d['missing']
assert d['frozen_identity_valid'] and d['base_and_master_valid'] and j['valid']
assert j['complete_connected_security']==d['full_security_qualified']
expected_paths={str(root/d['candidate'])}|{r['path'] for r in d['rows'] if r['valid']}
assert {r['path'] for r in j['rows']}==expected_paths
assert all(digest(Path(r['path'])/'result.json')==r['result_sha256'] for r in j['rows'])
logs={'julia-tests':'/tmp/p2-limit-aware-julia-tests.log','python-tests':'/tmp/p2-limit-aware-audit-tests.log'}
validation=root/'validation-logs';validation.mkdir(exist_ok=True)
for name,source in logs.items():shutil.copyfile(source,validation/(name+'.log'))
jtext=Path(logs['julia-tests']).read_text();ptext=Path(logs['python-tests']).read_text()
counts=[(int(a),int(b)) for a,b in re.findall(r'\|\s+(\d+)\s+(\d+)\s+',jtext)]
assert sum(a for a,b in counts)==115 and all(a==b for a,b in counts)
assert 'Ran 37 tests' in ptext and '\nOK\n' in ptext
(root/'software-validation.json').write_text(json.dumps({'julia_checks':115,'python_unittest_checks':37,'valid':True},indent=2)+'\n')
# Preserve exact current implementation, audit, configuration and test sources.
paths=list((repo/'src').glob('*.jl'))+list((repo/'test').glob('*.jl'))
paths += [repo/'examples'/name for name in ['p2_mixed_avr_500.jl','p2_mixed_avr_campaign.jl','p2_mixed_avr_reserve.jl',
 'p2_mixed_limit_aware.jl','resolve_p2_mixed_limit_aware.jl','audit_mixed_avr_500.py','s2_followup_physics.py',
 'report_mixed_avr_reserve.py','report_p2_mixed_limit_aware.py','replay_mixed_avr_reserve.jl',
 'test_p2_limit_aware_audit.py','test_mixed_avr_audit.py','test_reserve_avr_audit.py','seal_p2_mixed_limit_aware.py']]
paths += [repo/'AGENTS.md',repo/'README.md',repo/'ROADMAP.md',repo/'docs/src/mixed_avr_droop.md',repo/'Project.toml',repo/'Manifest.toml']
for source in paths:
 if source.exists():
  target=root/'source_snapshot'/source.relative_to(repo);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
prior={}
for name in ['p2_mixed_avr_500_20261022','p2_mixed_avr_reserve_20261023']:
 p=repo/'artifacts'/name/'MANIFEST.json';prior[name]=digest(p)
files={str(p.relative_to(root)):digest(p) for p in sorted(root.rglob('*')) if p.is_file()}
manifest={'files':files,'prior_manifest_hashes':prior,'response':'limit_aware','emergency':False,
 'connected_outages':389,'attempted_unique_states':1950,'qualified_unique_states':5+5*d['accepted'],'accepted_outages':d['accepted'],'unresolved_outages':d['unresolved'],
 'full_security_qualified':d['full_security_qualified'],'full_catalogue_optimality':False,'p2_closed':False,
 'original_s2_resumed':False,'discrete_or_transient_security':False}
(root/'MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
assert all(digest(root/p)==h for p,h in files.items())
verification={'valid':True,'files_verified':len(files),'manifest_sha256':digest(root/'MANIFEST.json')}
(root/'seal-verification.json').write_text(json.dumps(verification,indent=2)+'\n')
print(json.dumps(verification))
