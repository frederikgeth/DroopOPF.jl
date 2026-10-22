"""Read-only diagnosis of saved CCOpt/105% iterates; no optimizer calls.

Failed iterates identify residuals and candidate constraints, never infeasibility.
Internal relaxed-NLP coordinate indices are deliberately not JuMP variable IDs.
"""
import copy
import hashlib
import json
from pathlib import Path
from s2_followup_physics import check_case

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'artifacts/s2_scopf/ieee500_native'
PREVIOUS = BASE / 'solver_demand_qualification'
OUT = BASE / 'targeted_demand_diagnostics'
HASHES = {}


def read(path, envelope=False):
    HASHES[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    value = json.loads(path.read_text())
    return value['data'] if envelope else value


def state_diagnostics(folder, factor=None, selected=None):
    suffix = '' if factor is None else f'-{factor}'
    study = read(folder / ('input.json' if factor is None else f'optimized{suffix}.json'), True)
    result = read(folder / f'result{suffix}.json', True)
    angles = read(ROOT / 'artifacts/s1_free_droop/500/angle_limits.json')
    events = {'base': dict(branch_ids=[], generator_ids=[])}
    events.update({x['id']: x for x in study['contingencies']})
    rows = []
    for sid, event in events.items():
        if selected and sid not in selected:
            continue
        state = result['states'][sid]
        if state is None:
            rows.append(dict(id=sid, missing=True))
            continue
        case = copy.deepcopy(study['case'])
        for branch in case['network']['branches']:
            if branch['id'] in event['branch_ids']:
                branch['available'] = False
        for generator in case['generators']:
            if generator['id'] in event['generator_ids']:
                generator['available'] = False
        check = check_case(case, state, result['tap_settings'][sid], result['shunt_settings'][sid], angles)
        flows = check.pop('branch_max_terminal_s_pu')
        balances = check.pop('bus_balance')
        droop = check.pop('droop_by_generator')
        scale = case['base_power']
        thermal = [dict(branch=b['id'], kind=b['kind'],
                        margin_mva=scale*(b['thermal_limit']-flows[str(b['id'])]),
                        utilization=flows[str(b['id'])]/b['thermal_limit'])
                   for b in case['network']['branches'] if b['available'] and b['thermal_limit'] > 0]
        voltage = [dict(bus=b['id'], vm=state['vm'][i],
                        margin_pu=min(state['vm'][i]-b['v_min'], b['v_max']-state['vm'][i]))
                   for i, b in enumerate(case['network']['buses'])]
        bounds = {g['id']: [g['p_min'], g['p_max'], g['q_min'], g['q_max']] for g in case['generators']}
        for a in case['attachments']:
            cap = case['controls'][a['control_id']-1]['capability']
            b = bounds[a['generator_id']]
            b[0] = max(b[0], cap['p_min']); b[1] = min(b[1], cap['p_max'])
            b[2] = max(b[2], cap['q_min']); b[3] = min(b[3], cap['q_max'])
        margins = []
        for i, g in enumerate(case['generators']):
            if not g['available']:
                continue
            lo, hi, qlo, qhi = bounds[g['id']]
            margins.append(dict(generator=g['id'], p_upper_margin_mw=(hi-state['pg'][i])*scale,
                                q_margin_mvar=min(state['qg'][i]-qlo, qhi-state['qg'][i])*scale))
        response = None
        if sid != 'base':
            total = sum(study['participation'][str(g['id'])] for g in case['generators'] if g['available'])
            candidates = []
            error = 0.
            for i, g in enumerate(case['generators']):
                if not g['available']:
                    continue
                alpha = study['participation'][str(g['id'])]/total
                if alpha > 0:
                    candidates.append(((bounds[g['id']][1]-result['states']['base']['pg'][i])/alpha, g['id']))
                error = max(error, abs(state['pg'][i]-result['states']['base']['pg'][i]-alpha*result['balancing_power'][sid]))
            upper, limiting = min(candidates)
            response = dict(limiting_generator=limiting,
                            balancing_coordinate_remaining_mw=(upper-result['balancing_power'][sid])*scale,
                            coupling_max_pu=error,
                            scope='At this fixed base dispatch; not a demand margin or global boundary')
        rows.append(dict(id=sid, physical=check, response=response,
                         thermal=sorted(thermal, key=lambda x: x['margin_mva'])[:8],
                         thermal_utilization=sorted(thermal, key=lambda x: x['utilization'], reverse=True)[:8],
                         voltage=sorted(voltage, key=lambda x: x['margin_pu'])[:8],
                         generator_p=sorted(margins, key=lambda x: x['p_upper_margin_mw'])[:8],
                         generator_q=sorted(margins, key=lambda x: x['q_margin_mvar'])[:8],
                         balance_residuals=sorted(balances, key=lambda x: max(abs(x['p_pu']), abs(x['q_pu'])), reverse=True)[:8],
                         droop_residuals=sorted(droop, key=lambda x: x['residual_pu'], reverse=True)[:8]))
    return rows


def main():
    for path in (Path(__file__), ROOT/'examples/s2_followup_physics.py'):
        HASHES[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    ccopt = []
    for path in sorted(PREVIOUS.glob('ccopt-10000*/round-*/attempt-*/summary.json')):
        record = read(path)
        ccopt.append(dict(source=str(path.relative_to(BASE)), status=record['solver_status'],
                          accepted=record['accepted'], feasibility_stage=record.get('feasibility_stage'),
                          free_shared_droop_variables=record.get('free_shared_droop_variables'),
                          variables=record.get('variables'), diagnostics=record.get('ccopt_diagnostics'),
                          stationarity=record.get('relaxed_nlp_stationarity_diagnostic'),
                          complementarity_product_max=record.get('complementarity_product_max')))
    # Include the separately named tight-start attempt if present.
    covered = {x['source'] for x in ccopt}
    for path in sorted(PREVIOUS.rglob('summary.json')):
        if path.parent.name.startswith('attempt-') and '10000' in str(path.relative_to(PREVIOUS)):
            key = str(path.relative_to(BASE))
            if key not in covered:
                record = read(path)
                if record.get('solver') == 'ccopt':
                    ccopt.append(dict(source=key, status=record['solver_status'], accepted=record['accepted'],
                                      feasibility_stage=record.get('feasibility_stage'),
                                      diagnostics=record.get('ccopt_diagnostics'),
                                      stationarity=record.get('relaxed_nlp_stationarity_diagnostic')))
    directory = PREVIOUS / 'ipopt-10500-continuation/round-1'
    states = dict(accepted_master=state_diagnostics(directory/'attempt-1', 1.05,
                  {'base', 'generator_14', 'generator_60'}))
    for event in ('branch_36', 'branch_562'):
        states[event+'_failed_retry'] = state_diagnostics(directory/'demand-1.05'/(event+'-retry'), selected={event})
    payload = dict(optimizer_calls=0, ccopt_nominal=ccopt, normal_105=states,
                   limitations=['Saved failed iterates are diagnostic only, not feasible witnesses or infeasibility certificates.',
                                'CCOpt stationarity metrics refer to the relaxed NLP, not an original MPCC certificate.',
                                'No preserved feasibility-stage primal/dual vector exists for the prior CCOpt objective switch.',
                                'Internal coordinate indices cannot be assigned physical variable names from saved summaries alone.'],
                   source_hashes=HASHES)
    OUT.mkdir(exist_ok=True)
    (OUT/'saved-state-diagnostics.json').write_text(json.dumps(payload, indent=2)+'\n')
    failed36 = states['branch_36_failed_retry'][0]
    failed562 = states['branch_562_failed_retry'][0]
    master = {x['id']: x for x in states['accepted_master']}
    assert all(x['physical']['valid'] for x in master.values())
    assert not failed36['physical']['valid'] and not failed562['physical']['valid']
    assert len(ccopt) == 12 and not any(x['accepted'] for x in ccopt)
    assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest() == digest for p, digest in HASHES.items())
    lines = [
        '# Targeted 500-bus demand diagnosis', '',
        'Saved-state analysis complete; new optimization is awaiting the campaign equipment confirmation. '
        'This analysis makes zero optimizer calls and leaves all historical solver points unchanged.', '',
        '## CCOpt at 100%', '',
        'All 12 saved nominal master attempts remain unqualified. One reached LOCALLY_SOLVED during '
        'constant-objective feasibility, then TIME_LIMIT after switching to loss minimization. '
        'Its final relaxed-NLP dual residual is approximately 856.09, primal residual 0.0006215, '
        'and complementarity product 2.337e-6. This is evidence of convergence loss, not network infeasibility.', '',
        'The feasibility-stage primal and dual vectors were not preserved separately. '
        'Therefore the existing files cannot establish the exact state or multiplier change at the objective switch. '
        'Internal relaxed-NLP residual indices also cannot be reliably mapped to physical variables from the summaries. '
        'A targeted retry should preserve named primal variables, constraint/dual mappings, complementarity pairs '
        'and physical audits before and after each stage. Qualification still requires convergence on the original '
        'loss objective and independent original-network validation.', '',
        '## Original normal-limit 105% design', '',
        'The best selected controller passes 387/389 connected outages. The accepted joint-master base, '
        'G14 and G60 points replay successfully on the full 500-bus network.', '',
        f"At the fixed selected base dispatch, the G14-outage balancing coordinate has only "
        f"{master['generator_14']['response']['balancing_coordinate_remaining_mw']:.6f} MW remaining "
        'before G60 reaches its effective P maximum. The G60-outage coordinate has '
        f"{master['generator_60']['response']['balancing_coordinate_remaining_mw']:.6f} MW remaining "
        'before G14 reaches its effective P maximum. These are pointwise balancing-coordinate margins, '
        'not demand increments or a global infeasibility proof.', '',
        f"The failed B36 retry has maximum nodal balance residual "
        f"{failed36['physical']['power_balance_max_pu']*100:.3f} MW/MVAr equivalent on the 100 MVA base "
        '(the dominant residual is active power at bus 176); branch 309 reaches its rating. '
        'The failed B562 retry has a maximum balance residual of '
        f"{failed562['physical']['power_balance_max_pu']*100:.3f} MW/MVAr equivalent, "
        'with the largest active mismatch at bus 247 and branch 309 approximately '
        f"{-failed562['thermal'][0]['margin_mva']:.3f} MVA above its rating. "
        'These failed iterates suggest constraints to inspect; their residuals are not required relief amounts.', '',
        'The earlier passive-network cut checks found no positive infeasibility certificate. '
        'A stronger necessary-condition analysis must keep the common preventive dispatch and exact outage response '
        'coupled rather than interpreting the two branch-outage failures independently.', '',
        '## Pending optimization sequence', '',
        '1. Instrument and retry CCOpt 100% with the qualified Ipopt controller/start, retaining the original objective for final acceptance.',
        '2. Investigate B36/B562 together with G14/G60 and seek a joint necessary-condition certificate under normal limits.',
        '3. Design 105% and 110% independently under the approved emergency policy, with all 102 droop parameters free and shared across each master.',
        '4. For each accepted controller, check all 389 connected outages on the original network, add unresolved events to the master, and repeat within declared budgets.', '',
        'The original normal-limit 110% certificate does not establish emergency-policy infeasibility. '
        'No shared multi-demand qualification or full N−1 closure is claimed. '
        'Equipment controls, emergency voltage/thermal caps and relief budgets are stated in the pending confirmation.', '',
        'Machine-readable diagnostics and source hashes: saved-state-diagnostics.json.', '']
    (OUT/'PREPARATION.md').write_text('\n'.join(lines))
    print(json.dumps(dict(optimizer_calls=0, nominal_ccopt_models=len(ccopt),
                         ccopt_feasibility_stage_successes=sum(bool((x.get('feasibility_stage') or {}).get('native_success')) for x in ccopt),
                         states={k:[dict(id=x['id'], physical=x.get('physical'), response=x.get('response'),
                                        leading_thermal=x.get('thermal', [])[:2], leading_balance=x.get('balance_residuals', [])[:2])
                                    for x in rows] for k, rows in states.items()}), indent=2))


if __name__ == '__main__':
    main()
