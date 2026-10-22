"""Summarize the bounded, confirmed 105%-to-106.25% campaign without promoting failed points."""
import hashlib
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'artifacts/s2_scopf/ieee500_native'
OUT = BASE / 'finish_105_multidemand'


def report():
    attempts = []
    for path in sorted(OUT.glob('*/summary.json')):
        row = json.loads(path.read_text())
        stage = str(row['stage'])
        audit_path = path.parent / f'network-audit-{stage}.json'
        audit = json.loads(audit_path.read_text()) if audit_path.exists() else {}
        assert row['accepted'] == bool(audit.get('accepted', False)), str(path)
        if row['accepted']:
            assert row['record']['native_success']
            assert audit['original_full_network_valid'] and audit['reduction_valid']
        row['folder'] = str(path.parent.relative_to(BASE))
        row['original_full_network_valid'] = audit.get('original_full_network_valid', False)
        row['reduction_valid'] = audit.get('reduction_valid', False)
        attempts.append(row)
    pipelines = {p.stem.removeprefix('summary-'): json.loads(p.read_text())
                 for p in OUT.glob('summary-*.json')}
    required = [f'multi-{s}' for s in ('ipopt', 'madnlp', 'ccopt')]
    assert all(k in pipelines for k in required), 'All three backend attempts are required'
    calls = sum(r['record']['native_optimizer_calls'] for r in attempts)
    assert calls == sum(sum(r.get('native_optimizer_calls', 1) for r in json.loads(p.read_text())) for p in OUT.glob('*/stages.json'))
    assert calls <= 40
    coverage_root = BASE / 'emergency_loadability/coverage/finish-105-selected'
    separator_calls = sum(len(json.loads(p.read_text())) for p in coverage_root.glob('demand-*/*/stages.json'))
    result = dict(separator_native_calls=separator_calls, status='bounded_campaign_complete', maximum_demand=1.0625,
                  native_master_calls=calls, attempts=attempts, pipelines=pipelines,
                  common_controller_witness=json.loads((OUT / 'common-controller-witness.json').read_text()),
                  connected_outage_replays=[json.loads(p.read_text()) for p in OUT.glob('audit-coverage-*.json')],
                  historical_105_connected_controller_retained=True,
                  full_n1_security_closed=False,
                  scope='New masters contain base + B36/B219/B562/G14/G60 per demand. Accepted master points do not imply 389-outage qualification.')
    (OUT / 'RESULTS.json').write_text(json.dumps(result, indent=2) + '\n')
    protocol = json.loads((OUT / 'PROTOCOL.json').read_text())
    protocol.update(status=result['status'], optimizer_calls=calls)
    (OUT / 'PROTOCOL.json').write_text(json.dumps(protocol, indent=2) + '\n')
    lines = ['# 500-bus 105% finish and capped multi-demand attempts', '',
             'The confirmed campaign retains corrective taps and continuous shunts within the previously confirmed absolute bounds, with no movement budget. All 51 slopes and 51 reference voltages are shared across the demand/outage states in each free-design master. Base states retain normal limits and full load; outages retain exact active response and the approved emergency/DR/shedding policy.', '',
             'The prior independently replayed physical ceiling is **106.25% for base plus five critical outages**, not 106.5% and not exhaustive connected security. No new demand above 106.25% was attempted.', '',
             'Independent 105% polishing fixes shedding to zero. Higher-demand and multi-demand masters retain the approved 1% DR and 10 MW shedding budgets. The optimization priorities are shedding (where free), DR, normalized smooth emergency departures, then average base active loss. A later-stage failure preserves the last accepted stage; it does not establish a completed loss optimum.', '',
             '| Attempt | Solver | Demands (%) | Stage | Native status | Original network valid | Accepted |',
             '| --- | --- | --- | --- | --- | --- | --- |']
    for r in attempts:
        factors = ', '.join(f'{100*f:g}' for f in r['factors'])
        lines.append(f"| {r['label']} | {r['solver']} | {factors} | {r['stage']} | {r['record']['status']} | {r['original_full_network_valid']} | {'Yes' if r['accepted'] else 'No'} |")
    selected105 = pipelines['finish-105']['selected']
    if selected105:
        physical = json.loads((BASE / selected105['path'] / f"audit-{selected105['stage']}.json").read_text())
        lines += ['', f"105% last accepted priority: {selected105['stage']}; completed loss optimization: {pipelines['finish-105']['loss_objective_completed']}. Maximum selected outage DR: {max(x['dr_mw'] for x in physical['states']):.6f} MW; shedding is fixed at zero. This design uses emergency voltage capacity and is not a normal-limit solution.", '']
    lines += ['New native critical-outage feasibility points pass at 105.5% and 106% (MadNLP) and 106.25% (Ipopt recovery). None of these feasibility-only continuation points is a completed loss optimum.', '']
    witness = result['common_controller_witness']
    lines += ['', '| Joint solver | Last accepted new priority | Loss optimization completed |', '| --- | --- | --- |']
    for solver in ('ipopt', 'madnlp', 'ccopt'):
        pipeline = pipelines[f'multi-{solver}']; selected = pipeline['selected']
        lines.append(f"| {solver} | {selected['stage'] if selected else 'None'} | {pipeline['loss_objective_completed']} |")
    initial_checks = []
    for path in OUT.glob('multi-*-anchor/initial-model-feasibility.json'):
        initial_checks.append(dict(attempt=path.parent.name, **json.loads(path.read_text())))
    result['initial_model_checks'] = initial_checks
    (OUT / 'RESULTS.json').write_text(json.dumps(result, indent=2) + '\n')
    lines += ['', 'A constructed common-controller witness passes original-network and reduction replay for all 30 states across the five demands. It uses up to 9.998043 MW shedding under the approved 10 MW cap. Each demand component comes from a native accepted solve with identical droops; assembly makes zero optimizer calls. This proves targeted shared-controller feasibility, not joint optimality or exhaustive connected security.', '']
    for diagnostic in initial_checks:
        if 'evaluation_error' in diagnostic:
            lines += [f"Initial joint-model check, {diagnostic['attempt']}: the generic MOI checker lacks a distance function for complementarity sets; this diagnostic limitation does not prevent the native CCOpt attempt. The independent physical and projection equations remain the acceptance checks.", '']
        else:
            lines += [f"Initial joint-model check, {diagnostic['attempt']}: {diagnostic['violations_over_1e6']} constraint violations above 1e-6.", '']
    for replay in result['connected_outage_replays']:
        lines += [f"New 105% connected-outage replay: qualified={replay['qualified']}; " + '; '.join(f"{r['passed']}/{r['evaluated']} evaluated, {r['unchecked']} unchecked" for r in replay['rows']), '']
    lines += ['', 'The new 105% scan stops after G32, G89, G37 and G42 remain unresolved. Three accepted branch master witnesses lie outside that early-stopped scan prefix. The failures give no new infeasibility certificate; 383 scan events are unchecked. The preceding 389/389 controller remains the qualified 105% result.', '']
    lines += ['', 'Stage limits use the backend-native setting: Ipopt CPU time; MadNLP/CCOpt wall time. These bounded attempts are not a controlled runtime benchmark.', '']
    lines += ['', f'Native master/initializer calls: **{calls}** (bound: 40); connected-outage separator calls: **{separator_calls}**. Fixed-controller initializer calls are recorded separately by their names; they are not free-droop design qualifications.', '',
              'All stored candidate points are reconstructed and audited against the original 500-bus network, including both terminals of every original online line/transformer with its original rating and the approved emergency multiplier. Network reduction eliminates 70 zero-injection buses and retains equipment constraints. Native time/iteration limits and physically invalid iterates remain rejected.', '',
              'The earlier 105% controller retains its 389/389 connected-outage qualification and the separately audited DR-first zero-shedding allocation. It is not silently replaced by a new controller validated only on five outages. Full N−1 remains open because of the separately documented islanding obstructions. S1 and the declared 14-bus S2 scope remain closed.', '',
              'Machine-readable results: `RESULTS.json`; confirmed policy: `PROTOCOL.json`; exact executed sources, native records, controllers, points and independent original-network/reduction audits are retained in each attempt folder.', '']
    (OUT / 'REPORT.md').write_text('\n'.join(lines))
    design_rows, equipment_rows = [], []
    for label in ['finish-105', 'continue-10550', 'continue-10600', 'continue-10625', *required]:
        pipeline = pipelines.get(label, {})
        selected = pipeline.get('selected')
        if not selected:
            continue
        folder = BASE / selected['path']; stage = selected['stage']
        study = json.loads((folder / f'controller-{stage}.json').read_text())['data']
        for attachment in study['case']['attachments']:
            control = study['case']['controls'][attachment['control_id'] - 1]
            design_rows.append(dict(design=label, stage=stage, generator=attachment['generator_id'],
                                    slope=control['slope'], v_ref=control['schedule']['v_ref'],
                                    q_min=control['capability']['q_min'], q_max=control['capability']['q_max'],
                                    loss_objective_completed=pipeline['loss_objective_completed']))
        point = json.loads((folder / f'point-{stage}.json').read_text())
        for state in point['states']:
            for family, config, id_key in [('taps', study['tap_controls'], 'branch_id'),
                                           ('banks', study['shunt_controls'], 'bank_id')]:
                for control in config:
                    key = str(control[id_key]); value = state[family].get(key)
                    if value is not None:
                        assert control['lower'] - 1e-6 <= value <= control['upper'] + 1e-6
                    equipment_rows.append(dict(design=label, stage=stage, factor=state['factor'],
                                               scenario=state['id'], family=family, control=key, value=value,
                                               available=value is not None, lower=control['lower'], upper=control['upper']))
    for name, records in [('accepted-droop-designs.csv', design_rows), ('accepted-equipment-values.csv', equipment_rows)]:
        if records:
            with (OUT / name).open('w', newline='') as stream:
                writer = csv.DictWriter(stream, fieldnames=list(records[0])); writer.writeheader(); writer.writerows(records)
    source_paths = [ROOT / 'examples/s2_500bus_finish_multidemand.jl',
                    ROOT / 'examples/report_s2_500bus_finish_multidemand.py',
                    ROOT / 'examples/s2_arpae500_loadability.jl',
                    ROOT / 'examples/s2_500bus_scaled_mpcc.jl',
                    ROOT / 'examples/audit_s2_500bus_finish_coverage.py',
                    ROOT / 'examples/check_s2_500bus_common_controller.py',
                    ROOT / 'examples/check_s2_500bus_finish_multidemand.py',
                    *[ROOT / name for name in ('README.md', 'ROADMAP.md', 'CHANGELOG.md', 'docs/src/s2_500bus.md',
                       'artifacts/s2_scopf/ieee500_native/REPORT.md', 'artifacts/s2_scopf/ieee500_native/STATUS.json',
                       'artifacts/s2_scopf/ieee500_native/CURRENT_RESULTS.json')]]
    paths = sorted(set([p for p in OUT.rglob('*') if p.is_file() and p.name != 'source_manifest.json'] + source_paths))
    manifest = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    (OUT / 'source_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return result


if __name__ == '__main__':
    r = report()
    print(json.dumps(dict(native_master_calls=r['native_master_calls'],
                          accepted_attempts=sum(x['accepted'] for x in r['attempts']))))
