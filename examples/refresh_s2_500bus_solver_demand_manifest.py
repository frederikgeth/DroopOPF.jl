"""Refresh hashes after reporting, documentation build and final validation."""
from pathlib import Path
import hashlib
import json
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/s2_scopf/ieee500_native/solver_demand_qualification'

def manifest_files():
    suffixes={'.json','.jl','.py','.log','.csv','.md','.txt'}
    files={p for p in OUT.rglob('*') if p.is_file() and p.suffix in suffixes and p.name!='source_manifest.json'}
    files.update(p for p in (ROOT/'docs/src/assets/s2_500bus/solver_demand_qualification').iterdir() if p.suffix in ('.png','.pdf'))
    files.update((ROOT/'examples').glob('*.jl'));files.update((ROOT/'examples').glob('*.py'));files.update((ROOT/'src').rglob('*.jl'))
    for name in ('Project.toml','Manifest.toml','AGENTS.md','README.md','ROADMAP.md','CHANGELOG.md','docs/make.jl','docs/Project.toml','docs/Manifest.toml','docs/src/s2_500bus.md',
                 'artifacts/s2_scopf/ieee500_native/REPORT.md','artifacts/s2_scopf/ieee500_native/STATUS.json','artifacts/s2_scopf/ieee500_native/CURRENT_RESULTS.json',
                 'artifacts/s2_scopf/ieee500_native/pilot_study.json','artifacts/s1_arpae500/calibrated-study.json','artifacts/s1_free_droop/500/angle_limits.json',
                 'test/data/arpae/c1_network01/results/scenario_02_pmin0_qsym/network_model.json'):
        p=ROOT/name
        if p.is_file():files.add(p)
    starts=OUT/'s1-start-checks.json'
    if starts.exists():
        for r in json.loads(starts.read_text())['starts']:files.add(ROOT/r['result_path'])
    return sorted(files)

def main():
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in manifest_files()}
    path=OUT/'source_manifest.json';path.write_text(json.dumps(hashes,indent=2)+'\n')
    assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==digest for p,digest in hashes.items())
    print(json.dumps(dict(files=len(hashes),verified=True)))
if __name__=='__main__':main()
