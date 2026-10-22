"""Current report/source inventory; executed per-run snapshots stay separate."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/s2_scopf/ieee500_native/targeted_demand_diagnostics'


def refresh():
    target=OUT/'source_manifest.json'
    files={p for p in OUT.rglob('*') if p.is_file() and p!=target}
    for directory,pattern in (('src','*.jl'),('examples','*.jl'),('examples','*.py'),('docs/src','*.md'),('docs/src/assets/s2_500bus_targeted','*')):
        files.update(p for p in (ROOT/directory).rglob(pattern) if p.is_file())
    for name in ('Project.toml','Manifest.toml','AGENTS.md','README.md','ROADMAP.md','CHANGELOG.md',
                 'artifacts/s2_scopf/ieee500_native/REPORT.md','artifacts/s2_scopf/ieee500_native/STATUS.json',
                 'artifacts/s2_scopf/ieee500_native/CURRENT_RESULTS.json','artifacts/s2_scopf/ieee500_native/pilot_study.json',
                 'artifacts/s1_arpae500/calibrated-study.json','artifacts/s1_free_droop/500/angle_limits.json',
                 'test/data/arpae/c1_network01/results/scenario_02_pmin0_qsym/network_model.json'):
        files.add(ROOT/name)
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
    target.write_text(json.dumps(hashes,indent=2)+'\n')
    assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in hashes.items())
    # Coverage input hashes include every selected state and native-stage file.
    inputs=0
    for path in OUT.glob('audit-emergency-*-coverage.json'):
        for name,digest in json.loads(path.read_text())['source_hashes'].items():
            assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest;inputs+=1
    print(json.dumps(dict(inventory_files=len(hashes),selected_coverage_inputs=inputs,verified=True)))


if __name__=='__main__':refresh()
