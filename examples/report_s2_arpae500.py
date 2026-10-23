"""Build the 500-bus checkpoint report from saved results; never optimizes."""
import json
import copy
import shutil
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from audit_s2_arpae500 import ROOT, OUT, load, data, audit
from s2_followup_physics import check_case
from s2_500bus_reporting import nominal_selection, nominal_envelopes


def report():
    audit()
    figures = OUT/'figures'
    figures.mkdir(exist_ok=True)
    images = []
    original = data(OUT/'pilot_study.json')['case']
    colors = dict(ipopt='#0072b2', madnlp='#d55e00')
    curves = {s: data(OUT/f'pilot-{s}/controller.json')['case']['controls'] for s in colors}
    nominal = nominal_selection()
    nominal_curves = data(OUT/nominal[1]['selected']/'controller.json')['case']['controls'] if nominal else None
    for page in range(3):
        fig, axes = plt.subplots(6, 3, figsize=(12, 16), constrained_layout=True)
        for ax, k in zip(axes.flat, range(page*18, page*18+18)):
            if k >= len(original['controls']):
                ax.axis('off')
                continue
            base = original['controls'][k]
            ref = base['schedule']['v_ref']
            refs = [ref]+[curves[s][k]['schedule']['v_ref'] for s in colors]
            if nominal_curves:
                refs.append(nominal_curves[k]['schedule']['v_ref'])
            v = np.linspace(min(refs)-.06, max(refs)+.06, 301)
            for label, d, color in [('S1 seed', base, '#555555')]+[(s, curves[s][k], c) for s, c in colors.items()]:
                q = np.clip(d['q_at_deadband']+(np.maximum(d['schedule']['v_db_low']-v, 0)-np.maximum(v-d['schedule']['v_db_high'], 0))/d['slope'], d['capability']['q_min'], d['capability']['q_max'])
                ax.plot(v, q*original['base_power'], label=label, color=color, lw=1.4)
            if nominal_curves:
                d = nominal_curves[k]
                q = np.clip(d['q_at_deadband']+(np.maximum(d['schedule']['v_db_low']-v, 0)-np.maximum(v-d['schedule']['v_db_high'], 0))/d['slope'], d['capability']['q_min'], d['capability']['q_max'])
                ax.plot(v, q*original['base_power'], label='MadNLP 389 outages', color='#7b3294', lw=1.4)
            a = next(a for a in original['attachments'] if a['control_id'] == k+1)
            ax.set_title(f"G{a['generator_id']} / bus {a['location']['bus_id']}", fontsize=9)
            ax.set_xlabel('Voltage (pu)', fontsize=8)
            ax.set_ylabel('Q (MVAr)', fontsize=8)
            ax.grid(alpha=.2)
        axes.flat[0].legend(fontsize=8)
        fig.suptitle('500-bus droop designs: S1 seed, three-outage pilots and nominal qualification')
        name = f'pilot-droop-{page+1}.png'
        fig.savefig(figures/name, dpi=130)
        plt.close(fig)
        images.append(name)
    for solver in colors:
        r = data(OUT/f'pilot-{solver}/result-1.0.json')
        study = data(OUT/f'pilot-{solver}/optimized-1.0.json')
        fig, axes = plt.subplots(3, 1, figsize=(13, 10), constrained_layout=True)
        ids = list(r['states'])
        taps = sorted(map(int, r['tap_settings']['base']))
        banks = sorted(map(int, r['shunt_settings']['base']))
        source_seed = load(ROOT/'artifacts/s1_free_droop/500/attempts/design-droop_tap_shunt-1.0-cost-ccopt.json')
        axes[0].plot(taps, [source_seed['taps'][str(i)] for i in taps], color='#666666', ls=':', lw=1, label='S1 seed')
        axes[1].plot(banks, [source_seed['susceptances'][str(i)] for i in banks], color='#666666', ls=':', lw=1, label='S1 seed')
        for sid in ids:
            axes[0].plot(taps, [r['tap_settings'][sid].get(str(i), np.nan) for i in taps], label=sid, lw=1)
            axes[1].plot(banks, [r['shunt_settings'][sid][str(i)] for i in banks], marker='.', label=sid)
            axes[2].plot([b['id'] for b in original['network']['buses']], r['states'][sid]['vm'], lw=.7, label=sid)
        axes[0].axhline(.95, color='black', ls='--')
        axes[0].axhline(1.05, color='black', ls='--')
        bounds = {s['bank_id']: s for s in study['shunt_controls']}
        axes[1].plot(banks, [bounds[i]['upper'] for i in banks], 'k--', label='upper bound')
        axes[1].axhline(0, color='black', ls='--')
        buses = original['network']['buses']
        for field in ['v_min', 'v_max']:
            axes[2].plot([b['id'] for b in buses], [b[field] for b in buses], 'k--', lw=.7)
        for ax, xlabel, ylabel in zip(axes, ['Transformer ID', 'Bank ID', 'Bus ID'], ['Tap ratio', 'Susceptance (pu)', 'Voltage (pu)']):
            ax.set_xlabel(xlabel)
            ax.set_ylabel(ylabel)
            ax.grid(alpha=.2)
        axes[0].legend(ncol=4, fontsize=8)
        fig.suptitle(f'500-bus {solver}: base and three pilot contingencies only')
        name = f'pilot-equipment-voltage-{solver}.png'
        fig.savefig(figures/name, dpi=150)
        plt.close(fig)
        images.append(name)
        fig, axes = plt.subplots(3, 1, figsize=(13, 10), constrained_layout=True)
        generators = [(i, g) for i, g in enumerate(original['generators']) if g['available']]
        gids = [g['id'] for i, g in generators]
        scale = original['base_power']
        angles = load(ROOT/'artifacts/s1_free_droop/500/angle_limits.json')
        for sid in ids:
            for ax, field in zip(axes[:2], ['pg', 'qg']):
                ax.plot(gids, [r['states'][sid][field][i]*scale for i, g in generators], marker='.', lw=.8, label=sid)
            case = copy.deepcopy(study['case'])
            if sid != 'base':
                event = next(e for e in study['contingencies'] if e['id'] == sid)
                for b in case['network']['branches']:
                    if b['id'] in event['branch_ids']:
                        b['available'] = False
                for g in case['generators']:
                    if g['id'] in event['generator_ids']:
                        g['available'] = False
            ck = check_case(case, r['states'][sid], r['tap_settings'][sid], r['shunt_settings'][sid], angles)
            branches = [b for b in case['network']['branches'] if b['available']]
            axes[2].plot([b['id'] for b in branches], [100*ck['branch_max_terminal_s_pu'][str(b['id'])]/b['thermal_limit'] for b in branches], lw=.8, label=sid)
        for ax, prefix, ylabel in zip(axes[:2], ['p', 'q'], ['P generation (MW)', 'Q generation (MVAr)']):
            ax.plot(gids, [g[f'{prefix}_min']*scale for i, g in generators], 'k--', lw=.8)
            ax.plot(gids, [g[f'{prefix}_max']*scale for i, g in generators], 'k--', lw=.8)
            ax.set_xlabel('Generator ID')
            ax.set_ylabel(ylabel)
        axes[2].axhline(100, color='black', ls='--', label='Rate-A limit')
        axes[2].set_xlabel('Branch ID')
        axes[2].set_ylabel('Max terminal |S| / Rate A (%)')
        for ax in axes:
            ax.grid(alpha=.2)
        axes[0].legend(ncol=4, fontsize=8)
        fig.suptitle(f'500-bus {solver}: pilot generation and branch bounds (tripped generators = zero)')
        name = f'pilot-generation-flow-{solver}.png'
        fig.savefig(figures/name, dpi=150)
        plt.close(fig)
        images.append(name)
    nominal_images = nominal_envelopes(figures)
    images.extend(nominal_images)
    rows = []
    for p in sorted(OUT.rglob('summary.json')):
        r = load(p)
        if 'solver' not in r or 'solver_status' not in r:
            continue
        rows.append(f"| `{p.parent.relative_to(OUT)}` | {r['solver']} | {r['solver_status']} | {'Pass' if r['accepted'] else 'Rejected'} | {r.get('nominal_loss_mw', float('nan')):.9f} |")
    replayed = {r['directory']: r for r in load(OUT/'independent_audit.json')['attempts']}
    recovery_rows = []
    recovery_paths = sorted((OUT/'recovery').glob('*/summary.json'))+sorted((OUT/'linear_recovery').glob('*/summary.json'))
    for p in recovery_paths:
        r = load(p)
        d = r['ccopt_diagnostics']
        physical = replayed[str(p.parent.relative_to(OUT))]['physical_valid']
        recovery_rows.append(f"| {p.parent.name} | {d['inner_iterations']} | {d['primal_feasibility']:.3g} | {d['dual_feasibility']:.3g} | {d['complementarity_feasibility']:.3g} | {'Pass' if physical else 'Fail'} |")
    qualifications = []
    for p in sorted((OUT/'qualification').glob('summary-*.json')):
        r = load(p)
        last = r['rounds'][-1]
        text = '; '.join(f"demand {s['factor']}: {s['evaluated']}/389 evaluated, {len(s['failed'])} failed" for s in last['scans']) or 'master design did not pass'
        qualifications.append(f"- `{p.stem}`: {'qualified' if r['accepted'] else 'not qualified'}, {len(r['rounds'])} round(s); {text}.")
    certificates = load(OUT/'fixed_base_active_reserve_certificates.json')['certificates']
    reserve_note = f"The pilot Ipopt base dispatch fails a necessary proportional-response reserve test for {len(certificates)} generator outages. For loss of G60, G14 reaches Pmax before total supply can meet demand; the lossless minimum shortfall is 700.721 MW. This certificate concerns that fixed pilot dispatch, not every possible preventive design. Failed cases therefore require a redesigned base dispatch. Detailed certificates are retained in `fixed_base_active_reserve_certificates.json`."
    body = '''# S2 500-bus qualification checkpoint

The 500-bus study is open. Ipopt and MadNLP passed the nominal pilot (base plus three outages); this is not exhaustive connected-outage qualification. Full N-1 security is impossible with all source loads served because 171 outages isolate a loaded bus without an online generator. S1 and the declared sampled 14-bus S2 scope remain closed.

## Confirmed contract

All 131 transformer taps (469–599) are free within 0.95–1.05. All 11 available banks use continuous susceptance: B1 0–0.6, B2 0–1.0, B3/B4/B6/B9/B12 0–0.5, B5/B16 0–0.4, B13 0–0.3 and B14 0–0.8 pu. Equipment is corrective per demand and outage, with no extra movement budgets. All 51 droop slopes and references are shared across design states: 2–8% full Q span, calibration reference ±0.02 pu, zero deadband and zero Q reference. Source voltage, angle and Rate-A limits remain in force; active response uses within-demand Pmax weights.

The source has 593 online branches and 51 online generators. There are 389 connected outages (338 branches and 51 generators), plus 255 branch outages that isolate one bus: 171 loaded without generation, 45 unloaded with generation and 39 unloaded empty. No load shedding or automatic generator trip is assumed. The loaded-island failures follow directly from active balance and nonnegative conductance/resistance, independently of solver behavior.

## Numerical evidence

The nominal pilot includes branch 299, transformer branch 489 and generator 14, selected by saved-reference loading within their families. Native convergence and exact-physics replay are both required. Rejected iterates below remain diagnostic records, not optimal designs. For CCOpt recovery, the actual normalization, initial-barrier and scheduled-relaxation fields identify its configuration; inherited descriptive strategy labels can be stale. Barrier/relaxation fields in inherited smooth-backend records are inapplicable metadata: the adapter sets those options only for CCOpt, while smooth backends use their defaults.

| Attempt | Solver | Native status | Acceptance | Raw base ΣPg−ΣPd (MW) |
|---|---|---|---|---:|
'''+ '\n'.join(rows)+'''

Targeted CCOpt recovery endpoints (dual residuals refer to the final relaxed NLP, not an original-MPCC stationarity certificate):

| Recovery | Inner iterations | Native primal | Native dual | Complementarity | Exact physical replay |
|---|---:|---:|---:|---:|---|
'''+ '\n'.join(recovery_rows)+'''

## Exhaustive connected-outage gate

Contingency scores order the checks only. Each check holds the same preventive base dispatch and base equipment fixed, keeps selected post-contingency taps and shunts corrective, and verifies exact physics. Failed events are added to the shared design master, followed by a complete recheck of all 389 events. Unchecked events are not classified safe. The feasibility checks use the native constant schedule-deviation objective; their objective is not an active-loss score.

'''+ ('\n'.join(qualifications) if qualifications else 'Qualification has not completed.')+'\n\n'+reserve_note+'''

## Pilot figures

These figures show accepted pilot designs only. They do not establish coverage of other outages or demand levels. No accepted CCOpt design is plotted while its native convergence and physical acceptance gates remain unmet.

'''+ '\n\n'.join(f'![{name}](figures/{name})' for name in images)+'''

## Remaining closure gates

An accepted shared design must survive every connected outage at all declared training demands, and frozen-design held-out demands must then pass. Backend comparisons require independently accepted designs. Island handling remains an explicit limitation until a policy is authorized and checked. No release or tag has been published.

Raw evidence is retained under `artifacts/s2_scopf/ieee500_native`, with source hashes, solver contracts, starts, failed iterates, native residuals and independent AC/droop/equipment/response replay in `independent_audit.json`. Reproduce with `python3 examples/audit_s2_arpae500.py` and the Matplotlib reporting environment for `examples/report_s2_arpae500.py`.
'''
    if nominal:
        body = body.replace('The 500-bus study is open. Ipopt and MadNLP passed the nominal pilot (base plus three outages); this is not exhaustive connected-outage qualification.',
            'The 500-bus study remains open. MadNLP has qualified all 389 connected outages at nominal demand with one preventive base dispatch, after reserve-aware recovery. Its accepted base loss is 22.609398136 MW. Independent replay checks all 390 unique selected states and verifies a common base and controller across the 389 separate outage witnesses. Multi-demand and held-out gates remain open. Ipopt and MadNLP also passed the earlier three-outage pilot.')
        body = body.replace('## Pilot figures', '## Accepted designs and operating figures')
        body = body.replace('These figures show accepted pilot designs only. They do not establish coverage of other outages or demand levels.',
            'The final two figures show min–max envelopes across the qualified nominal base and all 389 connected outages. The earlier operating figures retain the three-outage pilot. Purple droop curves show the fully qualified nominal MadNLP design; pilot Ipopt/MadNLP curves solve a smaller security problem and their losses are not comparable as identical models. No multi-demand or held-out coverage is implied.')
    obstruction = OUT/'active_loss_diagnostic/independent_audit.json'
    if obstruction.exists():
        certificate = load(obstruction)
        assert certificate['verified'] and certificate['certified_infeasible'] and certificate['acceptance_tolerance_robust']
        details = '''## Certified obstruction to five-demand qualification

**The required 110% demand / G60 outage is physically infeasible under the confirmed bounds.** This is an independently verified mathematical obstruction, not a conclusion drawn from local solver failure. No droop redesign or active-response rule within these equipment and generation limits can make this case feasible. The five-demand 90/95/100/105/110% target therefore cannot be accepted. Its four held-out checks were not run because the training gate failed.

After the G60 outage, remaining Pmax is 4101.772 MW and load is 4061.9623 MW, leaving 39.8097 MW for losses. A conservative active-flow outer LP cannot satisfy nodal balance, individual Pmax, terminal Rate-A limits and necessary resistive-loss inequalities, even though Q, droop, Kirchhoff voltage constraints, angle constraints and preventive-response coupling are omitted. The model retains only conservative consequences of the free tap bounds and source voltage maxima. All continuous banks have zero conductance, so omitting their reactive behavior enlarges the feasible set.

For each branch, with series loss `L`, terminal active powers `Pf/Pt`, resistance `r`, source-end maximum voltage `Vfmax`, receiving-end maximum `Vtmax`, and minimum allowed tap `taumin`, every AC solution must satisfy:

```text
L = Pf + Pt
L >= r * taumin^2 * Pf^2 / Vfmax^2
L >= r * Pt^2 / Vtmax^2
```

Globally valid tangent planes give a linear outer relaxation. HiGHS found an infeasibility ray after three LP rounds. Independent Python `Fraction` arithmetic reconstructs the source case, all 1,870 variable bounds, all 4,006 rows, every support coefficient and all nonnegative ray multipliers. It includes multiplier-stationarity residuals over finite variable bounds in the proof. The exact Farkas gap is strictly positive. Reusing the same multipliers on a larger relaxation that allows 1e-6 power/bound/branch-loss-identity tolerances and 1e-8 unavailable-generator Pg also leaves a strictly positive exact gap. Thus the obstruction survives the numerical acceptance tolerances. The ray normalization has no MW interpretation.

The 20-state shared-controller MadNLP attempts (461 MUMPS iterations, then 230 UMFPACK iterations; approximately 304/303 seconds) remain rejected numerical records. Neither met physical acceptance. The certificate supplies the stronger final classification for the required high-demand case. CCOpt's pilot also remains unqualified after six total attempts; no rejected iterate is plotted as an optimal design.

Evidence: `active_loss_diagnostic/result.json`, its `independent_audit.json` and `run_metadata.json`. Reproduce exact replay with `python3 examples/audit_s2_500bus_active_loss.py`. The optional solver environment is recorded in the run metadata; no repository dependency was added. Initial diagnostic implementation errors are retained separately and produced no accepted certificate.

'''
        body = body.replace('## Accepted designs and operating figures', details+'## Accepted designs and operating figures')
        body = body.replace('## Pilot figures', details+'## Pilot figures')
        body = body.replace('Multi-demand and held-out gates remain open.',
            'The five-demand target is certified infeasible because the required 110% G60 outage cannot satisfy a conservative active-loss relaxation; held-out checks were deferred.')
        body = body.replace('## Remaining closure gates', '## Closeout decision')
        body = body.replace('An accepted shared design must survive every connected outage at all declared training demands, and frozen-design held-out demands must then pass. Backend comparisons require independently accepted designs. Island handling remains an explicit limitation until a policy is authorized and checked. No release or tag has been published.',
            'The nominal 389-connected-outage gate is closed as qualified for the accepted MadNLP design. The bounded five-demand investigation is complete with a certified failure at 110%/G60. Overall 500-bus S2 remains unqualified and open: the requested five-demand target cannot pass, CCOpt has no accepted pilot, and 171 loaded islands preclude all-loads-served full N-1. Further work requires an explicit change in demand/security requirements or physical capabilities; changing only droop or solver settings cannot remove the certificate. S1 and the declared sampled 14-bus S2 scope remain closed. No release or tag has been published.')
    (OUT/'REPORT.md').write_text(body)
    assets = ROOT/'docs/src/assets/s2_500bus'
    assets.mkdir(exist_ok=True)
    for name in images:
        shutil.copy2(figures/name, assets/name)
    (ROOT/'docs/src/s2_500bus.md').write_text(body.replace('](figures/', '](assets/s2_500bus/'))


if __name__ == '__main__':
    report()
