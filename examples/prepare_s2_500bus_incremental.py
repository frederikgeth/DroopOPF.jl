"""Prepare an expanded 105% feasible start without starting optimization."""
import copy
import hashlib
import json
import shutil
import tempfile
from pathlib import Path
from audit_s2_500bus_loadability import audit_point

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'artifacts/s2_scopf/ieee500_native'
OUT = BASE / 'incremental_shared_recovery'
load = lambda p: json.loads(Path(p).read_text())


def prepare():
    OUT.mkdir(exist_ok=True)
    initial = BASE / 'targeted_demand_diagnostics/relief_priority_witness/emergency-10500-round-1-polish-shedding'
    controller = load(initial / 'controller-derived.json')
    contract = load(initial / 'contract.json')
    states = load(initial / 'point-derived.json')['states']
    reference = next(s for s in states if s['id'] == 'base')
    ledger = load(BASE / 'targeted_demand_diagnostics/selected-operating-witnesses-10500.json')
    added = {'generator_32', 'generator_89', 'generator_37', 'generator_42'}
    sources = [(initial, 'derived', False)]
    for entry in ledger['entries']:
        if entry['event'] not in added:
            continue
        assert entry['accepted']
        folder = BASE / 'emergency_loadability' / entry['path']; stage = entry['stage']
        donor = load(folder / f'controller-{stage}.json')
        assert donor['data']['case']['controls'] == controller['data']['case']['controls']
        raw = load(folder / f'point-{stage}.json')['states']
        base = next(s for s in raw if s['id'] == 'base' and s['factor'] == 1.05)
        for field in ('state', 'taps', 'banks', 'dr', 'shed'):
            assert base[field] == reference[field], field
        states.append(copy.deepcopy(next(s for s in raw if s['id'] == entry['event'] and s['factor'] == 1.05)))
        sources.append((folder, stage, True))
    assert len(states) == 10 and len({s['id'] for s in states}) == 10
    hashes = {}
    for folder, stage, native_required in sources:
        with tempfile.TemporaryDirectory(prefix='s2-incremental-prep-') as name:
            temporary = Path(name)
            for filename in ('contract.json', 'stages.json', f'controller-{stage}.json', f'point-{stage}.json'):
                path = folder / filename
                shutil.copy2(path, temporary / filename)
                hashes[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
            audited = audit_point(temporary, stage)
            assert audited['physical_valid']
            assert not native_required or audited['accepted']
    record = dict(stage='derived', status='DERIVED_EXPANDED_START', native_success=False,
                  native_optimizer_calls=0, artificial_max_pu=0., artificial_net_max_pu=0.)
    contract.update(name='expanded-105-feasible-start', factors=[1.05],
                    outages=sorted(s['id'] for s in states if s['id'] != 'base'),
                    fixed_controller=True, initial_controller=controller['data']['case']['controls'],
                    zero_shedding=True, free_shared_slopes=0, free_shared_references=0,
                    objective='Read-only witness assembly; no optimization')
    folder = OUT / 'witnesses/expanded-105'
    folder.mkdir(parents=True, exist_ok=True)
    for filename, data in [('contract.json', contract), ('stages.json', [record]),
                           ('controller-derived.json', controller),
                           ('point-derived.json', dict(record=record, states=states))]:
        (folder / filename).write_text(json.dumps(data, indent=2) + '\n')
    audited = audit_point(folder, 'derived')
    assert audited['physical_valid'] and not audited['native_success'] and not audited['accepted']
    assert all(s['shedding_mw'] == 0. for s in audited['states'])
    result = dict(status='prepared_awaiting_fresh_equipment_confirmation', optimizer_calls=0,
                  expanded_105_included_states=10, expanded_105_original_network_valid=True,
                  expanded_105_zero_shedding=True, additional_outages=sorted(added),
                  proposed_equipment_timing='Corrective per demand/outage; continuous shunts; no additional movement budgets',
                  proposed_taps=controller['data']['tap_controls'],
                  proposed_shunts=controller['data']['shunt_controls'],
                  shared_free_slopes=51, shared_free_references=51,
                  initial_joint_demands=[.9, .95, 1.], next_joint_demands=[1.05, 1.0625],
                  demand_expansion_gate='Require accepted native feasibility and completed priorities at the preceding step; retain security scope and add failed outages before claiming qualification',
                  ccopt_gate='Recover a physically valid native single-demand 100% design before its joint-demand expansion',
                  source_hashes=hashes, maximum_new_demand=1.0625,
                  equipment_confirmation=None,
                  physical_policy='Base normal/full load; N-1 voltage extension .05 pu, 110% Rate A both ends, 1% DR and 10 MW shedding; zero shedding for independent 105% polishing')
    (OUT / 'PREPARATION.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ('status', 'optimizer_calls', 'expanded_105_included_states', 'expanded_105_original_network_valid', 'expanded_105_zero_shedding')}))
    return result


if __name__ == '__main__':
    prepare()
