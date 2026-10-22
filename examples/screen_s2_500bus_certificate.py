"""Reuse a saved Farkas ray for exact necessary-condition demand screening.

The extended relaxations only remove constraints or weaken necessary loss
inequalities. A nonpositive gap is inconclusive, never evidence of feasibility.
"""
from fractions import Fraction as Q
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT/'artifacts/s2_scopf/ieee500_native'
OUT = BASE/'emergency_loadability'
F = lambda x: Q(x.replace('//', '/') if isinstance(x, str) else x)


def screen(factor, emergency=False, relief=False, tolerant=False):
    proof = json.loads((BASE/'active_loss_diagnostic/result.json').read_text())
    source = json.loads((BASE/'pilot_study.json').read_text())['data']['case']
    case = proof['case']
    branches = [b for b in case['network']['branches'] if b['available']]
    buses = {b['id']: b for b in case['network']['buses']}
    taps = {b['branch_id']: b for b in proof['tap_controls']}
    mapping = proof['variable_map']
    bounds = [(F(l), F(u)) for l, u in proof['variable_bounds']]
    rows = [({int(i): F(a) for i, a in r['coefficients'].items()}, F(r['rhs'])) for r in proof['rows']]
    nb = len(branches)
    start_bus = 2+2*nb
    start_support = start_bus+2*len(buses)
    tol = F('0.000001') if tolerant else F(0)
    unavailable = F('0.00000001') if tolerant else F(0)
    for i, g in enumerate(case['generators']):
        bounds[i] = (F(g['p_min'])-tol, F(g['p_max'])+tol) if g['available'] else (-unavailable, unavailable)
    for k, b in enumerate(branches):
        rating = F(b['thermal_limit'])*(F('1.1') if emergency else 1)+tol
        for key in ('pf', 'pt'):
            bounds[mapping[key][k]-1] = (-rating, rating)
        bounds[mapping['loss'][k]-1] = (F(0), 2*rating+tol)
    # Keep the redundant total-loss bound conservative in the expanded model.
    bounds[proof['objective_index']-1] = (F(0), sum(bounds[i-1][1] for i in mapping['loss'])+1)
    for i in range(2, start_bus):
        a, b = rows[i]
        rows[i] = a, b+tol
    loads = {bus: sum((F(l['p']*factor) for l in source['loads'] if l['bus_id'] == bus), F(0)) for bus in buses}
    for k, bus in enumerate(buses):
        i = start_bus+2*k
        rows[i] = rows[i][0], loads[bus]+tol
        rows[i+1] = rows[i+1][0], -loads[bus]+tol
    branch_index = {b['id']: k for k, b in enumerate(branches)}
    for k, support in enumerate(proof['supports']):
        b = branches[branch_index[support['branch']]]
        side = support['side']
        voltage = F(buses[b['from_bus'] if side == 1 else b['to_bus']]['v_max'])+(F('.05') if emergency else 0)+tol
        tap = F(taps[b['id']]['lower'])-tol if b['id'] in taps else F(b['tap_ratio'])
        a = F(b['resistance'])*(tap*tap if side == 1 else 1)/(voltage*voltage)
        p0 = F(support['point'])
        pvar = mapping['pf' if side == 1 else 'pt'][branch_index[b['id']]]
        rows[start_support+k] = ({pvar: 2*a*p0, mapping['loss'][branch_index[b['id']]]: F(-1)}, a*p0*p0)
    weights = {i: F(w) for i, w in proof['multipliers']}
    residual = [F(0)]*len(bounds)
    rhs = F(0)
    for i, w in weights.items():
        assert w >= 0
        a, b = rows[i-1]
        rhs += w*b
        for index, value in a.items():
            residual[index-1] += w*value
    gap = sum(min(a*l, a*u) for a, (l, u) in zip(residual, bounds))-rhs
    relief_reduction = F(0)
    if relief:
        prices = {bus: -(weights.get(start_bus+2*k+1, F(0))-weights.get(start_bus+2*k+2, F(0)))
                  for k, bus in enumerate(buses)}
        available = []
        for l in source['loads']:
            p = F(l['p']*factor)
            if p <= 0:
                continue
            # Maximize reduction of this ray's gap, conservatively allowing every
            # load to contribute DR before allocating the separate shedding cap.
            price = max(F(0), prices[l['bus_id']])
            relief_reduction += price*(F('.01')*p+tol)
            # A looser independent shedding cap only strengthens conservatism.
            available.append((price, F('.1')*p+tol))
        budget = F(10)/F(case['base_power'])+tol
        for price, capacity in sorted(available, reverse=True):
            amount = min(budget, capacity)
            relief_reduction += price*amount
            budget -= amount
        gap -= relief_reduction
    return dict(factor=factor, emergency=emergency, relief=relief,
                acceptance_tolerance_robust=tolerant, exact_gap=str(gap),
                certified_infeasible=gap > 0, numeric_gap=float(gap),
                relief_ray_reduction=float(relief_reduction))


if __name__ == '__main__':
    # The original replay is an internal consistency check before extrapolation.
    original = json.loads((BASE/'active_loss_diagnostic/result.json').read_text())
    original_audit = json.loads((BASE/'active_loss_diagnostic/independent_audit.json').read_text())
    assert original_audit['verified'] and original_audit['acceptance_tolerance_robust']
    assert original_audit['source_sha256'] == hashlib.sha256((BASE/'active_loss_diagnostic/result.json').read_bytes()).hexdigest()
    assert original['source_sha256'] == hashlib.sha256((BASE/'pilot_study.json').read_bytes()).hexdigest()
    assert F(screen(1.1)['exact_gap']) == F(original['strict_gap_exact'])
    factors = [1., 1.025, 1.05, 1.075, 1.09, 1.095, 1.0975, 1.099, 1.0991, 1.099125, 1.0995,
               1.1, 1.1025, 1.103125, 1.105, 1.11, 1.115, 1.117, 1.1171, 1.1175, 1.12, 1.125]
    rows = [screen(f, emergency=e, relief=r, tolerant=True) for e, r in ((False, False), (True, False), (True, True)) for f in factors]
    record = dict(method='Exact rational replay of one existing ray on conservative expanded active-loss relaxations',
                  outage='generator_60', rows=rows,
                  source_certificate_sha256=hashlib.sha256((BASE/'active_loss_diagnostic/result.json').read_bytes()).hexdigest(),
                  source_study_sha256=hashlib.sha256((BASE/'pilot_study.json').read_bytes()).hexdigest(),
                  screen_adapter_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  limitation='Nonpositive gaps are inconclusive. This is not an AC or common-controller feasible boundary. No new optimizer calls.')
    (OUT/'demand_certificate_screen.json').write_text(json.dumps(record, indent=2)+'\n')
    for e, r in ((False, False), (True, False), (True, True)):
        proven = [v['factor'] for v in rows if v['emergency'] == e and v['relief'] == r and v['certified_infeasible']]
        print(dict(emergency=e, relief=r, first_certified_sample=min(proven) if proven else None))
