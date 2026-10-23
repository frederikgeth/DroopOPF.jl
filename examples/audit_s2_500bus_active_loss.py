"""Exact rational replay of the optional active-loss relaxation diagnostic."""
from fractions import Fraction
import copy
import hashlib
import json
from audit_s2_arpae500 import ROOT, OUT, load, data


def F(value=0):
    return Fraction(value.replace('//', '/') if isinstance(value, str) else value)


def verify():
    path = OUT/'active_loss_diagnostic/result.json'
    result = load(path)
    source = OUT/'pilot_study.json'
    assert hashlib.sha256(source.read_bytes()).hexdigest() == result['source_sha256']
    original = data(source)
    expected = copy.deepcopy(original['case'])
    expected['id'] += '/diagnostic'
    for l in expected['loads']:
        l['p'] *= result['factor']
        l['q'] *= result['factor']
    for g in expected['generators']:
        if g['id'] == result['outage']:
            g['available'] = False
    assert expected == result['case']
    assert result['tap_controls'] == original['tap_controls']
    case = result['case']
    assert all(s['conductance'] == 0 for s in case['network']['shunts'])
    assert all(all(g == 0 for g in b['step_conductances']) for b in case['network']['banks'])
    branches = [b for b in case['network']['branches'] if b['available']]
    buses = {b['id']: b for b in case['network']['buses']}
    tap_controls = {t['branch_id']: t for t in result['tap_controls']}
    mapping = result['variable_map']
    ng, nb = len(case['generators']), len(branches)
    assert mapping == dict(pg=list(range(1, ng+1)), pf=list(range(ng+1, ng+nb+1)),
                           pt=list(range(ng+nb+1, ng+2*nb+1)), loss=list(range(ng+2*nb+1, ng+3*nb+1)))
    z = ng+3*nb+1
    assert result['objective_index'] == z
    bounds = [(F(g['p_min']), F(g['p_max'])) if g['available'] else (F(0), F(0)) for g in case['generators']]
    bounds += [(-F(b['thermal_limit']), F(b['thermal_limit'])) for b in branches]*2
    bounds += [(F(0), 2*F(b['thermal_limit'])) for b in branches]
    # Julia records the Float64 sum used to create this deliberately loose bound.
    actual = [(F(l), F(u)) for l, u in result['variable_bounds']]
    assert actual[:-1] == bounds
    assert actual[-1][0] == 0 and actual[-1][1] >= sum(2*F(b['thermal_limit']) for b in branches)
    rows = []

    def equality(coeff, rhs=F(0)):
        rows.append((coeff, rhs))
        rows.append(({i: -a for i, a in coeff.items()}, -rhs))

    equality({z: F(1)} | {i: F(-1) for i in mapping['loss']})
    for k, b in enumerate(branches):
        equality({mapping['loss'][k]: F(1), mapping['pf'][k]: F(-1), mapping['pt'][k]: F(-1)})
    for bus in case['network']['buses']:
        coeff = {mapping['pg'][i]: F(1) for i, g in enumerate(case['generators']) if g['bus_id'] == bus['id']}
        coeff.update({mapping['pf'][k]: F(-1) for k, b in enumerate(branches) if b['from_bus'] == bus['id']})
        coeff.update({mapping['pt'][k]: F(-1) for k, b in enumerate(branches) if b['to_bus'] == bus['id']})
        demand = sum((F(l['p']) for l in case['loads'] if l['bus_id'] == bus['id']), F(0))
        equality(coeff, demand)
    branch_indices = {b['id']: k for k, b in enumerate(branches)}
    for support in result['supports']:
        k = branch_indices[support['branch']]
        b = branches[k]
        assert b['resistance'] >= 0
        side = support['side']
        assert side in (1, 2)
        tau_min = tap_controls[b['id']]['lower'] if b['id'] in tap_controls else b['tap_ratio']
        bus = buses[b['from_bus'] if side == 1 else b['to_bus']]
        a = F(b['resistance'])*(F(tau_min)**2 if side == 1 else 1)/F(bus['v_max'])**2
        assert F(support['coefficient']) == a
        p0 = F(support['point'])
        pvar = mapping['pf' if side == 1 else 'pt'][k]
        rows.append(({pvar: 2*a*p0, mapping['loss'][k]: F(-1)}, a*p0*p0))
    stored = [({int(i): F(a) for i, a in row['coefficients'].items()}, F(row['rhs'])) for row in result['rows']]
    assert stored == rows
    residual = [F(0)]*len(actual)
    rhs = F(0)
    infeasible = result['strict_gap_exact'] is not None
    if not infeasible:
        residual[z-1] = F(1)
    for index, value in result['multipliers']:
        multiplier = F(value)
        assert multiplier >= 0
        coeff, bound = rows[index-1]
        rhs += multiplier*bound
        for i, a in coeff.items():
            residual[i-1] += multiplier*a
    margin = sum(min(a*l, a*u) for a, (l, u) in zip(residual, actual))-rhs
    claimed = result['strict_gap_exact'] if infeasible else result['verified_loss_lower_pu']
    assert claimed is not None and margin == F(claimed)
    assert result['certified_infeasible'] == (infeasible and margin > 0)
    record = dict(verified=True, certified_infeasible=result['certified_infeasible'],
                  exact_replayed_value=str(margin), variables=len(actual), rows=len(rows),
                  source_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    if result['certified_infeasible']:
        # Reuse the same nonnegative multipliers on an even larger model that
        # allows the numerical acceptance tolerances. No second solve is needed.
        tol, unavailable, roundoff = F('0.000001'), F('0.00000001'), F('0.000001')
        relaxed_bounds = [(F(g['p_min'])-tol, F(g['p_max'])+tol) if g['available'] else (-unavailable, unavailable)
                          for g in case['generators']]
        relaxed_bounds += [(-F(b['thermal_limit'])-tol, F(b['thermal_limit'])+tol) for b in branches]*2
        relaxed_bounds += [(F(0), 2*(F(b['thermal_limit'])+tol)+roundoff) for b in branches]
        relaxed_bounds.append(actual[-1])
        assert relaxed_bounds[-1][1] >= sum(u for l, u in relaxed_bounds[-nb-1:-1])
        relaxed_rows = copy.deepcopy(rows)
        for i in range(2, 2+2*nb):
            coeff, rhs = relaxed_rows[i]
            relaxed_rows[i] = coeff, rhs+roundoff
        base_rows = 2+2*nb+2*len(case['network']['buses'])
        for i in range(2+2*nb, base_rows):
            coeff, rhs = relaxed_rows[i]
            relaxed_rows[i] = coeff, rhs+tol
        for index, support in enumerate(result['supports']):
            k = branch_indices[support['branch']]
            b = branches[k]
            side = support['side']
            tau = F(tap_controls[b['id']]['lower'])-tol if b['id'] in tap_controls else F(b['tap_ratio'])
            assert tau > 0
            bus = buses[b['from_bus'] if side == 1 else b['to_bus']]
            a = F(b['resistance'])*(tau*tau if side == 1 else 1)/(F(bus['v_max'])+tol)**2
            p0 = F(support['point'])
            pvar = mapping['pf' if side == 1 else 'pt'][k]
            relaxed_rows[base_rows+index] = ({pvar: 2*a*p0, mapping['loss'][k]: F(-1)}, a*p0*p0)
        residual, rhs = [F(0)]*len(actual), F(0)
        for index, value in result['multipliers']:
            multiplier = F(value)
            coeff, bound = relaxed_rows[index-1]
            rhs += multiplier*bound
            for i, a in coeff.items():
                residual[i-1] += multiplier*a
        robust_gap = sum(min(a*l, a*u) for a, (l, u) in zip(residual, relaxed_bounds))-rhs
        record.update(acceptance_tolerance_robust=robust_gap > 0, robust_gap_exact=str(robust_gap),
                      relaxed_power_and_bound_tolerance='1e-6', relaxed_unavailable_pg_tolerance='1e-8',
                      relaxed_branch_loss_identity_tolerance='1e-6')
    if not infeasible:
        record['verified_loss_lower_mw'] = float(margin)*case['base_power']
    (path.parent/'independent_audit.json').write_text(json.dumps(record, indent=2)+'\n')
    print(json.dumps(record))


if __name__ == '__main__':
    verify()
