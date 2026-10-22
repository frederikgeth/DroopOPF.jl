"""Verify final campaign identities, hashes, acceptance gates and exports; no solves."""
import csv
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/s2_scopf/ieee500_native/finish_105_multidemand'
load = lambda p: json.loads(Path(p).read_text())
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()


def check():
    results = load(OUT / 'RESULTS.json')
    assert results['status'] == 'bounded_campaign_complete'
    assert results['native_master_calls'] == 25
    assert results['separator_native_calls'] == 8
    assert len(results['attempts']) == 25
    assert sum(r['accepted'] for r in results['attempts']) == 9
    for attempt in results['attempts']:
        folder = ROOT / 'artifacts/s2_scopf/ieee500_native' / attempt['folder']
        stage = attempt['stage']; contract = load(folder / 'contract.json')
        record = attempt['record']; physical = load(folder / f'audit-{stage}.json')
        reduced = load(folder / f'network-audit-{stage}.json')
        assert physical['contract_sha256'] == sha(folder / 'contract.json')
        assert physical['point_sha256'] == sha(folder / f'point-{stage}.json')
        assert physical['auditor_sha256'] == sha(ROOT / 'examples/audit_s2_500bus_loadability.py')
        assert physical['physics_helper_sha256'] == sha(ROOT / 'examples/s2_followup_physics.py')
        assert reduced['maps_sha256'] == sha(folder / 'network_reduction_maps.json')
        assert reduced['auditor_sha256'] == sha(ROOT / 'examples/audit_s2_500bus_network_reduction.py')
        assert all(r['original_ratings_verified'] and r['valid'] for r in reduced['checks'])
        assert reduced['reduction_valid']
        assert len(physical['states']) == 6 * len(contract['factors'])
        assert max(contract['factors']) <= 1.0625
        assert record['free_shared_droop_variables'] == (0 if contract['fixed_controller'] else 102)
        assert contract['response_relaxation_cap'] == 0.
        assert not contract['restore'] and contract['thermal_multiplier'] == 1.1
        assert attempt['accepted'] == reduced['accepted'] == physical['accepted']
        if attempt['accepted']:
            assert record['native_success'] and physical['physical_valid']
            if contract['zero_shedding']:
                assert all(s['shedding_mw'] == 0 for s in physical['states'])
    for solver in ('ipopt', 'madnlp', 'ccopt'):
        pipeline = results['pipelines'][f'multi-{solver}']
        assert len(pipeline['rows']) == 3
        assert all(r['record']['status'] == 'TIME_LIMIT' and not r['accepted'] for r in pipeline['rows'])
        assert pipeline['selected'] is None and not pipeline['loss_objective_completed']
    witness = results['common_controller_witness']
    assert witness['shared_controller_feasible'] and not witness['native_joint_optimization']
    assert not witness['optimal_design'] and witness['included_states'] == 30
    for name, digest in witness['source_hashes'].items():
        assert sha(ROOT / name) == digest
    replay = results['connected_outage_replays'][0]
    assert not replay['qualified']
    entries = replay['rows'][0]['entries']
    assert {r['event'] for r in entries if not r['accepted']} == {'generator_32', 'generator_89', 'generator_37', 'generator_42'}
    for name, digest in replay['source_hashes'].items():
        assert sha(ROOT / name) == digest
    with (OUT / 'accepted-droop-designs.csv').open() as stream:
        droops = list(csv.DictReader(stream))
    assert len(droops) == 4 * 51
    assert all(r['loss_objective_completed'] == 'False' for r in droops)
    with (OUT / 'accepted-equipment-values.csv').open() as stream:
        controls = list(csv.DictReader(stream))
    assert len(controls) == 4 * 6 * 142
    assert sum(r['available'] == 'False' for r in controls) == 4
    for row in controls:
        if row['available'] == 'True':
            assert float(row['lower']) - 1e-6 <= float(row['value']) <= float(row['upper']) + 1e-6
    result = dict(passed=True, native_master_calls=25, separator_native_calls=8,
                  accepted_master_or_initializer_calls=9, multi_demand_attempts=9,
                  droop_export_rows=len(droops), equipment_export_rows=len(controls),
                  unavailable_equipment_rows=4, extra_optimizer_calls=0,
                  physical_and_reduction_audit_identities_verified=True)
    (OUT / 'VALIDATION.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return result


if __name__ == '__main__':
    check()
