"""Package and seal an already completed mixed-control campaign; never optimize."""
from pathlib import Path
import hashlib,json,re,shutil,sys

def load(p):return json.loads(Path(p).read_text())
def save(p,d):
    p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,indent=2)+'\n')
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main(root):
    root=Path(root).resolve();repo=Path(__file__).resolve().parents[1]
    if (root/'MANIFEST.json').exists():raise RuntimeError('campaign is already sealed')
    check=load(root/'aggregate-checks.json');replay=load(root/'final-julia-replay.json')
    assert check['valid'] and replay['valid'] and all(s['complete'] for s in check['scans'].values())
    assert load(root/'scan-retries/summary.json')['complete']
    frozen=load('/tmp/mixed-verified-final-source-hashes.json')
    assert all(digest(repo/p)==h for p,h in frozen.items()),'source/test drift after final regression'
    tests=Path('/tmp/mixed-verified-final-suite.log').read_text();assert '3337   3337' in tests and '163    163' in tests and '14     14' in tests
    assert 'Test Failed' not in tests and 'ERROR:' not in tests
    python=Path('/tmp/mixed-python-tests-final.log').read_text();assert 'Ran 12 tests' in python and 'OK' in python
    docs=Path('/tmp/mixed-final-docs-r2.log').read_text();assert 'ERROR:' not in docs and 'Automatic `version=' in docs
    for lane,s in check['scans'].items():
        for row in s['rows']:
            if row['status']!='native_and_independent_pass':continue
            phase=Path(row['path']);assert load(phase/'julia-final-replay.json')['valid']
    marker='## Mixed AVR / droop capability campaign (2026-10-22)'
    agents=repo/'AGENTS.md'
    if marker not in agents.read_text():
        with agents.open('a') as out:
            out.write('''\n\n## Mixed AVR / droop capability campaign (2026-10-22)\n\nThe user authorized all planned steps for a fresh mixed-control 500-bus study.\nSelect the largest 30% of online positive-Pmax units by count, nearest integer\nwith half upward and ascending-ID ties: 15 AVR and 36 droop units (39 offline).\nAVR targets use nominal S2 saved generator-bus voltages. Explicit exploratory\napparent ratings are S=Pmax/0.95, not verified manufacturer/MBASE ratings.\nDynamic Q capability intersects the existing Q box with the apparent circle;\nAVR releases and droop saturates at these limits. GFL/GFM modeling stays deferred.\n\nThis benchmark preserves exact S2 131 corrective taps/11 continuous banks,\nabsolute bounds/no extra movement cap, proportional equality participation,\nemergency limits and original relief allowances. Production limit-aware default\nis unchanged. Profile90/100/105/100/90% uses five one-hour periods and assumed\n25%-of-active-range/hour preventive ramps. Main catalogue AVR targets stay fixed;\nseparate +/-0.02 pu,0.01 pu/hour AVR scheduling sensitivities were attempted.\nNo repeated equipment confirmation was requested within the user's scope.\n\nEvidence is artifacts/p2_mixed_avr_500_20261022. All389 connected outages at all5\nperiods were assessed for fixed and shared-designed curves. Final accepted\noutages: fixed352/designed364;13 fixed-dispatch capacity exclusions each;\n24/12 numerical leftovers. The exclusions concern frozen dispatch plus S2\nparticipation, not network-wide infeasibility. A bounded joint recovery pilot\ndid not qualify. Five-period AVR scheduling remains numerically unresolved.\nThe fixed-reference trajectory composes independently native-optimized periods\nwith verified ramps; do not call its timed-out coupled solve converged.\n\nThe14-bus2AVR/3droop study passes125states with normal bounds/no relief.\nFinal3514Julia checks,12Python corruption/contract checks and current-source\nreplay729accepted resultfiles pass. The frozen global/rational feasibility gate\nand old voltage-only droop predictor reject rated cases until extended; the\nseparate passive active-only S2 outer bound remains a necessary exclusion only.\nOriginalS2 remains paused, prior sealed evidence unchanged, and P2 stays open.\nDo not overwrite this campaign after its manifest is sealed.\n''')
    verification=root/'verification';verification.mkdir(exist_ok=True)
    final_logs={'full-tests.log':'mixed-verified-final-suite.log','focused-capability-tests.log':'mixed-final-shared-target-tests.log',
        'python-corruption-tests.log':'mixed-python-tests-final.log','docs.log':'mixed-final-docs-r2.log',
        'current-julia-replay.log':'mixed-final-julia-replay.log','cross-file-audit.log':'mixed-final-report.log',
        'scan-designed.log':'mixed-full-scan.log','scan-fixed.log':'mixed-fixed-reference-scan.log','scan-retries.log':'mixed-retry-worker.log'}
    for dst,src in final_logs.items():shutil.copyfile(Path('/tmp')/src,verification/dst)
    development=verification/'development';development.mkdir(exist_ok=True)
    for p in Path('/tmp').glob('mixed*.log'):
        if p.name not in set(final_logs.values()):shutil.copyfile(p,development/p.name)
    procedures=verification/'procedures';procedures.mkdir(exist_ok=True)
    for p in Path('/tmp').glob('mixed*.jl'):shutil.copyfile(p,procedures/p.name)
    save(verification/'final-source-hashes.json',frozen)
    prior=load(root/'prior-sealed-evidence-verification.json');assert prior['valid']
    results=dict(valid=True,julia_checks_passed=3514,python_checks_passed=12,
        julia_replay_result_files=len(replay['rows']),replayed_state_instances=replay['state_instances_including_repeated_frozen_bases'],
        prior_sealed_files_verified=sum(x['verified_files'] for x in prior['rows']),documentation_build_passed=True,
        final_core_and_test_sources_unchanged=True,full_scan_outages_per_lane=389,periods=5,
        native_and_independent_replay_valid=True,security_passed=False,p2_closed=False,
        initial_strict_s2_preflight='original source-hash preflight rejected src/domain.jl drift already present from parser work; input bytes separately verified',
        julia_version='1.12.4',ipopt_version='3.14.19',blas_threads=1,python_version=sys.version)
    save(verification/'results.json',results)
    sys.path.insert(0,str(repo/'examples'))
    from report_mixed_avr_500 import report
    report(root,check)
    inputs=root/'source-inputs/s2';inputs.mkdir(parents=True,exist_ok=True)
    package=repo/'artifacts/p2_s2_500';contract=load(package/'contract.json');shutil.copyfile(package/'contract.json',inputs/'contract.json')
    inputrows=[]
    for role,ref in contract['inputs'].items():
        src=package/ref['snapshot'];assert digest(src)==ref['sha256'] and src.read_bytes()==(repo/ref['source']).read_bytes()
        dst=inputs/(role+'.json');shutil.copyfile(src,dst);inputrows.append(dict(role=role,source=ref['source'],sha256=digest(dst)))
    paths14=['artifacts/s2_scopf/ieee14_native/multidemand/design-ipopt/controller.json',
        'artifacts/s2_scopf/ieee14_native/multidemand/design-ipopt/result-1.0.json',
        'artifacts/s1_arpae14_joint_reference/relative5-study.json','artifacts/s1_arpae14_closeout/angle_limits.json']
    for i,rel in enumerate(paths14):
        dst=root/'source-inputs/14'/f'{i+1}-{Path(rel).name}';dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(repo/rel,dst)
        inputrows.append(dict(role='14-bus-source',source=rel,sha256=digest(dst)))
    save(root/'source-inputs/index.json',inputrows)
    sources=set(repo.glob('src/*.jl'))|set(repo.glob('test/*.jl'))|set(repo.glob('examples/*.jl'))|set(repo.glob('examples/*.py'))|set(repo.glob('docs/src/*.md'))
    for rel in ['AGENTS.md','Project.toml','Manifest.toml','README.md','ROADMAP.md','LICENSE','docs/make.jl','docs/Project.toml','docs/Manifest.toml']:
        if (repo/rel).is_file():sources.add(repo/rel)
    snapshot=root/'source-snapshot';hashes={}
    for src in sorted(sources):
        rel=src.relative_to(repo);dst=snapshot/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst);hashes[str(rel)]=digest(dst)
    save(root/'source-hashes.json',hashes)
    # Seal only after all writers and independent checks have finished.
    files={str(p.relative_to(root)):digest(p) for p in sorted(root.rglob('*')) if p.is_file() and p.name not in ('MANIFEST.json','seal-verification.json')}
    save(root/'MANIFEST.json',dict(scope='Mixed AVR/droop 14/500 capability-circle campaign; evidence valid,500 security not qualified',
        files=files,final_source_regression_checks=3514,python_corruption_checks=12,
        source_inputs_copied=len(inputrows),original_s2_resumed=False,p2_closed=False))
    bad=[p for p,h in files.items() if digest(root/p)!=h]
    assert not bad
    save(root/'seal-verification.json',dict(valid=True,files_verified=len(files),manifest_sha256=digest(root/'MANIFEST.json'),
        excluded_from_manifest=['MANIFEST.json','seal-verification.json']))
    print(json.dumps(dict(valid=True,sealed_files=len(files),source_files=len(hashes),input_files=len(inputrows),report=str(root/'REPORT.md'))))
if __name__=='__main__':main(sys.argv[1])
