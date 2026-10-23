"""Report continuation and response-policy diagnostics without weakening acceptance."""
import hashlib
import json
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'artifacts/s2_scopf/ieee500_native'
OUT = BASE / 'response_continuation'
FIG = ROOT / 'docs/src/assets/s2_500bus/response_continuation'
HEADING = '## Demand continuation and response-policy diagnostics'
load = lambda p: json.loads(Path(p).read_text())
save = lambda p, x: Path(p).write_text(json.dumps(x, indent=2) + '\n')


def report():
    summary = load(OUT / 'summary.json')
    rows = summary['attempts']
    details = []
    for r in rows:
        folder = OUT / r['name']
        audit = load(folder / f"audit-{r['stage']}.json")
        network = load(folder / f"network-audit-{r['stage']}.json")
        stage = load(folder / 'stages.json')[-1]
        assert r['accepted']==network['accepted']
        assert r['diagnostic_accepted']==network['diagnostic_accepted']
        assert r['native_status']==stage['status']
        assert not (r['accepted'] and r['cap']>0.)
        details.append(dict(**r, elapsed_seconds=stage['elapsed_seconds'],
            native_details=stage.get('native_details'),objective=stage['objective'],
            reconstruction_valid=network['reduction_valid'],
            original_physics_and_response_valid=audit['physical_valid'],
            max_loading_ratio=max(s['max_normal_loading_ratio'] for s in audit['states']),
            vm_min=min(s['vm_min_pu'] for s in audit['states']),
            vm_max=max(s['vm_max_pu'] for s in audit['states']),
            largest_response_rule_errors=sorted([dict(outage=s['id'], **e)
                for s in audit['states'] for e in s.get('largest_response_rule_errors', [])],
                key=lambda e:abs(e['error_mw']),reverse=True)))
    results = dict(**summary, runs=details, shared_controller_fixed=True,
        full_network_validation_required=True, diagnostic_is_original_recovery=False,
        minimum_relief_established=False, physical_remedies=False)
    save(OUT / 'RESULTS.json', results)
    save(OUT / 'STATUS.json', dict(closed=False, bounded_campaign_complete=True,
        last_exact_expanded_master_factor=summary['last_exact_factor'],
        target_recovered=summary['target_recovered'], exhaustive_qualified=False,
        full_n1_accepted=False, five_demand_optimum_accepted=False))

    FIG.mkdir(parents=True, exist_ok=True)
    fig, axs = plt.subplots(2, 2, figsize=(13, 8), layout='constrained')
    xx = list(range(1, len(rows)+1))
    for k, r in zip(xx, rows):
        color, marker = ('#16834a','o') if r['accepted'] else (('#bd7811','D') if r['diagnostic_accepted'] else ('#ba3535','x'))
        axs[0,0].scatter(k, 100*r['factor'], color=color, marker=marker, s=60)
        axs[0,1].scatter(k, max(1e-12,r['max_response_mw']), color=color, marker=marker, s=60)
        axs[1,1].scatter(k, max(1e-16,r['max_balance_pu']), color=color, marker=marker, s=60)
    axs[0,0].axhline(110,color='gray',ls=':',label='110% target')
    for color, marker, label in [('#16834a','o','Accepted exact policy'),('#bd7811','D','Diagnostic only'),('#ba3535','x','Rejected attempt')]:
        axs[0,0].scatter([],[],color=color,marker=marker,label=label)
    axs[0,0].legend(fontsize=8)
    axs[0,0].set_ylabel('Demand (% of nominal)')
    axs[0,1].set_yscale('log'); axs[0,1].set_ylabel('Max response-rule error (MW)')
    axs[0,1].set_title('Policy deviation; not a power injection or load deficit')
    axs[1,0].plot(xx,[r['max_dr_mw'] for r in rows],'o-',label='DR')
    axs[1,0].plot(xx,[r['max_shedding_mw'] for r in rows],'s-',label='Shedding')
    axs[1,0].axhline(10,color='gray',ls=':',label='Shedding cap')
    axs[1,0].legend(fontsize=8); axs[1,0].set_ylabel('Max per-outage relief (MW)')
    axs[1,0].set_title('Rejected points are shown for diagnosis only')
    axs[1,1].set_yscale('log'); axs[1,1].set_ylabel('Original 500-bus max P/Q residual (pu)')
    for ax in axs.flat:
        ax.set_xlabel('Attempt number (report table order)'); ax.grid(alpha=.2)
    fig.suptitle('500-bus expanded master: continuation and response-policy restoration')
    for ext in ('png','pdf'): fig.savefig(FIG / f'continuation.{ext}',dpi=180)
    plt.close(fig)

    selected=[]
    for r in rows:
        if r['accepted']:
            selected.extend(load(OUT/r['name']/f"audit-{r['stage']}.json")['states'])
    fig,axs=plt.subplots(2,2,figsize=(12,8),layout='constrained')
    for sid in ['base','branch_36','branch_219','branch_562','generator_14','generator_60']:
        ss=sorted([s for s in selected if s['id']==sid],key=lambda s:s['factor'])
        if not ss: continue
        d=[100*s['factor'] for s in ss]
        line=axs[0,0].plot(d,[s['max_normal_loading_ratio'] for s in ss],'.-',label=sid)[0]
        color=line.get_color()
        axs[0,1].plot(d,[s['vm_min_pu'] for s in ss],'.-',color=color,label=sid)
        axs[0,1].plot(d,[s['vm_max_pu'] for s in ss],'.--',color=color)
        axs[1,0].plot(d,[s['dr_mw'] for s in ss],'.-',color=color,label=sid)
        axs[1,1].plot(d,[s['shedding_mw'] for s in ss],'.-',color=color,label=sid)
    axs[0,0].axhline(1,color='gray',ls=':',label='Normal cap')
    axs[0,0].axhline(1.1,color='black',ls=':',label='Outage emergency cap')
    axs[0,0].set_ylabel('Largest both-terminal S / original Rate A')
    axs[0,0].legend(fontsize=7,ncol=2)
    # This source has common 0.9–1.1 normal bus bounds; the case-specific
    # auditor, rather than these visual guides, determines acceptance.
    for v in (.9,1.1):axs[0,1].axhline(v,color='gray',ls=':')
    for v in (.85,1.15):axs[0,1].axhline(v,color='black',ls=':')
    axs[0,1].set_ylabel('Min (solid) / max (dashed) voltage (pu)')
    axs[0,1].set_title('Normal bounds 0.9–1.1; outage caps 0.85–1.15')
    axs[1,0].set_ylabel('Demand response (MW)')
    case=load(BASE/'pilot_study.json')['data']['case']
    positive_load_mw=sum(max(0.,l['p']) for l in case['loads'])*case['base_power']
    factors=sorted({s['factor'] for s in selected})
    axs[1,0].plot([100*f for f in factors],[.01*positive_load_mw*f for f in factors],
        ':',color='black',label='Aggregate 1% DR cap')
    axs[1,0].legend(fontsize=7,ncol=2)
    axs[1,1].set_ylabel('Shedding (MW)');axs[1,1].axhline(10,color='black',ls=':')
    for ax in axs.flat:ax.set_xlabel('Demand (% of nominal)');ax.grid(alpha=.2)
    fig.suptitle('Accepted exact-policy points only — feasibility, not minimum relief')
    for ext in ('png','pdf'):fig.savefig(FIG/f'accepted-physics.{ext}',dpi=180)
    plt.close(fig)

    last=100*summary['last_exact_factor']
    text=['# 500-bus demand continuation and response-policy diagnostics','',
        f'The last accepted exact-policy expanded-master demand is **{last:g}%**. The 110% target is '+('recovered.' if summary['target_recovered'] else '**not recovered**.')+' Overall 500-bus S2 remains open.','',
        '## Configuration and acceptance','',
        'This is the user-approved continuation/recovery follow-up to the 105% expanded master. All 131 taps (469–599) remain corrective at 0.95–1.05; all 11 continuous shunts remain corrective within the confirmed individual bounds, with no added movement budget. The retained 51-slope/reference controller is fixed to isolate dispatch/response feasibility. A failure here does not prove that every free-controller design fails.','',
        'The six-state master contains base, lines 36 and 219, transformer 562, G14 and G60. Preventive Pg and corrective equipment remain free. The base uses normal limits and full demand. Outages retain the confirmed voltage extension of 0.05 pu, 110% Rate A at both terminals, per-load DR ≤1%, total shedding ≤10 MW and combined per-load relief ≤10%, with proportional Q relief. Zero shedding is tried first. Feasibility points do not minimize relief or emergency departures.','',
        'Exact sparse reduction retains 430 voltage buses and all original equipment inequalities. Every saved point is reconstructed and independently checked against the original 500-bus network. Only native convergence, zero response relaxation, and all original physical/policy checks permit acceptance. A native SLOW_PROGRESS or TIME_LIMIT remains rejected even if its physical residuals pass.','',
        'Diagnostic models change only `Pg_out = Pg_base + alpha*delta + e`, with `|e_g| ≤ rho*Pmax_g`. At rho=1, any bounded corrective Pg is possible with delta=0; this diagnoses the existing response restriction. Errors are policy deviations, not nodal power injections or required shedding. Squared-error minimization and reduced caps provide warm starts for a fresh exact model. Positive rho is never accepted as an original-model recovery. The locally obtained error is not a proven global minimum.','',
        '## Attempts','',
        '| # | Attempt | Demand | Cap / Pmax | Solver | Native status | Exact accepted | Diagnostic accepted | DR MW | Shed MW | Response error MW |',
        '| ---: | --- | ---: | ---: | --- | --- | --- | --- | ---: | ---: | ---: |']
    for i,r in enumerate(rows,1):
        text.append(f"| {i} | {r['name']} | {100*r['factor']:g}% | {r['cap']:.6g} | {r['solver']} | {r['native_status']} | {r['accepted']} | {r['diagnostic_accepted']} | {r['max_dr_mw']:.6f} | {r['max_shedding_mw']:.6f} | {r['max_response_mw']:.6g} |")
    text += ['',f"The campaign executed {len(rows)} native attempts, with a declared maximum of {summary['maximum_attempts']}. Each attempt retains its executed driver/adapter, contract, native stages, primal state and independent full-network/reconstruction audits. The primary step is 0.5 percentage points, refined to 0.25 after a failed step. A failed local solve is not an infeasibility certificate or an exact feasible boundary.",'',
        '![Continuation and diagnostics](../../../../docs/src/assets/s2_500bus/response_continuation/continuation.png)','',
        '![Accepted exact-policy physics and relief](../../../../docs/src/assets/s2_500bus/response_continuation/accepted-physics.png)','',
        '## Scope and reproduction','',
        'Accepted points cover the listed five outages only. No new 389-connected-outage qualification, shared five-demand optimum, or all-islanding N−1 acceptance follows. Existing normal-policy infeasibility certificates and island supply obstructions retain their original scope. No physical remedy, capability change, release or tag is introduced.','',
        'This campaign combines continuation, warm starts, sparse exact reduction and the previously recorded equivalent relief-auxiliary cleanup. It does not provide a matched full-model continuation benchmark that could attribute convergence gains solely to network reduction.','',
        'Run `examples/s2_500bus_response_continuation.jl`, then `examples/s2_500bus_response_continuation_retry.jl` serially in a fresh output checkout to preserve records. The retry driver adds alternate exact Ipopt starts and up to six tighter-cap/restoration rounds within the original total 36-call limit. Generate this report with `examples/report_s2_500bus_response_continuation.py`. The optimizer-free response guard tests are in `response_audit_guard_checks.json`; they test acceptance/rejection of exact, relaxed-response, over-cap and AC-invalid points. `source_manifest.json` hashes the retained sources and audits.','']
    if selected:
        latest=[s for s in selected if s['factor']==summary['last_exact_factor']]
        extra=['## Last accepted exact-policy point','',
            '| State | DR MW | Shedding MW | Max S / Rate A | Min voltage pu | Max voltage pu |',
            '| --- | ---: | ---: | ---: | ---: | ---: |']
        for s in latest:
            extra.append(f"| {s['id']} | {s['dr_mw']:.6f} | {s['shedding_mw']:.6f} | {s['max_normal_loading_ratio']:.8f} | {s['vm_min_pu']:.8f} | {s['vm_max_pu']:.8f} |")
        extra+=['','This observed operating point identifies tight thermal/voltage margins, not unique binding causes or a proven minimum relief requirement. Separate per-bus, per-generator and per-branch audit records retain the exact identities.','']
        pos=text.index('## Scope and reproduction')
        text[pos:pos]=extra
    diagnostics=[r for r in rows if r['diagnostic_accepted']]
    if diagnostics:
        tight=min(diagnostics,key=lambda r:(r['cap'],r['max_response_mw']))
        extra=['## Response-policy diagnostic outcome','',
            f"The smallest cap with native convergence and full-network physical acceptance is {tight['cap']:.8g} of each available generator's Pmax, at {100*tight['factor']:g}% demand. Its largest actual response-rule deviation is {tight['max_response_mw']:.8g} MW. This is diagnostic acceptance only; positive relaxation cannot qualify the original response policy.",'',
            'The relaxed physical witness supplies a starting point for exact restoration. Local response-error minima and failed exact solves neither prove a positive global response gap nor identify a required MW remedy. The retained-controller restriction also prevents a global free-controller infeasibility conclusion.','']
        pos=text.index('## Scope and reproduction')
        text[pos:pos]=extra
    (OUT/'REPORT.md').write_text('\n'.join(text))
    doc=ROOT/'docs/src/s2_500bus.md'
    document=doc.read_text()
    followup='## Free-droop continuation with exact active response'
    tail=('\n\n'+followup+document.split(followup,1)[1]) if followup in document else ''
    previous=document.split(HEADING)[0].rstrip()
    section=[HEADING,'',text[2],'',
        'The accepted 105% expanded master seeds 0.5-percentage-point steps, refined to 0.25 on failure. The retained controller is fixed for this diagnostic; preventive Pg and confirmed corrective taps/banks remain free. Hard physical limits, DR/shedding budgets and original branch terminal ratings are unchanged. All points are replayed on the original 500-bus network.','',
        'A diagnostic permits bounded deviations from the original proportional active response, then minimizes these errors and attempts a fresh exact-policy model. Positive relaxation can never count as recovery. Native failure remains rejected even when physical residuals are small; a failed local solve is not a global infeasibility proof.','',
        '![Continuation and response-policy diagnostics](assets/s2_500bus/response_continuation/continuation.png)','',
        '![Accepted exact-policy physics and relief](assets/s2_500bus/response_continuation/accepted-physics.png)','',
        f"The {len(rows)} native attempt records and separate exact/diagnostic outcomes are in `artifacts/s2_scopf/ieee500_native/response_continuation/REPORT.md` and `RESULTS.json`. These cover base plus B36/B219/B562/G14/G60 only; nominal remains the exhaustively qualified connected-outage lower point. Minimum relief and the exact feasible boundary are not established. No physical remedy or release is introduced.",'']
    doc.write_text(previous+'\n\n'+'\n'.join(section)+tail)
    pointer=dict(report='response_continuation/REPORT.md',results='response_continuation/RESULTS.json',
        last_exact_expanded_master_factor=summary['last_exact_factor'],target_recovered=summary['target_recovered'],
        full_n1_accepted=False)
    for p in [BASE/'CURRENT_RESULTS.json',BASE/'STATUS.json']:
        data=load(p); data['response_continuation_followup']=pointer; save(p,data)
    save(OUT/'VALIDATION.json',dict(original_500bus_replay_per_attempt=True,
        all_reduction_maps_valid=all(r['reconstruction_valid'] for r in details),
        acceptance_guards=load(OUT/'response_audit_guard_checks.json'),
        reduction_acceptance_guards=load(BASE/'network_reduction/audit_guard_checks.json'),
        accepted_exact=[r['name'] for r in rows if r['accepted']],
        diagnostic_only=[r['name'] for r in rows if r['diagnostic_accepted']],
        exhaustive_outage_qualification=False))
    paths=[p for p in OUT.rglob('*') if p.is_file() and p.name!='source_manifest.json']
    paths += sorted(FIG.glob('*'))
    paths += [ROOT/'examples'/n for n in ['s2_500bus_response_continuation.jl','s2_arpae500_loadability.jl',
        's2_500bus_network_reduction.jl','audit_s2_500bus_loadability.py','audit_s2_500bus_network_reduction.py',
        'report_s2_500bus_response_continuation.py','check_s2_500bus_response_audit.py',
        's2_500bus_response_continuation_retry.jl']]
    save(OUT/'source_manifest.json',{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})
    print(json.dumps(dict(attempts=len(rows),last_exact_percent=last,target_recovered=summary['target_recovered'])))


if __name__=='__main__': report()
