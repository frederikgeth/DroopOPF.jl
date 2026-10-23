"""Attribute the saved exact certificate; no optimisation or bound changes.

All scores depend on the particular ray and its normalization. They identify
constraints participating in this proof, not unique causes or MW remedies.
"""
from collections import defaultdict
from fractions import Fraction
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'artifacts/s2_scopf/ieee500_native'
OUT = BASE / 'emergency_loadability'


def rational(x):
    return Fraction(x.replace('//', '/') if isinstance(x, str) else x)


def analyse():
    path = BASE / 'active_loss_diagnostic/result.json'
    proof = json.loads(path.read_text())
    audit = json.loads((path.parent / 'independent_audit.json').read_text())
    assert audit['verified'] and audit['certified_infeasible']
    assert audit['source_sha256'] == hashlib.sha256(path.read_bytes()).hexdigest()
    case = proof['case']
    branches = [b for b in case['network']['branches'] if b['available']]
    buses = case['network']['buses']
    weights = {i: rational(v) for i, v in proof['multipliers']}
    residual = defaultdict(Fraction)
    contributions = defaultdict(Fraction)
    nbranch = len(branches)
    start_bus = 2 + 2*nbranch
    start_support = start_bus + 2*len(buses)
    support_scores = defaultdict(Fraction)
    demand_scores = []
    for index, row in enumerate(proof['rows']):
        w = weights.get(index+1, Fraction(0))
        for variable, a in row['coefficients'].items():
            residual[int(variable)] += w*rational(a)
        score = -w*rational(row['rhs'])
        group = ('total_loss_identity' if index < 2 else
                 'branch_loss_identities' if index < start_bus else
                 'nodal_active_balance' if index < start_support else
                 'resistive_loss_tangents')
        contributions[group] += score
        if index >= start_support:
            support = proof['supports'][index-start_support]
            support_scores[support['branch']] += abs(score)
    for k, bus in enumerate(buses):
        i = start_bus+2*k
        net = weights.get(i+1, Fraction(0))-weights.get(i+2, Fraction(0))
        rhs = rational(proof['rows'][i]['rhs'])
        demand_scores.append(dict(bus=bus['id'], multiplier=float(net),
                                  signed_gap_contribution=float(-net*rhs),
                                  load_mw=float(rhs)*case['base_power']))
    mapping = proof['variable_map']
    bound_scores = {}
    for group, indices in mapping.items():
        rows = []
        for k, i in enumerate(indices):
            lo, hi = map(rational, proof['variable_bounds'][i-1])
            a = residual[i]
            score = min(a*lo, a*hi)
            contributions['bound_'+group] += score
            item = case['generators'][k] if group == 'pg' else branches[k]
            rows.append(dict(id=item['id'], coefficient=float(a),
                             active_bound='lower' if a > 0 else 'upper' if a < 0 else 'none',
                             signed_gap_contribution=float(score),
                             available=item['available']))
        bound_scores[group] = sorted(rows, key=lambda r: abs(r['signed_gap_contribution']), reverse=True)
    z = proof['objective_index']
    lo, hi = map(rational, proof['variable_bounds'][z-1])
    contributions['bound_total_loss'] += min(residual[z]*lo, residual[z]*hi)
    gap = sum(contributions.values(), Fraction(0))
    assert gap == rational(proof['strict_gap_exact']) and gap > 0
    generator_capacity = sum(g['p_max'] for g in case['generators'] if g['available'])*case['base_power']
    load = sum(l['p'] for l in case['loads'])*case['base_power']
    report = dict(
        scope='Read-only attribution of the existing normal-limit 110%/G60 certificate',
        certificate_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        exact_gap_reconstructed=str(gap),
        signed_gap_contributions={k: float(v) for k, v in contributions.items()},
        bound_participants=bound_scores,
        nodal_balance_participants=sorted(demand_scores, key=lambda r: abs(r['signed_gap_contribution']), reverse=True),
        loss_tangent_participants=[dict(branch=i, absolute_rhs_weight=float(v))
            for i, v in sorted(support_scores.items(), key=lambda kv: kv[1], reverse=True)],
        remaining_generation_capacity_mw=generator_capacity, demand_mw=load,
        capacity_available_for_losses_mw=generator_capacity-load,
        lossless_capacity_demand_factor_upper_bound=generator_capacity/(load/proof['factor']),
        new_optimisation_runs=0,
        limitations=[
            'Ray scores and its gap are not MW deficits, unique causes, or remedy sizes.',
            'Certificate uses terminal active-flow bounds, not complete AC apparent-flow constraints.',
            'Relaxation-feasible points never establish an AC or shared-controller demand boundary.',
            'Original certificate does not establish infeasibility under the proposed emergency/relief policy.',
            'No equipment upgrades or other physical remedies investigated.'])
    OUT.mkdir(exist_ok=True)
    (OUT/'bottleneck_attribution.json').write_text(json.dumps(report, indent=2)+'\n')
    inventory = json.loads((ROOT/'artifacts/s2_scopf/ieee500_preparation/island_inventory.json').read_text())
    source_case = json.loads((BASE/'pilot_study.json').read_text())['data']['case']
    islands = []
    for item in inventory['islands']:
        vertices = set(item['small_component'])
        cut = [b['id'] for b in source_case['network']['branches'] if b['available'] and ((b['from_bus'] in vertices) != (b['to_bus'] in vertices))]
        assert cut == [item['branch']]
        generation = [g for g in source_case['generators'] if g['available'] and g['bus_id'] in vertices]
        demand = sum(l['p'] for l in source_case['loads'] if l['bus_id'] in vertices)*source_case['base_power']
        if not generation and demand > 0:
            islands.append(dict(branch=item['branch'],bus=sorted(vertices),nominal_load_mw=demand))
    budget_rows = []
    for factor in (.9,.95,1.,1.05,1.1):
        required = [dict(**item,demand_factor=factor,minimum_shedding_after_max_dr_mw=.99*factor*item['nominal_load_mw']) for item in islands]
        budget_rows.append(dict(factor=factor,loaded_islands_without_generation=len(required),
            exceeding_10mw_total_shedding_even_without_fraction_cap=sum(r['minimum_shedding_after_max_dr_mw']>10.+1e-6 for r in required),
            largest_required_shedding_mw=max(r['minimum_shedding_after_max_dr_mw'] for r in required)))
    (OUT/'island_relief_budget.json').write_text(json.dumps(dict(islands=islands,by_demand=budget_rows,
        method='Source cut edges and local generation/load replay; no optimisation or proposed remedy',
        limitation='The weaker total-budget test ignores the combined per-load fraction cap. Under the confirmed 10% fraction cap all 171 loaded islands fail.'),indent=2)+'\n')
    by_id = {b['id']: b for b in branches}
    lines = [
        '# 500-bus bottleneck analysis and next-campaign preparation', '',
        'Status: saved-certificate attribution complete. Campaign configuration was subsequently confirmed; current execution results are recorded in REPORT.md and RESULTS.json.', '',
        '## Findings from existing evidence', '',
        f"The exact normal-limit 110%/G60 certificate gap was reconstructed from all row and bound contributions. "
        f"Surviving Pmax is {generator_capacity:.4f} MW, load is {load:.4f} MW, and the capacity allowance for losses is {generator_capacity-load:.4f} MW. "
        'That allowance is not a remedial MW deficit.', '',
        'The lossless active-capacity ceiling for the same outage without load relief is '
        f"{100*report['lossless_capacity_demand_factor_upper_bound']:.4f}% demand. "
        'This is an upper bound, not an achievable AC loadability boundary. The normal-limit 110% case is already certified infeasible.', '',
        'The largest absolute loss-tangent RHS weights in this particular certificate occur on:', '',
        '| Branch | From bus | To bus | Kind |',
        '| --- | --- | --- | --- |']
    for item in report['loss_tangent_participants'][:10]:
        b = by_id[item['branch']]
        lines.append(f"| {b['id']} | {b['from_bus']} | {b['to_bus']} | {b['kind']} |")
    lines += ['',
        'These are proof participants, not a ranking of observed overloads or unique binding AC bottlenecks. '
        'The largest absolute generator bound terms involve G14, G32, G89, G37 and G42; terms also depend on capacity and ray normalization.', '',
        '## Prepared study sequence', '',
        '1. Preserve the original normal-limit baseline and certificate. Report strict and emergency-assisted loadability separately.',
        '2. Use the accepted nominal design as the starting point. Build feasibility-first demand steps with shared droop parameters and corrective equipment. Add failed connected outages to the master and recheck earlier demand points when the shared design changes.',
        '3. Keep generator P/Q limits, outages, angle bounds and equipment bounds hard. Use temporary signed power-balance residuals only in Phase I; require them to vanish before accepting a physical point. They must never be counted as demand response or shedding.',
        '4. Admit bounded emergency voltage and apparent-flow departures only post-contingency, with explicit nonnegative penalties against normal limits. Audit both branch ends, including transformers. Base states retain normal limits and full load.',
        '5. Introduce explicit load variables for demand response, then involuntary shedding, only if needed. Reduce reactive demand with the same fraction. Enforce total and per-load caps without double counting DR and shedding.',
        '6. Use staged priorities: eliminate artificial residuals; minimize involuntary shedding; minimize demand response; minimize normalized emergency departures; finally optimize operating losses. Lock earlier optima within declared numerical tolerances before each later stage.',
        '7. Continue demand upward with smaller steps near failure; retry failures with Phase I and a warm start. Record the highest independently validated demand and unresolved upper region. A local solver failure is not an infeasibility proof, and AC feasibility need not be monotone.',
        '8. Distinguish independently feasible single-demand points from one common droop design feasible at every retained training demand. Full connected security requires all 389 connected outages. Keep islanding events in a separate ledger; do not accept them by silently dropping load or tripping generators.', '',
        'No generation additions, network reinforcement, rating investment, or other physical-remedy studies are included.', '',
        '## Confirmed campaign configuration', '',
        '- All 131 selected taps and 11 continuous shunt banks at the previous individual bounds, corrective per demand/outage, no extra movement budget. All 102 droop slope/reference parameters shared.',
        '- Emergency caps: 110% Rate A for lines and transformers; source voltage intervals expanded by 0.05 pu at each end in N−1 only. These are explicitly confirmed study assumptions, not validated equipment ratings.',
        '- Post-contingency relief: up to 1% DR per load, followed by up to 10 MW total shedding, with a combined 10% per-load cap and proportional Q reduction.', '',
        'This certificate-attribution script performs no new optimisation. The previous normal-limit results remain historical evidence in their original scope.', '']
    (OUT/'PREPARATION.md').write_text('\n'.join(lines))
    print(json.dumps(dict(exact_gap_reconstructed=True,
        capacity_available_for_losses_mw=generator_capacity-load,
        lossless_capacity_demand_factor_upper_bound=report['lossless_capacity_demand_factor_upper_bound'],
        top_loss_tangent_branches=report['loss_tangent_participants'][:10],
        top_generator_bound_participants=bound_scores['pg'][:5],
        signed_gap_contributions=report['signed_gap_contributions']), indent=2))


if __name__ == '__main__':
    analyse()
