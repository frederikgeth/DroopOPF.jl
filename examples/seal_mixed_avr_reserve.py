"""Seal completed reserve-aware assessment; distinguishes qualification from unresolved cases."""
from pathlib import Path
import hashlib,json,re,shutil,sys

def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def load(p):return json.loads(Path(p).read_text())
def save(p,d):Path(p).write_text(json.dumps(d,indent=2)+'\n')

def seal(root):
    root=Path(root).resolve();repo=Path(__file__).resolve().parents[1]
    if (root/'MANIFEST.json').exists():raise RuntimeError('already sealed')
    audit=load(root/'reserve-aggregate-checks.json');replay=load(root/'final-julia-replay.json')
    assert audit['scanned']==389 and audit['accepted']+audit['unresolved']==389 and not audit['missing']
    assert replay['valid'] and len(replay['rows'])==1+audit['accepted']
    assert replay['complete_connected_security']==audit['full_security_qualified']
    frozen=load('/tmp/reserve-final-source-test-hashes.json')
    assert all(digest(repo/p)==h for p,h in frozen.items()),'source/test change after final regression start'
    tests=Path('/tmp/reserve-source-frozen-suite.log').read_text()
    assert '3365' in tests and '163' in tests and '14' in tests
    assert 'ERROR:' not in tests and 'Test Failed' not in tests and 'Error During Test' not in tests
    python=Path('/tmp/reserve-python-verified.log').read_text();assert 'Ran 19 tests' in python and 'OK' in python
    docs=Path('/tmp/reserve-docs-build.log').read_text();assert 'ERROR:' not in docs and 'Automatic `version=' in docs
    precompile=Path('/tmp/reserve-precompile-check.log').read_text();assert 'package import and precompile passed' in precompile
    logs={'julia-full-suite.log':'/tmp/reserve-source-frozen-suite.log','python-audit-tests.log':'/tmp/reserve-python-verified.log',
        'documentation-build.log':'/tmp/reserve-docs-build.log','package-precompile.log':'/tmp/reserve-precompile-check.log'}
    for name,source in logs.items():shutil.copyfile(source,root/name)
    source_paths=[p for d in ['src','test'] for p in (repo/d).rglob('*.jl')]
    source_paths += [p for p in (repo/'examples').rglob('*') if p.is_file() and p.suffix in ('.jl','.py')]
    source_paths=list(dict.fromkeys(source_paths))
    source_paths += [repo/p for p in ['examples/p2_mixed_avr_500.jl','examples/p2_mixed_avr_campaign.jl','examples/audit_mixed_avr_500.py',
        'examples/mixed_avr_capacity_screen.py','examples/p2_s2_capacity_filter.py','examples/s2_followup_physics.py',
        'AGENTS.md','Project.toml','Manifest.toml','README.md','ROADMAP.md','docs/src/mixed_avr_droop.md'] if (repo/p).is_file()]
    for p in source_paths:
        q=root/'release_source_snapshot'/p.relative_to(repo);q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
    old=repo/'artifacts/p2_mixed_avr_500_20261022';manifest=load(old/'MANIFEST.json')
    assert digest(old/'MANIFEST.json')=='d17aa659c0e1eaf0c45f24e06703275b75c9d1adea9b79d6cb4e06ab40c02b13'
    assert all(digest(old/p)==h for p,h in manifest['files'].items()),'prior sealed evidence changed'
    save(root/'prior-evidence-verification.json',dict(valid=True,files_verified=len(manifest['files']),original_s2_resumed=False))
    files={str(p.relative_to(root)):digest(p) for p in sorted(root.rglob('*')) if p.is_file() and p.name not in ['MANIFEST.json','seal-verification.json']}
    save(root/'MANIFEST.json',dict(scope='500-bus mixed AVR/droop reserve-aware assessment; actual qualification recorded separately',
        full_security_qualified=audit['full_security_qualified'],accepted_outages=audit['accepted'],unresolved_outages=audit['unresolved'],
        files=files,attempted_unique_states=1950,validated_unique_states=5+5*audit['accepted'],julia_replayed_result_files=len(replay['rows']),julia_checks=3542,python_checks=19,
        full_catalogue_resource_optimality_claimed=False,transient_or_discrete_equipment_qualification_claimed=False,
        original_s2_resumed=False,p2_closed=False))
    assert all(digest(root/p)==h for p,h in files.items())
    save(root/'seal-verification.json',dict(valid=True,files_verified=len(files),manifest_sha256=digest(root/'MANIFEST.json')))
    print('SEALED',len(files),'files')
if __name__=='__main__':seal(sys.argv[1])
