"""Package the fresh P2 evidence; --replay reruns independent numerical audits."""
import hashlib,json,os,re,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=Path(os.environ.get('P2_QUALIFICATION_OUTPUT',str(ROOT/'artifacts/p2_remaining_qualification_20261022')))
load=lambda p:json.loads(p.read_text())
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def run(name):subprocess.run([sys.executable,'-B',str(ROOT/'examples'/name)],check=True,stdout=subprocess.DEVNULL)
if '--replay' in sys.argv or not (OUT/'independent-audit.json').exists():run('audit_p2_remaining_qualification.py')
assert load(OUT/'independent-audit.json')['passed']
if '--replay' in sys.argv or not (OUT/'audit-negative-tests.json').exists():run('test_p2_remaining_audit.py')
assert len(load(OUT/'audit-negative-tests.json')['rejected_corruptions'])==6
run('p2_ranking_measurements.py');run('p2_combined_coverage.py');run('report_p2_remaining_qualification.py')
# Pin source data, including compatible-version environment and all original S2 inputs.
inputs=load(ROOT/'artifacts/p2_s2_multidemand_20261022/source-input-hashes.json')
contract=load(ROOT/'artifacts/p2_s2_500/contract.json')
for item in contract['inputs'].values():
 inputs[item['source']]=item['sha256']
 assert sha(ROOT/'artifacts/p2_s2_500'/item['snapshot'])==item['sha256']
oldimplroot=ROOT/'artifacts/p2_s2_implementation_20261022';oldimpl=load(oldimplroot/'manifest.json')
assert all(sha(oldimplroot/p)==h for p,h in oldimpl['artifact_hashes'].items()),'Prior implementation artifact changed'
for p,h in oldimpl['input_source_hashes'].items():
 if p in inputs:assert inputs[p]==h
 inputs[p]=h
extra=['artifacts/s1_arpae14_joint_reference/relative5-study.json','artifacts/s1_arpae14_closeout/angle_limits.json',
       'artifacts/s1_free_droop/500/angle_limits.json','artifacts/s2_scopf/ieee14_native/multidemand/design-ipopt/controller.json']
extra += [f'artifacts/s2_scopf/ieee14_native/multidemand/design-ipopt/result-{f}.json' for f in (.9,.95,1.,1.05,1.1)]
extra += [f'artifacts/p2_s2_implementation_20261022/14/full/{name}.json' for name in ('controller-solve','point-solve','stages','contract','summary','audit-solve')]
for rel in extra:
 h=sha(ROOT/rel)
 if rel in inputs:assert inputs[rel]==h
 inputs[rel]=h
assert all(sha(ROOT/p)==h for p,h in inputs.items()),'Source input changed'
# The prior sealed P2 multi-demand evidence is retained byte for byte.
oldroot=ROOT/'artifacts/p2_s2_multidemand_20261022';old=load(oldroot/'MANIFEST.json')
assert all(sha(oldroot/p)==h for p,h in old['artifacts'].items()),'Prior sealed artifact changed'
core={p:h for p,h in old['repository_sources'].items() if p.startswith('src/')}
assert all(sha(ROOT/p)==h for p,h in core.items()),'Production source changed during qualification'
reference={14:load(ROOT/'artifacts/p2_s2_implementation_20261022/14/full/contract.json'),
           500:load(oldroot/'s2-allowance/stage-4/500/progressive/round-1/master/primary/contract.json')}
checked=0
for p in OUT.rglob('contract.json'):
 if 'source-snapshot' in p.parts or 'input-snapshot' in p.parts:continue
 c=load(p)
 if 'case_size' not in c or 'source_study' not in c:continue
 ref=reference[c['case_size']]
 assert c['angles']==ref['angles'] and c['reference_controls']==ref['reference_controls']
 assert c['active_response']=='s2_proportional_v1' and c['response_relaxation_cap']==0 and not c['restore']
 checked+=1
sources=set(ROOT.glob('examples/*p2*.jl'))|set(ROOT.glob('examples/*p2*.py'))|set(ROOT.glob('src/**/*.jl'))|set(ROOT.glob('test/**/*.jl'))
sources.update(ROOT/p for p in ('Project.toml','Manifest.toml','AGENTS.md','README.md','ROADMAP.md','docs/make.jl','docs/src/p2_remaining_qualification.md'))
queue=list(sources)
while queue:
 p=queue.pop()
 if not p.is_file():continue
 for rel in re.findall(r'"([^"\n]+\.(?:jl|py))"',p.read_text()):
  for candidate in (p.parent/rel,ROOT/rel,ROOT/'examples'/rel):
   if candidate.is_file() and candidate not in sources:sources.add(candidate);queue.append(candidate)
for group,folder in ((sources,'source-snapshot'),([ROOT/p for p in inputs],'input-snapshot')):
 for p in group:
  if p.is_file():
   target=OUT/folder/p.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
verification={'source_inputs_verified':len(inputs),'canonical_S2_inputs':len(contract['inputs']),'prior_sealed_artifacts_unchanged':len(old['artifacts']),'prior_implementation_artifacts_unchanged':len(oldimpl['artifact_hashes']),'production_sources_unchanged':len(core),'declared_contracts_checked':checked,'sources_snapshotted':len(sources),'passed':True}
(OUT/'provenance-verification.json').write_text(json.dumps(verification,indent=2)+'\n')
manifest={'source_inputs':inputs,'repository_sources':{str(p.relative_to(ROOT)):sha(p) for p in sorted(sources) if p.is_file()},'artifacts':{str(p.relative_to(OUT)):sha(p) for p in sorted(OUT.rglob('*')) if p.is_file() and p.name.lower()!='manifest.json'}}
(OUT/'MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
assert all(sha(OUT/p)==h for p,h in manifest['artifacts'].items())
print(json.dumps(dict(verification,artifact_hashes_verified=len(manifest['artifacts'])),indent=2))
