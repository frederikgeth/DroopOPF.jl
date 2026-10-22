"""Independent saved-state replay and source-topology audit; performs no solve."""
from pathlib import Path
import copy
import hashlib
import json
from collections import Counter
from s2_followup_physics import check_case, equipment_valid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/s2_scopf/ieee500_native'
load = lambda p: json.loads(Path(p).read_text())
data = lambda p: load(p)['data']


def topology(case):
    branches = [b for b in case['network']['branches'] if b['available']]
    vertices = {b['id'] for b in case['network']['buses']}
    rows = []
    for event in branches:
        adjacency = {v: [] for v in vertices}
        for b in branches:
            if b['id'] == event['id']:
                continue
            adjacency[b['from_bus']].append(b['to_bus'])
            adjacency[b['to_bus']].append(b['from_bus'])
        unseen = set(vertices)
        components = []
        while unseen:
            stack = [unseen.pop()]
            component = set(stack)
            while stack:
                for v in adjacency[stack.pop()]:
                    if v in unseen:
                        unseen.remove(v)
                        component.add(v)
                        stack.append(v)
            components.append(component)
        if len(components) == 1:
            continue
        small = min(components, key=len)
        gens = [g['id'] for g in case['generators'] if g['available'] and g['bus_id'] in small]
        p = sum(l['p'] for l in case['loads'] if l['bus_id'] in small)
        q = sum(l['q'] for l in case['loads'] if l['bus_id'] in small)
        category = 'loaded_without_generator' if p > 0 and not gens else 'unloaded_generator' if gens else 'unloaded_empty'
        rows.append(dict(branch=event['id'], small_component=sorted(small), p_load_pu=p,
                         q_load_pu=q, generators=gens, category=category))
    counts = dict(Counter(r['category'] for r in rows))
    return dict(online_branches=len(branches), online_generators=sum(g['available'] for g in case['generators']),
                connected_branch_outages=len(branches)-len(rows), islanding_outages=len(rows),
                categories=counts, islands=rows,
                full_n1_possible_with_all_loads_served=not counts.get('loaded_without_generator', 0))


def replay(study, result, angles):
    rows = []
    events = {'base': dict(branch_ids=[], generator_ids=[])}
    events.update({c['id']: c for c in study['contingencies']})
    assert set(result['states']) == set(events)
    assert result['control_policy'] == study['control_policy']
    for sid, event in events.items():
        state = result['states'][sid]
        if state is None:
            rows.append(dict(id=sid, valid=False, missing=True))
            continue
        case = copy.deepcopy(study['case'])
        for b in case['network']['branches']:
            if b['id'] in event['branch_ids']:
                b['available'] = False
        for g in case['generators']:
            if g['id'] in event['generator_ids']:
                g['available'] = False
        ck = check_case(case, state, result['tap_settings'][sid], result['shunt_settings'][sid], angles)
        eq = equipment_valid(study, case, result['tap_settings'][sid], result['shunt_settings'][sid])
        coupling = 0.
        if sid != 'base' and result['states']['base'] is not None:
            total = sum(study['participation'][str(g['id'])] for g in case['generators'] if g['available'])
            coupling = max(abs(state['pg'][i]-result['states']['base']['pg'][i]
                               -study['participation'][str(g['id'])]/total*result['balancing_power'][sid])
                           for i, g in enumerate(case['generators']) if g['available'])
        # Keep the report compact; raw source states permit complete replay.
        ck.pop('branch_max_terminal_s_pu')
        ck.pop('bus_balance')
        ck.pop('droop_by_generator')
        ck.update(id=sid, equipment_valid=eq, response_coupling_max_pu=coupling)
        ck['valid'] &= eq and coupling <= 1e-6
        rows.append(ck)
    return rows


def reserve_certificates(study, result):
    """Necessary active-reserve test for a fixed base, independent of AC solves."""
    gens = study['case']['generators']
    pg = result['states']['base']['pg']
    demand = sum(l['p'] for l in study['case']['loads'])
    rows = []
    for i, g in enumerate(gens):
        if not g['available']:
            continue
        others = [(j, h) for j, h in enumerate(gens) if h['available'] and j != i]
        total = sum(study['participation'][str(h['id'])] for j, h in others)
        delta, limiting = min(((h['p_max']-pg[j])/(study['participation'][str(h['id'])]/total), h['id'])
                              for j, h in others if study['participation'][str(h['id'])] > 0)
        supply = sum(pg[j] for j, h in others)+delta
        if supply < demand-1e-6:
            rows.append(dict(outage=g['id'], limiting_generator=limiting,
                             maximum_balancing_delta_pu=delta, maximum_total_supply_pu=supply,
                             load_pu=demand, minimum_shortfall_mw=(demand-supply)*study['case']['base_power']))
    return rows


def audit():
    original = data(OUT/'pilot_study.json')
    protocols = [OUT/'protocol.json', OUT/'recovery/protocol.json', OUT/'linear_recovery/protocol.json']
    protocols += sorted((OUT/'qualification').glob('protocol-*.json'))
    for protocol in protocols:
        if not protocol.exists():
            continue
        for path, digest in load(protocol)['run_source_hashes'].items():
            assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest() == digest, (str(protocol), path)
    calibrated = data(ROOT/'artifacts/s1_arpae500/calibrated-study.json')['case']
    angles = load(ROOT/'artifacts/s1_free_droop/500/angle_limits.json')
    network_source = ROOT/'test/data/arpae/c1_network01/results/scenario_02_pmin0_qsym/network_model.json'
    assert angles == {k: [b['angmin'], b['angmax']] for k, b in load(network_source)['branch'].items()}
    topo = topology(calibrated)
    assert topo['categories'] == dict(loaded_without_generator=171, unloaded_generator=45, unloaded_empty=39)
    assert topo['connected_branch_outages'] + topo['online_generators'] == 389
    assert all(len(r['small_component']) == 1 for r in topo['islands'])
    for island in topo['islands']:
        if island['category'] == 'loaded_without_generator':
            offline = sum(g['bus_id'] in island['small_component'] for g in calibrated['generators'])
            assert island['p_load_pu'] > 1e-6+offline*1e-8
    assert all(b['resistance'] >= 0 for b in calibrated['network']['branches'])
    assert all(s['conductance'] >= 0 for s in calibrated['network']['shunts'])
    assert all(all(g >= 0 for g in b['step_conductances']) for b in calibrated['network']['banks'])
    rows = []
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (
        network_source, ROOT/'artifacts/s1_free_droop/500/angle_limits.json',
        ROOT/'artifacts/s1_arpae500/calibrated-study.json', Path(__file__))}
    for summary in sorted(OUT.rglob('summary.json')):
        record = load(summary)
        if 'solver' not in record or 'accepted' not in record or record.get('initialization_only'):
            continue
        folder = summary.parent
        pairs = [(p, folder/p.name.replace('result-', 'optimized-')) for p in sorted(folder.glob('result-*.json'))]
        if (folder/'result.json').exists():
            pairs.append((folder/'result.json', folder/'input.json'))
        for rp, sp in pairs:
            if not sp.exists():
                continue
            study, result = data(sp), data(rp)
            policy = study['control_policy']
            assert policy['taps'] == policy['shunts'] == 'corrective'
            assert policy['tap_movement_limits'] is None and policy['shunt_movement_limits'] is None
            assert len(study['tap_controls']) == 131 and len(study['shunt_controls']) == 11
            for t in study['tap_controls']:
                assert t['lower'] == .95 and t['upper'] == 1.05
            assert {s['bank_id']: (s['lower'], s['upper']) for s in study['shunt_controls']} == {
                1: (0., .6), 2: (0., 1.), 3: (0., .5), 4: (0., .5), 5: (0., .4),
                6: (0., .5), 9: (0., .5), 12: (0., .5), 13: (0., .3), 14: (0., .8), 16: (0., .4)}
            assert study['mode'] == original['mode'] == 'preventive'
            assert study['participation'] == original['participation']
            assert study['redispatch_limits'] == original['redispatch_limits']
            for key in ('network', 'generators', 'attachments'):
                assert study['case'][key] == original['case'][key], key
            if record['accepted']:
                if (folder/'controller.json').exists():
                    assert study['case']['controls'] == data(folder/'controller.json')['case']['controls']
                for old, new in zip(calibrated['controls'], study['case']['controls']):
                    span = old['capability']['q_max']-old['capability']['q_min']
                    assert .02-1e-8 <= new['slope']*span <= .08+1e-8
                    ref = new['schedule']['v_ref']
                    assert old['schedule']['v_ref']-.02-1e-8 <= ref <= old['schedule']['v_ref']+.02+1e-8
                    assert new['schedule']['v_db_low'] == new['schedule']['v_db_high'] == ref
                    assert new['q_at_deadband'] == 0
                    assert {k: v for k, v in old.items() if k not in ('slope', 'schedule')} == {
                        k: v for k, v in new.items() if k not in ('slope', 'schedule')}
                if (folder/'fixed_base.json').exists():
                    fixed = load(folder/'fixed_base.json')
                    assert result['states']['base'] == fixed['state']
                    assert result['tap_settings']['base'] == fixed['taps']
                    assert result['shunt_settings']['base'] == fixed['susceptances']
            checks = replay(study, result, angles)
            physical = all(c['valid'] for c in checks)
            native = result['termination_status'] in ('LOCALLY_SOLVED', 'ALMOST_LOCALLY_SOLVED', 'OPTIMAL')
            if record['accepted']:
                assert physical and native, str(folder)
            rows.append(dict(directory=str(folder.relative_to(OUT)), result=rp.name, claimed_accepted=record['accepted'],
                             native_success=native, physical_valid=physical, states=checks))
            for p in (sp, rp, summary):
                hashes[str(p.relative_to(ROOT))] = hashlib.sha256(p.read_bytes()).hexdigest()
    proofs = []
    accepted_results = {(r['directory'], r['result']) for r in rows if r['claimed_accepted'] and r['physical_valid']}
    expected_events = {f"branch_{b['id']}" for b in original['case']['network']['branches']
                       if b['available'] and b['id'] not in {i['branch'] for i in topo['islands']}}
    expected_events |= {f"generator_{g['id']}" for g in original['case']['generators'] if g['available']}
    for summary in sorted((OUT/'qualification').glob('summary-*.json')):
        phase = load(summary)
        if not phase['accepted']:
            continue
        label = summary.stem.removeprefix('summary-')
        last = phase['rounds'][-1]
        master = OUT/phase['selected']
        for factor in phase['factors']:
            full = data(master/f'optimized-{float(factor)}.json')
            base = data(master/f'result-{float(factor)}.json')
            scanpath = OUT/f"qualification/{label}/round-{last['round']}/demand-{float(factor)}/scan.json"
            scan = load(scanpath)
            assert scan['exhaustive'] and not scan['failed']
            assert len(scan['attempts']) == 389
            assert {r['event'] for r in scan['attempts']} == expected_events
            for row in scan['attempts']:
                folder = OUT/row['final']['name']
                assert row['final']['accepted'] and (str(folder.relative_to(OUT)), 'result.json') in accepted_results
                single, result = data(folder/'input.json'), data(folder/'result.json')
                assert single['case'] == full['case']
                for key in ('states', 'tap_settings', 'shunt_settings'):
                    assert result[key]['base'] == base[key]['base']
            proofs.append(dict(label=label, solver=phase['solver'], factor=factor, master=phase['selected'],
                               common_base_verified=True, exhaustive_outages=389, unique_states=390))
    report = dict(topology=topo, attempts=rows, source_hashes=hashes, qualification_proofs=proofs,
                  accepted_result_files=sum(r['claimed_accepted'] for r in rows),
                  rejected_result_files=sum(not r['claimed_accepted'] for r in rows),
                  accepted_optimizer_runs=len({r['directory'] for r in rows if r['claimed_accepted']}),
                  rejected_optimizer_runs=len({r['directory'] for r in rows if not r['claimed_accepted']}),
                  counter_unit='A shared multi-demand optimizer run emits several per-demand result files.',
                  accepted_claim_discrepancies=0, full_n1_accepted=False)
    certificate = dict(criterion='Fixed preventive base plus Pmax-weighted response cannot reach total demand before a surviving generator reaches Pmax; active network losses are nonnegative.',
                       certificates=reserve_certificates(original, data(OUT/'pilot-ipopt/result-1.0.json')),
                       source='pilot-ipopt/result-1.0.json')
    (OUT/'fixed_base_active_reserve_certificates.json').write_text(json.dumps(certificate, indent=2)+'\n')
    dest = OUT/'independent_audit.json'
    dest.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({k: report[k] for k in ('accepted_optimizer_runs', 'rejected_optimizer_runs', 'accepted_claim_discrepancies')}))


if __name__ == '__main__':
    audit()
