"""Replay saved acceptance invariants; inventory hashes are current, not execution provenance."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/s2_scopf/ieee500_native/incremental_shared_recovery'
load = lambda p: json.loads(p.read_text())


def main():
    result = load(OUT / 'RESULTS.json')
    accepted = 0
    for row in result['attempts']:
        folder = ROOT / 'artifacts/s2_scopf/ieee500_native' / row['folder']
        contract = load(folder / 'contract.json')
        assert contract['free_shared_slopes'] == contract['free_shared_references'] == 51
        assert not contract['fixed_controller'] and not contract['fixed_base']
        assert contract['response_relaxation_cap'] == 0 and not contract['restore']
        assert max(contract['factors']) <= 1.0625
        if row['accepted']:
            accepted += 1
            stage = row['stage']
            audit = load(folder / f'network-audit-{stage}.json')
            assert row['record']['native_success'] and row['record']['status'] != 'TIME_LIMIT'
            assert audit['accepted'] and audit['original_full_network_valid'] and audit['reduction_valid']
            point = load(folder / f'point-{stage}.json')
            assert all(s['artificial_max_pu'] == 0 for s in point['states'])
            if not contract['emergency']:
                assert contract['zero_dr'] and contract['zero_shedding'] and contract['thermal_multiplier'] == 1
                assert all(max(map(abs, s['dr'].values()), default=0) < 1e-9 and
                           max(map(abs, s['shed'].values()), default=0) < 1e-9 for s in point['states'])
    coverage = load(OUT / 'audit-coverage-incremental-105-r1.json')
    assert coverage['qualified'] and coverage['common_controller_and_per_demand_preventive_base_verified']
    assert coverage['zero_shedding'] and coverage['factors'] == [1.05]
    assert all(r['passed'] == r['evaluated'] == 389 and r['unchecked'] == 0 for r in coverage['rows'])
    for name, digest in coverage['source_hashes'].items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
    assert result['native_master_calls'] == 33 and result['separator_native_calls'] == 380
    assert not result['full_n1_accepted']
    validation = dict(passed=True, accepted_native_stages=accepted, native_master_calls=33,
                      new_separator_calls=380, qualified_connected_outages=389,
                      selected_coverage_source_hashes=len(coverage['source_hashes']),
                      original_network_and_reduction_audits_verified=True,
                      documentation_build='passed; API page and search-index size advisories only',
                      figures_visually_reviewed=True, full_n1_accepted=False)
    (OUT / 'VALIDATION.json').write_text(json.dumps(validation, indent=2) + '\n')
    files = {p for p in OUT.rglob('*') if p.is_file() and p.name != 'source_manifest.json'}
    files.update((ROOT / 'examples').glob('*.jl')); files.update((ROOT / 'examples').glob('*.py'))
    files.update((ROOT / 'src').rglob('*.jl'))
    files.update((ROOT / 'docs/src/assets/s2_500bus/incremental_shared_recovery').glob('*'))
    for name in ('AGENTS.md', 'README.md', 'ROADMAP.md', 'CHANGELOG.md', 'docs/src/s2_500bus.md',
                 'artifacts/s2_scopf/ieee500_native/REPORT.md',
                 'artifacts/s2_scopf/ieee500_native/STATUS.json',
                 'artifacts/s2_scopf/ieee500_native/CURRENT_RESULTS.json'):
        files.add(ROOT / name)
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
    (OUT / 'source_manifest.json').write_text(json.dumps(hashes, indent=2) + '\n')
    print(json.dumps(dict(**validation, current_inventory_files=len(hashes))))


if __name__ == '__main__': main()
