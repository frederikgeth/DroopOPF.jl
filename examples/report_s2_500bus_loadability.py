"""Summarize audited demand continuation without widening qualification claims."""
import json
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from s2_followup_physics import check_case

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT/'artifacts/s2_scopf/ieee500_native'
OUT = BASE/'emergency_loadability'
ASSETS = ROOT/'docs/src/assets/s2_500bus/loadability'
load = lambda p: json.loads(Path(p).read_text())


def report():
    ASSETS.mkdir(parents=True, exist_ok=True)
    rows = []
    for path in sorted(OUT.glob('**/summary.json')):
        raw = load(path)
        if 'final_stage' not in raw:
            continue
        stage = raw['final_stage']
        selection = path.parent/'selected_feasible_stage.json'
        if selection.exists():
            stage = load(selection)['stage']
        ap = path.parent/f'audit-{stage}.json'
        if not ap.exists():
            continue
        audit = load(ap)
        rows.append(dict(name=raw['name'], factors=raw['factors'],
                         outages=raw['outages'], emergency=raw['emergency'], relief=raw['relief'],
                         accepted=audit['accepted'], physical_valid=audit['physical_valid'],
                         native_success=audit['native_success'], final_stage=stage,
                         last_native_stage=raw['final_stage'],last_native_status=raw['stages'][-1]['status'],
                         equilibrium_witness_valid=audit.get('equilibrium_witness_valid',audit['physical_valid']),
                         worst_balance_pu=max(s['power_balance_max_pu'] for s in audit['states']),
                         max_dr_mw=max(s['dr_mw'] for s in audit['states']),
                         max_shedding_mw=max(s['shedding_mw'] for s in audit['states']),
                         max_voltage_departure_pu=max((v['violation_pu'] for s in audit['states'] for v in s['normal_voltage_departures']), default=0.),
                         max_thermal_ratio=max(s['max_normal_loading_ratio'] for s in audit['states']),
                         stage_statuses=[dict(stage=s['stage'], status=s['status']) for s in raw['stages']],
                         path=str(path.parent.relative_to(ROOT))))
    screen = load(OUT/'demand_certificate_screen.json')
    bounds = []
    for emergency, relief, label in ((False, False, 'Normal limits'), (True, False, 'Emergency limits, no relief'), (True, True, 'Emergency limits + DR/shedding')):
        proven = [r['factor'] for r in screen['rows'] if r['emergency'] == emergency and r['relief'] == relief and r['certified_infeasible']]
        bounds.append(dict(policy=label, certified_infeasible_sample=min(proven) if proven else None))
    aborted = [load(p) for p in OUT.glob('**/abort.json')]
    coverage_path = OUT/'coverage/compact-five-demand/independent_audit.json'
    coverage = load(coverage_path) if coverage_path.exists() else None
    recovery_path = OUT/'dispatch-recovery/summary.json'
    recovery = load(recovery_path) if recovery_path.exists() else None
    summary = dict(runs=rows, certificate_upper_samples=bounds, externally_aborted_runs=aborted,
                   emergency_connected_coverage=coverage, dispatch_recovery=recovery,
                   new_physical_remedy_investigation=False, full_n1_accepted=False,
                   limitation='Critical-outage continuation and shared master acceptance do not establish exhaustive connected-outage security.')
    (OUT/'RESULTS.json').write_text(json.dumps(summary, indent=2)+'\n')
    fig, axes = plt.subplots(2, 2, figsize=(12, 8), layout='constrained')
    colors = {False: '#1764a0', True: '#c26a12'}
    shared_file = OUT/'decomposition/summary.json'
    shared = load(shared_file) if shared_file.exists() else None
    common_names = {str((OUT/r['path']).relative_to(OUT)) for r in shared['rows'] if r['accepted']} if shared else set()
    for policy in (False, True, 'shared'):
        if policy == 'shared':
            chosen = [r for r in rows if r['accepted'] and r['name'] in common_names]
            color, label = '#207d38', 'One fixed shared controller'
        else:
            chosen = [r for r in rows if r['emergency'] == policy and len(r['factors']) == 1 and r['accepted'] and not '/full-' in r['name'] and not r['name'].startswith(('decomposition/','coverage/','dispatch-recovery/','compact/'))]
            color = colors[policy]
            label = 'Emergency pilot' if policy else 'Normal limits'
        chosen.sort(key=lambda r: r['factors'][0])
        if not chosen:
            continue
        factors = [100*r['factors'][0] for r in chosen]
        axes[0, 0].plot(factors, [r['max_voltage_departure_pu'] for r in chosen], 'o-', color=color, label=label)
        axes[0, 1].plot(factors, [100*r['max_thermal_ratio'] for r in chosen], 'o-', color=color, label=label)
        axes[1, 0].plot(factors, [r['max_dr_mw'] for r in chosen], 'o-', color=color, label=label+' DR')
        axes[1, 0].plot(factors, [r['max_shedding_mw'] for r in chosen], 's--', color=color, label=label+' shedding')
        axes[1, 1].semilogy(factors, [max(r['worst_balance_pu'], 1e-14) for r in chosen], 'o-', color=color, label=label)
    axes[0, 0].axhline(.05, color='gray', ls='--', label='Emergency cap')
    axes[0, 1].axhline(110, color='gray', ls='--', label='Emergency cap')
    axes[0, 1].axhline(100, color='gray', ls=':', label='Normal cap')
    axes[1, 0].axhline(10, color='gray', ls='--', label='Shedding cap')
    axes[1, 1].axhline(1e-6, color='gray', ls='--', label='Power-balance gate')
    for ax, title, ylabel in zip(axes.flat,
        ['Largest voltage departure from normal bounds', 'Largest branch/transformer loading',
         'Largest load relief in any studied state', 'Independent AC power-balance replay'],
        ['pu', '% of Rate A', 'MW', 'pu']):
        ax.set(title=title, xlabel='Demand (% of nominal)', ylabel=ylabel)
        ax.grid(alpha=.25);ax.legend(fontsize=7)
    axes[0, 0].set_ylim(bottom=0.)
    axes[1, 0].set_ylim(bottom=0.)
    fig.suptitle('500-bus critical-outage demand continuation — accepted points only\nThree outages; no exhaustive-security claim', fontsize=12)
    for ext in ('png', 'pdf'):
        fig.savefig(ASSETS/f'continuation.{ext}', dpi=170)
    plt.close(fig)
    # Separate security coverage from critical-outage continuation.
    fig, axes = plt.subplots(1, 3, figsize=(13, 4), layout='constrained')
    if coverage:
        cc=sorted(coverage['factors'], key=lambda r:r['factor'])
        xx=[100*r['factor'] for r in cc]
        passed=[r['evaluated']-len(r['failed']) for r in cc]
        failed=[len(r['failed']) for r in cc]
        axes[0].bar(xx,passed,width=2,color='#207d38',label='Accepted')
        axes[0].bar(xx,failed,bottom=passed,width=2,color='#b94137',label='Failed local check')
        axes[0].bar(xx,[389-r['evaluated'] for r in cc],bottom=[r['evaluated'] for r in cc],width=2,color='#d1d4d6',label='Unchecked')
        axes[0].set(ylim=(0,410),ylabel='Connected outages',title='Fixed-plan emergency coverage')
        axes[0].legend(fontsize=7)
    ib=load(OUT/'island_relief_budget.json')['by_demand']
    xx=[100*r['factor'] for r in ib]
    axes[1].plot(xx,[r['exceeding_10mw_total_shedding_even_without_fraction_cap'] for r in ib],'o-',color='#b94137')
    axes[1].set(ylabel='Islanding outages',title='Exceeding 10 MW after full 1% DR')
    axes[2].plot(xx,[r['largest_required_shedding_mw'] for r in ib],'o-',color='#b94137',label='Worst necessary shedding')
    axes[2].axhline(10,color='gray',ls='--',label='Confirmed budget')
    axes[2].set(ylabel='MW',title='Island cut-balance lower bound')
    axes[2].legend(fontsize=7)
    for ax in axes:
        ax.set_xlabel('Demand (% of nominal)');ax.grid(alpha=.2)
    for ext in ('png','pdf'):
        fig.savefig(ASSETS/f'coverage-islands.{ext}',dpi=170)
    plt.close(fig)
    lines = ['# 500-bus loadability and emergency-operation follow-up', '',
        'This follow-up changes operating assumptions, not physical equipment. Historical normal-limit certificates and nominal qualification remain valid in their original scopes.', '',
        '## Confirmed policy', '',
        'All 131 transformer taps remain corrective at 0.95–1.05. All 11 shunt banks remain continuous and corrective at the previously confirmed individual bounds, with no additional movement budget. The 51 droop slopes and 51 reference voltages are shared across demand/outage states within each master.', '',
        'Base states retain normal voltage/Rate A limits and full demand. N−1 states may use voltage bounds expanded by 0.05 pu at each end and 110% Rate A thermal caps on both lines and transformers. Source Rate C equals Rate A on all 593 online devices; the 110% cap is an explicitly confirmed study assumption.', '',
        'DR is limited to 1% of each positive active load, followed by up to 10 MW total involuntary shedding per contingency. Combined relief is limited to 10% of each participating load. Reactive demand is reduced proportionally. No artificial active/reactive injection may substitute for served demand in an accepted result.', '',
        'Phase I minimizes signed artificial power residuals. Subsequent stages fix them to zero, then locally minimize shedding, DR, normalized normal-limit departures, and base losses, retaining each earlier optimum within the declared tolerance. This is local NLP optimisation; it is not a proof of globally minimum relief.', '',
        '## Necessary-condition upper bounds', '',
        'The existing nonnegative certificate ray is replayed using exact rational arithmetic on conservative expanded active-flow/loss relaxations. Positive gaps prove infeasibility; nonpositive gaps are inconclusive.', '',
        '| Policy | First sampled demand certified infeasible for G60 outage |', '| --- | --- |']
    for b in bounds:
        value = f"{100*b['certified_infeasible_sample']:.4f}%" if b['certified_infeasible_sample'] else 'No positive gap on sampled demands'
        lines.append(f"| {b['policy']} | {value} |")
    lines += ['', 'These are upper samples, not feasible boundaries. Certificate gaps are ray-normalized and have no MW interpretation.', '',
        '## Boundary and bottleneck interpretation', '',
        'The independently qualified lower operating point remains 100% demand for all 389 connected outages. At normal limits, 109% passes the three critical outages but only 386/389 connected checks; lines 21 and 36 and transformer 562 fail the bounded local checks. Therefore 109% is not a security-qualified lower boundary. Local failures and positive Phase-I residuals are inconclusive about global infeasibility.', '',
        'With emergency limits, one identical 110%-designed controller passes the three critical outages (line 219, G14 and G60) at all five training demands and four intermediate demands. At 110%, the accepted DR stage uses at most 17.465465 MW DR and exactly zero shedding. Lower-demand compact hard models require zero relief through 105%; 107.5% uses about 0.000058 MW DR. This is decomposed feasibility evidence, not a converged joint multi-demand loss optimum. A later emergency-penalty stage timed out, so minimum emergency use is not established.', '',
        'The normal-limit certificate is driven by surviving active-generation capacity and unavoidable resistive losses. High-weight generation bounds include G14, G32, G89, G37 and G42; major loss-tangent participants include branches 436, 309, 379, 5, 7, 562, 21, 151, 36 and 33. These are certificate participants, not a unique bottleneck ranking or a remedy recommendation. Bus 478 connects through 220-MVA branches 309 and 422; their loading and local voltage departures identify an operating stress corridor in the accepted emergency point.', '',
        'A stronger joint active-flow relaxation additionally couples preventive Pg and the existing Pmax-weighted outage response across the base, G14, G60 and line-36 outages. Its independently reconstructed bounds include conservative series-loss ceilings. Fifty LP rounds produced no positive certificate at 110%; that result is inconclusive about AC feasibility. The historical nominal AC states embed in the same relaxation without violating its rows. Its numerical point is used only for initialization.', '',
        '## Exhaustive connected-outage checks', '']
    if coverage:
        lines += ['| Demand | Evaluated | Passed | Failed local checks |', '| --- | ---: | ---: | --- |']
        for r in sorted(coverage['factors'],key=lambda r:r['factor']):
            lines.append(f"| {100*r['factor']:g}% | {r['evaluated']}/389 | {r['evaluated']-len(r['failed'])} | {', '.join(r['failed']) or 'None among evaluated'} |")
    lines += ['', 'Checkpointed coverage is retained. Unchecked events are unqualified. A bounded contingency-addition recovery frees preventive Pg while keeping the same droop controller and adds line 36 and transformer 562 to the three critical outages; its separate summary retains each native result. No failed fixed-dispatch solve is promoted to a network-wide infeasibility claim.', '']
    if recovery:
        for r in recovery['rows']:
            lines.append(f"- Dispatch recovery at {100*r['factor']:g}%: accepted physical point = {r['accepted']}; {r['path']}.")
        lines += ['', 'At 105%, the accepted feasibility point has zero shedding, but the subsequent DR minimization timed out; minimum DR is not established. At 110%, both the MadNLP zero-shedding attempt and coordinated-start Ipopt last-resort attempt timed out and failed physical acceptance. The recovered 105% base has not been exhaustively requalified.']
    lines += ['', '![Critical-outage continuation](../../../../docs/src/assets/s2_500bus/loadability/continuation.png)', '',
              '![Connected coverage and island budget](../../../../docs/src/assets/s2_500bus/loadability/coverage-islands.png)']
    lines += ['',
        '## Audited optimisation results', '',
        '| Run | Demand factors | Accepted | Max DR (MW) | Max shedding (MW) | Final stage/status |',
        '| --- | --- | --- | --- | --- | --- |']
    for r in (r for r in rows if not r['name'].startswith('coverage/')):
        status = next(s['status'] for s in r['stage_statuses'] if s['stage'] == r['final_stage'])
        lines.append(f"| {r['name']} | {', '.join(str(f) for f in r['factors'])} | {r['accepted']} | {r['max_dr_mw']:.4f} | {r['max_shedding_mw']:.4f} | {r['final_stage']}/{status} |")
    lines += ['', 'Native convergence, original AC balance, exact droop, active/reactive generation limits, response coupling, equipment settings, angle limits, emergency limits and load-relief budgets are independently checked. A rejected iterate may satisfy some constraints without qualifying the run.', '',
        'Continuation of separate single-demand designs does not establish one shared design across the whole range. Shared-master runs explicitly couple the same 102 parameters across their listed demands. Only evaluated outages are covered; unchecked connected outages and islanding events are not classified safe.', '',
        'The 171 loaded islands without generation cannot retain 90% of their load under the combined 10% per-load relief cap, regardless of the 10 MW system budget. Thus this policy still does not qualify full N−1.', '',
        'Even ignoring the per-load fraction cap, at nominal demand 85 islanding outages need more than 10 MW shedding after full 1% DR (worst 94.957830 MW); at 110%, 87 do (worst 104.453613 MW). These cut-balance bounds are independent of local solver convergence.', '',
        'No generation additions, reinforcement, or other physical remedies were investigated. Overall 500-bus S2 remains open unless exhaustive qualification is separately documented.', '']
    if (BASE/'network_reduction/REPORT.md').exists():
        lines += ['', 'Subsequent rating-preserving electrical network-reduction numerical tests and full-network reconstruction checks are recorded in [../network_reduction/REPORT.md](../network_reduction/REPORT.md). Their accepted scope is reported separately.', '']
    (OUT/'REPORT.md').write_text('\n'.join(lines))
    print(json.dumps(dict(audited_runs=len(rows), accepted=sum(r['accepted'] for r in rows), figure=str(ASSETS/'continuation.png'))))


if __name__ == '__main__':
    report()
