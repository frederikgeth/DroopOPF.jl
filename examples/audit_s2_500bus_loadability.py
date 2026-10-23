"""Independent replay of explicit emergency/DR/shedding and Phase-I points."""
import copy
import cmath
import hashlib
import json
from pathlib import Path
from s2_followup_physics import check_case, equipment_valid

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT/'artifacts/s2_scopf/ieee500_native'
OUT = BASE/'emergency_loadability'
load = lambda p: json.loads(Path(p).read_text())


def audit_point(folder, stage=None):
    folder = Path(folder)
    contract = load(folder/'contract.json')
    stages = load(folder/'stages.json')
    stage = stage or stages[-1]['stage']
    point = load(folder/f'point-{stage}.json')
    study = load(folder/f'controller-{stage}.json')['data']
    source_study = load(BASE/'pilot_study.json')['data']
    physical_source = copy.deepcopy(study['case'])
    physical_source['controls'] = source_study['case']['controls']
    assert physical_source == source_study['case'], 'Unexpected source equipment, demand or generator changes'
    for key in ('mode', 'participation', 'redispatch_limits', 'reactive_assignments', 'control_policy'):
        assert study[key] == source_study[key], key
    for key in ('tap_controls', 'shunt_controls'):
        strip_initial = lambda controls: [{k: v for k, v in c.items() if k != 'initial'} for c in controls]
        assert strip_initial(study[key]) == strip_initial(source_study[key]), key
    for d, ref in zip(study['case']['controls'], source_study['case']['controls']):
        assert d['capability'] == ref['capability']
    if contract['fixed_controller'] and 'initial_controller' in contract:
        assert study['case']['controls'] == contract['initial_controller'], 'Fixed controller changed'
    angles = load(ROOT/'artifacts/s1_free_droop/500/angle_limits.json')
    reference = load(ROOT/'artifacts/s1_arpae500/calibrated-study.json')['data']['case']
    droop_valid = len(study['case']['controls']) == 51
    for d, ref in zip(study['case']['controls'], reference['controls']):
        span = ref['capability']['q_max']-ref['capability']['q_min']
        droop_valid &= .02/span-1e-8 <= d['slope'] <= .08/span+1e-8
        droop_valid &= abs(d['schedule']['v_ref']-ref['schedule']['v_ref']) <= .02+1e-8
        droop_valid &= abs(d['schedule']['v_db_low']-d['schedule']['v_ref']) <= 1e-10
        droop_valid &= abs(d['schedule']['v_db_high']-d['schedule']['v_ref']) <= 1e-10
        droop_valid &= d['q_at_deadband'] == 0
    events = {e['id']: e for e in study['contingencies']}
    # The controller file retains its seed event list; the run contract is authoritative.
    source = load(BASE/'pilot_study.json')['data']['case']
    result = []
    base_rows = {row['factor']: row for row in point['states'] if row['id'] == 'base'}
    if contract.get('fixed_base_reference'):
        for reference in contract['fixed_base_reference']:
            row = base_rows[reference['factor']]
            for key in ('state', 'taps', 'banks'):
                assert row[key] == reference[key], 'Fixed base changed'
    for row in point['states']:
        case = copy.deepcopy(study['case'])
        f, sid = row['factor'], row['id']
        for l in case['loads']:
            l['p'] *= f
            l['q'] *= f
        post = sid != 'base'
        if post:
            kind, identifier = sid.rsplit('_', 1)
            identifier = int(identifier)
            family = case['network']['branches'] if kind == 'branch' else case['generators']
            assert kind in ('branch', 'generator')
            next(item for item in family if item['id'] == identifier)['available'] = False
        normal = copy.deepcopy(case)
        if post and contract['emergency']:
            for b in case['network']['buses']:
                b['v_min'] -= .05
                b['v_max'] += .05
            for b in case['network']['branches']:
                b['thermal_limit'] *= contract['thermal_multiplier']
        relief_valid = True
        dr_total = shed_total = relabel_potential = 0.
        for l in case['loads']:
            d, s = row['dr'][str(l['id'])], row['shed'][str(l['id'])]
            eligible = post and contract['relief'] and l['p'] > 0
            relief_valid &= d >= -1e-8 and s >= -1e-8
            relief_valid &= d <= (.01*l['p'] if eligible else 0.)+1e-8
            relief_valid &= d+s <= (.1*l['p'] if eligible else 0.)+1e-8
            if eligible:
                relabel_potential += max(0., min(s,.01*l['p']-d))
            if l['p'] > 0:
                fraction = (d+s)/l['p']
                l['p'] *= 1-fraction
                l['q'] *= 1-fraction
            dr_total += d
            shed_total += s
        relief_valid &= shed_total*case['base_power'] <= 10.+1e-6
        if contract.get('zero_shedding'):
            relief_valid &= abs(shed_total) <= 1e-8
        if contract.get('zero_dr'):
            relief_valid &= abs(dr_total) <= 1e-8
        checks = check_case(case, row['state'], row['taps'], row['banks'], angles)
        eq = equipment_valid(study, case, row['taps'], row['banks'])
        coupling = 0.; response_cap=float(contract.get('response_relaxation_cap',0.)); response_cap_valid=True;response_rows=[]
        if post:
            base = base_rows[f]
            total = sum(study['participation'][str(g['id'])] for g in case['generators'] if g['available'])
            coupling = max(abs(row['state']['pg'][i]-base['state']['pg'][i]
                               -study['participation'][str(g['id'])]/total*row['delta'])
                           for i, g in enumerate(case['generators']) if g['available'])
            for i,g in enumerate(case['generators']):
                if not g['available']:continue
                error=row['state']['pg'][i]-base['state']['pg'][i]-study['participation'][str(g['id'])]/total*row['delta']
                cap=response_cap*max(g['p_max'],1e-6)
                response_cap_valid &= abs(error)<=cap+1e-6
                response_rows.append(dict(generator=g['id'],error_mw=error*case['base_power'],
                    error_pmax_fraction=abs(error)/max(g['p_max'],1e-6),allowed_fraction=response_cap))
        flow = checks.pop('branch_max_terminal_s_pu')
        balances = checks.pop('bus_balance')
        checks['largest_balance_residual_buses'] = sorted(balances, key=lambda r:max(abs(r['p_pu']),abs(r['q_pu'])), reverse=True)[:10] if checks['power_balance_max_pu'] > 1e-6 else []
        checks.pop('droop_by_generator')
        volts = []
        for i, b in enumerate(normal['network']['buses']):
            v = row['state']['vm'][i]
            violation = max(b['v_min']-v, v-b['v_max'], 0.)
            if violation > 1e-6:
                volts.append(dict(bus=b['id'], vm=v, normal_lower=b['v_min'], normal_upper=b['v_max'], violation_pu=violation))
        overloaded = [dict(branch=b['id'], kind=b['kind'], loading_pu=flow[str(b['id'])],
                           rate_a_pu=b['thermal_limit'], ratio=flow[str(b['id'])]/b['thermal_limit'])
                      for b in normal['network']['branches'] if b['available'] and flow[str(b['id'])] > b['thermal_limit']+1e-6]
        bus_indices = {b['id']: i for i, b in enumerate(case['network']['buses'])}
        voltages = [cmath.rect(v, a) for v, a in zip(row['state']['vm'], row['state']['va'])]
        branch_losses = []
        for b in case['network']['branches']:
            if not b['available']:
                continue
            tau = cmath.rect(row['taps'].get(str(b['id']), b['tap_ratio']), b['phase_shift'])
            current = (voltages[bus_indices[b['from_bus']]]/tau-voltages[bus_indices[b['to_bus']]])/complex(b['resistance'], b['reactance'])
            branch_losses.append(dict(branch=b['id'],kind=b['kind'],from_bus=b['from_bus'],to_bus=b['to_bus'],
                                      loss_mw=b['resistance']*abs(current)**2*case['base_power']))
        checks.update(factor=f, id=sid, dr_mw=dr_total*case['base_power'], shedding_mw=shed_total*case['base_power'],
                      shedding_replaceable_by_DR_without_physics_changes_mw=relabel_potential*case['base_power'],
                      artificial_max_pu=row['artificial_max_pu'], equipment_valid=eq, relief_valid=bool(relief_valid),
                      droop_policy_valid=bool(droop_valid), response_coupling_max_pu=coupling,
                      max_normal_loading_ratio=max(flow[str(b['id'])]/b['thermal_limit'] for b in normal['network']['branches'] if b['available']),
                      vm_min_pu=min(row['state']['vm']), vm_max_pu=max(row['state']['vm']),
                      generation_mw=sum(row['state']['pg'])*case['base_power'],
                      served_demand_mw=sum(l['p'] for l in case['loads'])*case['base_power'],
                      active_losses_mw=(sum(row['state']['pg'])-sum(l['p'] for l in case['loads']))*case['base_power'],
                      aggregate_pmax_headroom_mw=(sum(g['p_max'] for g in case['generators'] if g['available'])-sum(row['state']['pg']))*case['base_power'],
                      closest_pmax_generators=sorted([
                          dict(generator=g['id'],utilization=row['state']['pg'][i]/g['p_max'],headroom_mw=(g['p_max']-row['state']['pg'][i])*case['base_power'])
                          for i,g in enumerate(case['generators']) if g['available'] and g['p_max']>0], key=lambda r:-r['utilization'])[:10],
                      largest_normal_loading_branches=sorted([
                          dict(branch=b['id'],kind=b['kind'],from_bus=b['from_bus'],to_bus=b['to_bus'],ratio=flow[str(b['id'])]/b['thermal_limit'])
                          for b in normal['network']['branches'] if b['available']],key=lambda r:-r['ratio'])[:10],
                      largest_resistive_loss_branches=sorted(branch_losses,key=lambda r:-r['loss_mw'])[:10],
                      total_branch_resistive_loss_mw=sum(b['loss_mw'] for b in branch_losses),
                      normal_voltage_departures=volts, normal_thermal_departures=overloaded)
        # An original-equation witness can be valid even when internal signed
        # restoration variables cancel. Keep that mathematical feasibility
        # evidence separate from the stronger solver/restoration acceptance gate.
        checks['response_free_physical_valid'] = bool(checks['valid'] and eq and relief_valid and droop_valid and row['artificial_max_pu']<=1e-7)
        checks['diagnostic_valid'] = checks['response_free_physical_valid'] and bool(response_cap_valid)
        checks['response_relaxation_cap_fraction']=response_cap
        checks['largest_response_rule_errors']=sorted(response_rows,key=lambda r:abs(r['error_mw']),reverse=True)[:10]
        checks['response_error_max_pmax_fraction']=max((r['error_pmax_fraction'] for r in response_rows),default=0.)
        checks['equilibrium_witness_valid'] = bool(checks['valid'] and eq and relief_valid and droop_valid and coupling <= 1e-6)
        checks['valid'] = checks['equilibrium_witness_valid'] and row['artificial_max_pu'] <= 1e-7
        checks['strict_valid'] = checks['valid'] and not volts and not overloaded and dr_total <= 1e-8 and shed_total <= 1e-8
        result.append(checks)
    expected = {(f, sid) for f in contract['factors'] for sid in ['base']+contract['outages']}
    actual = {(r['factor'], r['id']) for r in result}
    assert expected == actual
    summary = dict(stage=stage, physical_valid=all(r['valid'] for r in result),
                   equilibrium_witness_valid=all(r['equilibrium_witness_valid'] for r in result),
                   strict_valid=all(r['strict_valid'] for r in result),
                   native_success=point['record']['native_success'],
                   accepted=point['record']['native_success'] and all(r['valid'] for r in result) and contract.get('response_relaxation_cap',0.)==0.,
                   response_free_physical_valid=all(r['response_free_physical_valid'] for r in result),
                   diagnostic_accepted=point['record']['native_success'] and all(r['diagnostic_valid'] for r in result) and contract.get('response_relaxation_cap',0.)>0.,
                   states=result, contract_sha256=hashlib.sha256((folder/'contract.json').read_bytes()).hexdigest(),
                   point_sha256=hashlib.sha256((folder/f'point-{stage}.json').read_bytes()).hexdigest())
    summary['auditor_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    summary['physics_helper_sha256'] = hashlib.sha256((ROOT/'examples/s2_followup_physics.py').read_bytes()).hexdigest()
    (folder/f'audit-{stage}.json').write_text(json.dumps(summary, indent=2)+'\n')
    return summary


def audit_strict_coverage():
    from audit_s2_arpae500 import replay
    angles = load(ROOT/'artifacts/s1_free_droop/500/angle_limits.json')
    rows = []
    for path in sorted((OUT/'strict').glob('full-*/summary.json')):
        summary = load(path)
        final = summary['rounds'][-1]
        scan = load(path.parent/f"round-{final['round']}/scan.json")
        evaluated = []
        common = None
        for event in scan['attempts']:
            native = event['final']
            folder = BASE/native['name']
            if not (folder/'result.json').exists():
                evaluated.append(dict(event=event['event'], accepted=False, missing_result=True))
                continue
            study = load(folder/'input.json')['data']
            result = load(folder/'result.json')['data']
            base = dict(state=result['states']['base'], taps=result['tap_settings']['base'], banks=result['shunt_settings']['base'],
                        controller=study['case']['controls'])
            if common is None:
                common = base
            assert common == base, 'Outage checks did not share one base and controller'
            checks = replay(study, result, angles)
            physical = all(r['valid'] for r in checks)
            assert not native['accepted'] or physical
            evaluated.append(dict(event=event['event'], accepted=native['accepted'] and physical))
        assert len({r['event'] for r in evaluated}) == len(evaluated)
        accepted = summary['accepted'] and len(evaluated) == 389 and all(r['accepted'] for r in evaluated)
        assert accepted == summary['accepted']
        rows.append(dict(factor=summary['factor'], accepted=accepted, evaluated=len(evaluated),
                         failed=[r['event'] for r in evaluated if not r['accepted']],
                         common_base_and_controller_verified=common is not None))
    record = dict(rows=rows, scope='Independent final-round replay of strict-limit connected-outage scans')
    (OUT/'strict/coverage_audit.json').write_text(json.dumps(record, indent=2)+'\n')
    return record


def audit_decomposition():
    path = OUT/'decomposition/summary.json'
    summary = load(path)
    controller_path = OUT/'decomposition/shared-controller.json'
    if not controller_path.exists():
        return dict(accepted=False, incomplete=True)
    controls = load(controller_path)['data']['case']['controls']
    rows = []
    for row in summary['rows']:
        folder = OUT/row['path']
        if row['stage'] is None:
            rows.append(dict(factor=row['factor'],accepted=False))
            continue
        checks = audit_point(folder,row['stage'])
        actual = load(folder/f"controller-{row['stage']}.json")['data']['case']['controls']
        assert actual == controls, 'Demand decomposition used different controllers'
        rows.append(dict(factor=row['factor'],accepted=checks['accepted'],
                         maximum_dr_mw=max(s['dr_mw'] for s in checks['states']),
                         maximum_shedding_mw=max(s['shedding_mw'] for s in checks['states'])))
    expected = [.9,.95,1.,1.05,1.1]
    training = [r for r in rows if r['factor'] in expected]
    accepted = sorted(r['factor'] for r in training) == expected and all(r['accepted'] for r in training)
    assert accepted == summary['accepted']
    record = dict(accepted=accepted,rows=rows,exact_same_controller_verified=True,
                  controller_sha256=hashlib.sha256(controller_path.read_bytes()).hexdigest(),
                  scope='Three critical connected outages per demand; no exhaustive-security or joint-optimality claim')
    (OUT/'decomposition/independent_audit.json').write_text(json.dumps(record,indent=2)+'\n')
    return record


def audit_emergency_coverage(label='compact-five-demand'):
    from audit_s2_arpae500 import topology
    path = OUT/f'coverage/{label}/summary.json'
    if path.exists():
        summary = load(path)
    else:
        # Checkpoint coverage is evidence only for the events actually saved.
        summary = dict(rows=[load(p) for p in sorted(path.parent.glob('progress-*.json'))], accepted=False)
    source = load(BASE/'pilot_study.json')['data']['case']
    topo = topology(source)
    islands = {r['branch'] for r in topo['islands']}
    expected_events = {f"branch_{b['id']}" for b in source['network']['branches'] if b['available'] and b['id'] not in islands}
    expected_events |= {f"generator_{g['id']}" for g in source['generators'] if g['available']}
    assert len(expected_events) == 389
    controller = load(OUT/'decomposition/shared-controller.json')['data']['case']['controls']
    shared = {(r['factor'],r['id']):r for r in load(OUT/'decomposition/shared-states.json')}
    factors = []
    cache = {}
    for group in summary['rows']:
        f = group['factor']
        events = []
        for entry in group['rows']:
            folder = OUT/entry['path']
            if 'stage' in entry:
                stage = entry['stage']
            else:
                stage = load(folder/'stages.json')[-1]['stage']
            if not (folder/f'point-{stage}.json').exists():
                assert not entry['accepted']
                events.append(dict(event=entry['event'],accepted=False,missing_point=True))
                continue
            key = (str(folder),stage)
            if key not in cache:
                ck = audit_point(folder,stage)
                controls = load(folder/f'controller-{stage}.json')['data']['case']['controls']
                assert controls == controller
                cache[key] = ck,load(folder/f'point-{stage}.json')['states']
            ck, raw = cache[key]
            base = next(r for r in raw if r['factor'] == f and r['id'] == 'base')
            reference = shared[(f,'base')]
            for field in ('state','taps','banks','dr','shed'):
                assert base[field] == reference[field], 'Scenario-dependent preventive base'
            row = next(r for r in ck['states'] if r['factor'] == f and r['id'] == entry['event'])
            accepted = ck['native_success'] and row['valid']
            assert not entry['accepted'] or accepted
            events.append(dict(event=entry['event'],accepted=bool(entry['accepted'] and accepted),
                dr_mw=row['dr_mw'],shedding_mw=row['shedding_mw'],
                replaceable_shedding_mw=row['shedding_replaceable_by_DR_without_physics_changes_mw'],
                voltage_departures=len(row['normal_voltage_departures']),thermal_departures=len(row['normal_thermal_departures']),
                max_normal_loading_ratio=row['max_normal_loading_ratio'],
                reused_master_state=entry.get('reused_master_state',False),reused_checkpoint=entry.get('reused_checkpoint',False)))
        actual = {e['event'] for e in events}
        assert len(actual) == len(events) and actual <= expected_events
        assert not group['exhaustive'] or actual == expected_events
        accepted = actual == expected_events and all(e['accepted'] for e in events)
        factors.append(dict(factor=f,evaluated=len(events),accepted=accepted,exhaustive=actual == expected_events,
                            failed=[e['event'] for e in events if not e['accepted']],
                            max_dr_mw=max((e.get('dr_mw',0.) for e in events if e['accepted']),default=0.),
                            max_shedding_mw=max((e.get('shedding_mw',0.) for e in events if e['accepted']),default=0.),
                            events=events))
    accepted = {r['factor'] for r in factors} == {.9,.95,1.,1.05,1.1} and all(r['accepted'] for r in factors)
    assert accepted == summary['accepted']
    result = dict(accepted=accepted,factors=factors,exact_shared_controller_and_fixed_bases_verified=True,
                  full_n1_accepted=False,scope='Checkpointed events only; target is 389 connected outages at each of five training demands')
    (path.parent/'independent_audit.json').write_text(json.dumps(result,indent=2)+'\n')
    return result


if __name__ == '__main__':
    import sys
    if sys.argv[1] == '--coverage':
        r = audit_strict_coverage()
    elif sys.argv[1] == '--decomposition':
        r = audit_decomposition()
    elif sys.argv[1] == '--emergency-coverage':
        r = audit_emergency_coverage()
    else:
        r = audit_point(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
    print(json.dumps({k: v for k, v in r.items() if k != 'states'}, indent=2))
