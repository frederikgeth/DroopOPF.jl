"""Independent Python replay of fixed-equipment P3 AC time-series results.

Uses the established scalar complex-current physics evaluator; never calls an
optimizer or Julia's constraint functions. No work is performed on import.
"""
import copy
import json
import math
from pathlib import Path
from s2_followup_physics import check_case


def audit_attempt(folder):
    folder = Path(folder)
    load = lambda p: json.loads(Path(p).read_text())
    contract = load(folder / 'contract.json')
    result = load(folder / 'result.json')
    periods = result['periods']
    durations = contract['duration_hours']
    assert len(periods) == len(durations) > 0
    assert all(math.isfinite(d) and d > 0 for d in durations)
    policy = {str(p['control_id']): p for p in contract['droop_controls']}
    assert len(policy) == len(contract['droop_controls'])
    assert set(result['droops']) == set(policy)
    assert [{k: v for k, v in p.items() if k != 'initial'} for p in result['droop_controls']] == contract['droop_controls']
    rows, energy, ramp_violation = [], 0., 0.
    valid = result['termination_status'] in ('LOCALLY_SOLVED', 'ALMOST_LOCALLY_SOLVED', 'OPTIMAL')
    reference = load(folder / 'period-1.json')['data']['case']
    for t, (o, duration) in enumerate(zip(periods, durations)):
        c = load(folder / f'period-{t+1}.json')['data']['case']
        assert {k:v for k,v in c.items() if k not in ('loads', 'id')} == {k:v for k,v in reference.items() if k not in ('loads', 'id')}
        assert [(l['id'], l['bus_id']) for l in c['loads']] == [(l['id'], l['bus_id']) for l in reference['loads']]
        for key, settings in result['droops'].items():
            original = c['controls'][int(key)-1]
            s = original['schedule']
            defaults = dict(slope=original['slope'], v_ref=s['v_ref'],
                            deadband_low=s['v_ref']-s['v_db_low'], deadband_high=s['v_db_high']-s['v_ref'])
            assert set(settings) == set(defaults)
            for k, value in settings.items():
                lo, hi = policy[key]['bounds'][k] or (defaults[k], defaults[k])
                valid &= math.isfinite(value) and lo-1e-6 <= value <= hi+1e-6
            original['slope'] = settings['slope']
            original['schedule'].update(v_ref=settings['v_ref'],
                v_db_low=settings['v_ref']-settings['deadband_low'],
                v_db_high=settings['v_ref']+settings['deadband_high'])
        s = o['state']
        if s is None:
            return dict(valid=False, reason='missing_state')
        assert set(s) == {'vm', 'va', 'pg', 'qg'}
        assert len(s['vm']) == len(s['va']) == len(c['network']['buses'])
        assert len(s['pg']) == len(s['qg']) == len(c['generators'])
        assert all(math.isfinite(v) for vec in s.values() for v in vec)
        angles = {str(b['id']): contract['angle_limits'].get(str(b['id']), [-math.inf, math.inf]) for b in c['network']['branches']}
        physics = check_case(c, s, {}, {}, angles)
        valid &= physics['valid'] and o['termination_status'] == result['termination_status'] and o['primal_status'] == result['primal_status']
        loss = c['base_power']*(sum(s['pg'])-sum(l['p'] for l in c['loads']))
        valid &= abs(loss-o['objective']) <= 1e-6
        energy += duration*loss
        if t:
            for i, g in enumerate(c['generators']):
                limits = contract['ramp_limits'].get(str(g['id']))
                if limits is None:
                    continue
                up, down = limits
                delta = s['pg'][i]-periods[t-1]['state']['pg'][i]
                ramp_violation = max(ramp_violation, delta-up*durations[t-1], -delta-down*durations[t-1])
        rows.append(dict(period=t+1, loss_mw=loss, valid=physics['valid'],
                         balance_max_pu=physics['power_balance_max_pu'], exact_droop_max_pu=physics['exact_droop_max_pu']))
    valid &= ramp_violation <= 1e-6 and abs(energy-result['objective_mwh']) <= 1e-6
    return dict(valid=bool(valid), periods=rows, objective_recomputed_mwh=energy,
                objective_error_mwh=abs(energy-result['objective_mwh']), ramp_violation_pu=ramp_violation)


def audit_campaign(root):
    root = Path(root)
    checks = []
    for n in (3, 14, 500):
        for lane in ('fixed', 'design'):
            folder = root / str(n) / lane
            check = audit_attempt(folder)
            assert check['valid'] == json.loads((folder / 'summary.json').read_text())['accepted']
            checks.append(dict(buses=n, lane=lane, **check))
    return dict(valid=all(r['valid'] for r in checks), accepted_periods=sum(len(r['periods']) for r in checks if r['valid']), attempts=checks)

if __name__ == '__main__':
    import sys
    root = Path(sys.argv[1])
    check = audit_campaign(root)
    (root / 'python-replay.json').write_text(json.dumps(check, indent=2)+'\n')
    print(json.dumps(dict(valid=check['valid'], accepted_periods=check['accepted_periods'])))
    assert check['valid']
