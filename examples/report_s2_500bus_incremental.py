"""Summarize incremental campaign results without promoting partial stages to optima."""
import csv
import hashlib
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'artifacts/s2_scopf/ieee500_native'
OUT = BASE / 'incremental_shared_recovery'
load = lambda p: json.loads(Path(p).read_text())


def report():
    attempts = []
    for path in sorted(OUT.glob('*/summary.json')):
        row = load(path); stage = row['stage']; record = row['record']; folder = path.parent
        network = load(folder / f'network-audit-{stage}.json') if (folder / f'network-audit-{stage}.json').exists() else {}
        assert row['accepted'] == network.get('accepted', False)
        if row['accepted']:
            assert record['native_success'] and network['original_full_network_valid'] and network['reduction_valid']
        attempts.append(dict(**row, folder=str(folder.relative_to(BASE)),
                             original_network_valid=network.get('original_full_network_valid', False)))
    pipelines = {p.stem.removeprefix('summary-'): load(p) for p in OUT.glob('summary-*.json')}
    coverages = [load(p) for p in sorted(OUT.glob('audit-coverage-*.json'))]
    calls = sum(a['record']['native_optimizer_calls'] for a in attempts)
    assert calls == sum(len(load(p)) for p in OUT.glob('*/stages.json'))
    assert calls <= load(OUT / 'PROTOCOL.json')['maximum_master_calls']
    separator_calls = sum(len(load(p)) for p in (BASE / 'emergency_loadability/coverage').glob('incremental-*/demand-*/*/stages.json'))
    results = dict(status='bounded_campaign_complete', native_master_calls=calls, separator_native_calls=separator_calls,
                   attempts=attempts, pipelines=pipelines, coverages=coverages,
                   direct_relief_preflight=load(OUT / 'direct-relief-preflight.json'),
                   full_n1_accepted=False, historical_105_controller_retained=True)
    (OUT / 'RESULTS.json').write_text(json.dumps(results, indent=2) + '\n')
    text = ['# Expanded 105% and incremental shared-droop recovery', '',
            'All 131 taps and 11 continuous shunt banks remain corrective within the confirmed absolute bounds, with no additional movement budgets. The 51 slopes and 51 references are free and shared within each master. Exact active response, original equipment constraints and the approved emergency/DR/shedding policy remain in force; independent 105% polishing fixes shedding to zero.', '',
            'The expanded 105% starting point combines the five critical outages with G32/G89/G37/G42 using one previously qualified controller and preventive base. All ten states pass original-network replay with zero shedding. This derived start is not a new optimization.', '',
            'DR and shedding are substituted directly into retained-bus P/Q balances, removing redundant nonnegative auxiliaries and linking equalities. Both formulations accept the same ten-state start with no violations above 1e-6; the direct model has 15,930 variables instead of 31,410. No original terminal rating, reconstructed-bus voltage, tap, bank, response or relief limit is removed.', '',
            '| Attempt | Solver | Demand (%) | Stage | Native status | Physical valid | Accepted |',
            '| --- | --- | --- | --- | --- | --- | --- |']
    for a in attempts:
        factors = ', '.join(f'{100*f:g}' for f in a['factors'])
        text.append(f"| {a['label']} | {a['solver']} | {factors} | {a['stage']} | {a['record']['status']} | {a['original_network_valid']} | {a['accepted']} |")
    text += ['', 'The expanded Ipopt 105% feasibility controller passes all 389 connected outages with zero shedding on the original network. Its DR and final-loss stages remain unresolved. Both Ipopt and MadNLP establish a single shared controller at 90%, 95% and 100% for the base plus five critical outages per demand, including a stricter normal-rating, exactly zero-DR/zero-shedding feasibility recovery. Neither solver completes final loss optimization; shared-controller exhaustive qualification and joint 105%/106.25% expansion remain deferred. CCOpt has no accepted single-100% recovery. These numerical limits do not establish infeasibility.', '',
            'Joint demand expansion requires native joint feasibility and completion of the priority stages, followed by the connected-outage check. CCOpt first faces its independent 100% feasibility/loss gate. A failed gate defers higher-demand work rather than counting it as tested or feasible.', '']
    for name, pipeline in pipelines.items():
        if 'loss_objective_completed' in pipeline:
            selected = pipeline.get('selected')
            text += [f"{name}: last accepted stage {selected['stage'] if selected else 'none'}; loss optimization completed={pipeline['loss_objective_completed']}.", '']
        elif pipeline.get('deferred'):
            text += [f"{name}: deferred — {pipeline['reason']}.", '']
    for c in coverages:
        text += [f"Connected-outage qualification={c['qualified']}: " + '; '.join(f"factor {r['factor']}: {r['passed']}/{r['evaluated']} passed, {r['unchecked']} unchecked" for r in c['rows']), '']
    text += [f'Native master calls: {calls}; native separator calls: {separator_calls}. Ipopt limits use CPU seconds; MadNLP/CCOpt use wall seconds. These are bounded recoveries, not controlled runtime comparisons.', '',
             'Accepted stages require native success plus independent original-500-bus and reduction audits. A physical time-limit point is a feasible witness, not an accepted optimum. Partial masters and incomplete scans do not qualify all 389 connected outages. Original normal-limit certificates and islanding obstructions retain their separate scope. S1 and the declared 14-bus S2 scope remain closed.', '']
    text += ['The following figures compare accepted native feasibility designs for the three-demand, five-critical-outage master. They do not show loss optima. Equipment colors indicate fractions of the absolute allowed range; white cells identify an outaged transformer. Raw selected values are in `accepted-droop-designs.csv` and `accepted-equipment-values.csv`.', '',
             '![Shared feasibility droop parameters](figures/shared-feasibility-droop-parameters.png)', '',
             '![Ipopt feasibility equipment](figures/ipopt-shared-equipment.png)', '',
             '![MadNLP feasibility equipment](figures/madnlp-shared-equipment.png)', '']
    (OUT / 'REPORT.md').write_text('\n'.join(text))
    records = []
    equipment = []
    seen = set()
    for name, pipeline in pipelines.items():
        selected = pipeline.get('selected')
        if not selected or (selected['path'], selected['stage']) in seen:
            continue
        seen.add((selected['path'], selected['stage']))
        folder = BASE / selected['path']; stage = selected['stage']
        study = load(folder / f'controller-{stage}.json')['data']
        point = load(folder / f'point-{stage}.json')
        for state in point['states']:
            for family, controls, values, id_key in [('tap', study['tap_controls'], state['taps'], 'branch_id'), ('shunt', study['shunt_controls'], state['banks'], 'bank_id')]:
                for control in controls:
                    key = str(control[id_key]); value = values.get(key)
                    if value is not None:
                        assert control['lower'] - 1e-6 <= value <= control['upper'] + 1e-6
                    equipment.append(dict(design=name, stage=stage, factor=state['factor'], event=state['id'], family=family, id=key, value=value, lower=control['lower'], upper=control['upper']))
        for a in study['case']['attachments']:
            d = study['case']['controls'][a['control_id'] - 1]
            records.append(dict(design=name, stage=stage, generator=a['generator_id'], slope=d['slope'],
                                v_ref=d['schedule']['v_ref'], loss_objective_completed=pipeline['loss_objective_completed']))
    if records:
        with (OUT / 'accepted-droop-designs.csv').open('w', newline='') as stream:
            writer = csv.DictWriter(stream, fieldnames=list(records[0])); writer.writeheader(); writer.writerows(records)
    if equipment:
        with (OUT / 'accepted-equipment-values.csv').open('w', newline='') as stream:
            writer = csv.DictWriter(stream, fieldnames=list(equipment[0])); writer.writeheader(); writer.writerows(equipment)
    return results


if __name__ == '__main__':
    r = report()
    print(json.dumps({k: r[k] for k in ('status', 'native_master_calls', 'separator_native_calls')}))
