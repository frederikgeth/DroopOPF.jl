"""Join native per-demand witnesses with identical droops; do not claim joint optimality."""
import copy
import hashlib
import json
import shutil
import tempfile
from pathlib import Path
from audit_s2_500bus_network_reduction import audit

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'artifacts/s2_scopf/ieee500_native'
OUT = BASE / 'finish_105_multidemand'
load = lambda p: json.loads(Path(p).read_text())


def check():
    inputs = [(BASE / 'free_droop_continuation/normalized-anchor-polish-1.0625-r05', 'dr')]
    inputs += [(OUT / f'common-controller-seed-{f}', 'feasibility') for f in (9000, 9500, 10000, 10500)]
    sources, states, maps, hashes = [], [], [], {}
    upper, stage = inputs[0]
    controller = load(upper / f'controller-{stage}.json')
    controls = controller['data']['case']['controls']
    for folder, stage in inputs:
        with tempfile.TemporaryDirectory(prefix='s2-common-controller-') as temporary:
            tmp = Path(temporary)
            files = ['contract.json', 'stages.json', 'network_reduction_maps.json', f'controller-{stage}.json', f'point-{stage}.json']
            for name in files:
                p = folder / name; shutil.copy2(p, tmp / name)
                hashes[str(p.relative_to(ROOT))] = hashlib.sha256(p.read_bytes()).hexdigest()
            result = audit(tmp, stage)
            assert result['accepted'], str(folder)
        assert load(folder / f'controller-{stage}.json')['data']['case']['controls'] == controls
        point = load(folder / f'point-{stage}.json')
        states.extend(point['states']); maps.extend(load(folder / 'network_reduction_maps.json'))
        sources.append(dict(folder=str(folder.relative_to(BASE)), stage=stage, native_and_original_network_accepted=True))
    assert len(states) == 30
    assert len({(s['factor'], s['id']) for s in states}) == 30
    assert {s['factor'] for s in states} == {.9, .95, 1., 1.05, 1.0625}
    folder = OUT / 'witnesses/common-controller'
    folder.mkdir(parents=True, exist_ok=True)
    contract = copy.deepcopy(load(upper / 'contract.json'))
    contract.update(name='common-controller-constructed-witness', factors=[.9, .95, 1., 1.05, 1.0625],
                    fixed_controller=True, initial_controller=controls, fixed_base=False,
                    free_shared_slopes=0, free_shared_references=0,
                    objective='No new optimization: identical-controller per-demand witness assembly')
    record = dict(stage='derived', status='DERIVED_SHARED_CONTROLLER_WITNESS', native_success=False,
                  native_optimizer_calls=0, artificial_max_pu=0., artificial_net_max_pu=0.)
    for name, value in [('contract.json', contract), ('controller-derived.json', controller),
                        ('stages.json', [record]), ('point-derived.json', dict(record=record, states=states)),
                        ('network_reduction_maps.json', maps)]:
        (folder / name).write_text(json.dumps(value, indent=2) + '\n')
    result = audit(folder, 'derived')
    assert result['original_full_network_valid'] and result['reduction_valid']
    assert not result['native_success'] and not result['accepted']
    physical = load(folder / 'audit-derived.json')
    conclusion = dict(max_dr_mw=max(s['dr_mw'] for s in physical['states']),
                      max_shedding_mw=max(s['shedding_mw'] for s in physical['states']),
                      shared_controller_feasible=True, original_network_valid=True, reduction_valid=True,
                      native_joint_optimization=False, optimal_design=False, optimizer_calls=0,
                      factors=[.9, .95, 1., 1.05, 1.0625], included_states=30,
                      security_scope='Base plus five critical outages per demand; not all 389 connected outages',
                      sources=sources, source_hashes=hashes)
    (OUT / 'common-controller-witness.json').write_text(json.dumps(conclusion, indent=2) + '\n')
    print(json.dumps({k: v for k, v in conclusion.items() if k not in ('sources', 'source_hashes')}))
    return conclusion


if __name__ == '__main__':
    check()
