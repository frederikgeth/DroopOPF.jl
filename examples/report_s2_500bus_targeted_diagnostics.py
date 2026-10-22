"""Report saved targeted campaign results; no optimization."""
import hashlib
import csv
import json
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from plot_s2_500bus_targeted_coverage import figures as coverage_figures

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'artifacts/s2_scopf/ieee500_native'
OUT=BASE/'targeted_demand_diagnostics'
FIG=ROOT/'docs/src/assets/s2_500bus_targeted'
load=lambda p:json.loads(p.read_text())


def main():
    FIG.mkdir(parents=True,exist_ok=True)
    summaries=[];designs=[];stage_calls=0;coverage_audits=[];design_backends={}
    for f in (1.05,1.1):
        path=OUT/f'summary-emergency-{round(f*10000)}.json'
        if not path.exists():continue
        summary=load(path);summaries.append(summary)
        coverage_path=OUT/f'audit-emergency-{round(f*10000)}-coverage.json'
        if coverage_path.exists():
            proof_data=load(coverage_path);assert proof_data['qualified']==summary['qualified']
            coverage_audits.append(dict(factor=f,qualified=proof_data['qualified'],path=str(coverage_path.relative_to(BASE))))
        if summary['selected_path']:
            folder=BASE/summary['selected_path'];stage=summary['selected_stage']
            audit=load(folder/f'audit-{stage}.json');assert audit['accepted']
            reduction=load(folder/f'network-audit-{stage}.json');assert reduction['accepted']
            designs.append((f,load(folder/f'controller-{stage}.json')['data']['case'],audit))
            backend=load(folder/'contract.json')['solver'];design_backends[f]={'madnlp':'MadNLP','ipopt':'Ipopt','ccopt':'CCOpt'}.get(backend,backend)
    for p in OUT.glob('emergency-*/stages.json'):stage_calls+=len(load(p))
    separator_calls=sum(len(load(p)) for p in (BASE/'emergency_loadability/coverage').glob('targeted-emergency-*/**/stages.json'))
    ccopt=[]
    for folder in sorted(OUT.glob('ccopt-100-*')):
        if not folder.is_dir():continue
        if (folder/'summary.json').exists():
            r=load(folder/'summary.json');ccopt.append(dict(path=folder.name,status=r['solver_status'],
                accepted=r['accepted'],native_optimizer_calls=r['native_optimizer_calls'],
                diagnostics=r.get('ccopt_diagnostics'),feasibility_stage=r.get('feasibility_stage')))
        elif (folder/'observer-failure.json').exists():
            r=load(folder/'observer-failure.json');ccopt.append(dict(path=folder.name,
                status=r['feasibility_stage']['status'],accepted=False,native_optimizer_calls=r['native_optimizer_calls'],
                export_error=r['export_error']))
    proof=OUT/'shared_active_normal/factor-1.05/independent_audit.json'
    bound=load(proof) if proof.exists() else None
    lp=load(proof.parent/'result.json') if proof.exists() else {}
    emergency_proof=OUT/'shared_active_emergency/factor-1.1/independent_audit.json'
    emergency_bound=load(emergency_proof) if emergency_proof.exists() else None
    emergency_lp=load(emergency_proof.parent/'result.json') if emergency_proof.exists() else {}
    result=dict(confirmation='User confirmed corrective taps/shunts on 2026-10-17; stated individual bounds, no extra movement budgets',
        ccopt=ccopt,independent_emergency_demands=summaries,normal_105_necessary_condition=bound,
        independent_coverage_audits=coverage_audits,emergency_separator_native_calls=separator_calls,
        emergency_master_native_calls=stage_calls,ccopt_master_native_calls=sum(r['native_optimizer_calls'] for r in ccopt),
        emergency_110_necessary_condition=emergency_bound,
        necessary_condition_lp_calls=len(lp.get('history',[]))+len(emergency_lp.get('history',[])),
        shared_multi_demand_started=False,full_n1_accepted=False,
        limitations=['Targeted-master feasibility and exhaustive connected-outage qualification are distinct.',
                     'A converged shedding stage does not establish a minimum-relief or loss-optimal design.',
                     'Normal-limit 110% infeasibility certificate does not apply to approved emergency policy.',
                     'No physical remedies, release or change to the closed S1 and 14-bus S2 studies.'])
    selection=OUT/'selected-operating-witnesses-10500.json'
    if selection.exists():
        chosen=load(selection);result['native_witness_selection']=dict(path=selection.name,replacements=chosen['replacements'],
            native_witnesses_only=True,optimizer_calls=0,common_controller_and_base_verified=True)
    zero_shedding=OUT/'dr-first-connected-witness.json'
    if zero_shedding.exists():result['derived_dr_first_witness']=load(zero_shedding)
    statistics=[]
    for item in coverage_audits:
        audit=load(BASE/item['path'])
        for group in audit['rounds']:
            if not group['qualified']:continue
            events=group['events'];statistics.append(dict(factor=audit['factor'],
                max_dr_mw=max(r['dr_mw'] for r in events),max_shedding_mw=max(r['shedding_mw'] for r in events),
                max_loading_over_rate_a=max(r['max_normal_loading_ratio'] for r in events),
                cases_with_normal_voltage_departures=sum(bool(r['normal_voltage_departures']) for r in events)))
    result['selected_operating_statistics']=statistics
    (OUT/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    images=[]
    if designs:
        fig,axes=plt.subplots(3,1,figsize=(12,10),constrained_layout=True)
        for f,case,audit in designs:
            states=audit['states'];ids=[x['id'].replace('generator_','G').replace('branch_','B') for x in states]
            axes[0].plot(ids,[x['max_normal_loading_ratio'] for x in states],'o-',label=f'{f:.0%} targeted master')
            axes[1].plot(ids,[x['dr_mw'] for x in states],'o-')
            axes[2].plot(ids,[x['shedding_mw'] for x in states],'o-')
        axes[0].axhline(1.,color='gray',ls=':',label='Normal Rate A')
        axes[0].axhline(1.1,color='red',ls='--',label='Emergency study cap')
        axes[2].axhline(10.,color='red',ls='--',label='Per-outage shedding cap')
        for ax,label in zip(axes,('Maximum loading / normal Rate A','Demand response (MW)','Load shedding (MW)')):
            ax.set_ylabel(label);ax.grid(alpha=.2)
        axes[0].legend(ncol=3);axes[2].legend()
        fig.suptitle('Original 500-bus replay of selected targeted masters\nCoverage and completed priority stages are reported separately')
        name='emergency-policy-use';images.append(name)
        fig.savefig(FIG/f'{name}.png',dpi=160);fig.savefig(FIG/f'{name}.pdf');plt.close(fig)
        calibration=load(ROOT/'artifacts/s1_arpae500/calibrated-study.json')['data']['case']
        nominal=load(BASE/'solver_demand_qualification/ipopt-10000/round-1/attempt-1-buildretry-1/controller.json')['data']['case']
        fig,axes=plt.subplots(2,1,figsize=(13,8),constrained_layout=True)
        for label,case in [('Qualified normal 100% Ipopt',nominal)]+[(f'{f:.0%} emergency {design_backends[f]} master',c) for f,c,_ in designs]:
            ids=[a['generator_id'] for a in case['attachments']]
            controls=[case['controls'][a['control_id']-1] for a in case['attachments']]
            refs=[calibration['controls'][a['control_id']-1] for a in case['attachments']]
            axes[0].plot(ids,[d['slope']*(d['capability']['q_max']-d['capability']['q_min']) for d in controls],'o-',ms=3,label=label)
            axes[1].plot(ids,[d['schedule']['v_ref']-r['schedule']['v_ref'] for d,r in zip(controls,refs)],'o-',ms=3)
        axes[0].axhline(.02,color='gray',ls='--');axes[0].axhline(.08,color='gray',ls='--')
        axes[1].axhline(-.02,color='gray',ls='--');axes[1].axhline(.02,color='gray',ls='--')
        axes[0].set_ylabel('Slope × Q capability span (pu V)');axes[1].set_ylabel('Reference change from calibration (pu V)')
        axes[1].set_xlabel('Generator ID');axes[0].legend()
        for ax in axes:ax.grid(alpha=.2)
        fig.suptitle('All 51 free droop slopes and reference voltages\nEmergency curves are selected master witnesses; see coverage and optimization-stage limits')
        name='droop-design-parameters';images.append(name)
        fig.savefig(FIG/f'{name}.png',dpi=160);fig.savefig(FIG/f'{name}.pdf');plt.close(fig)
        models=[('Calibrated input',calibration),('Qualified normal 100% Ipopt',nominal)]+[(f'{f:.0%} emergency {design_backends[f]} witness',c) for f,c,_ in designs]
        assignments=nominal['attachments']
        comparison=[]
        for label,case in models:
            for a in assignments:
                d=case['controls'][a['control_id']-1]
                comparison.append(dict(design=label,generator=a['generator_id'],bus=a['location']['bus_id'],
                    control=a['control_id'],slope=d['slope'],v_ref=d['schedule']['v_ref'],
                    v_db_low=d['schedule']['v_db_low'],v_db_high=d['schedule']['v_db_high'],
                    q_min=d['capability']['q_min'],q_max=d['capability']['q_max']))
        with (OUT/'droop-parameter-comparison.csv').open('w',newline='') as stream:
            writer=csv.DictWriter(stream,fieldnames=list(comparison[0]));writer.writeheader();writer.writerows(comparison)
        for page,start in enumerate(range(0,len(assignments),13),1):
            subset=assignments[start:start+13];nrows=4 if len(subset)>12 else 3
            fig,axes=plt.subplots(nrows,4,figsize=(14,11 if nrows==4 else 8.5));handles=[]
            for ax,a in zip(axes.flat,subset):
                controls=[c['controls'][a['control_id']-1] for _,c in models]
                low=min(d['schedule']['v_ref']-d['slope']*d['capability']['q_max'] for d in controls)-.005
                high=max(d['schedule']['v_ref']-d['slope']*d['capability']['q_min'] for d in controls)+.005
                voltage=np.linspace(low,high,300);handles=[]
                for (label,c),d in zip(models,controls):
                    reactive=np.clip((d['schedule']['v_ref']-voltage)/d['slope']+d['q_at_deadband'],d['capability']['q_min'],d['capability']['q_max'])
                    handles.append(ax.plot(voltage,reactive*c['base_power'],label=label,lw=1.2)[0])
                ax.set_title(f"G{a['generator_id']} / bus {a['location']['bus_id']}",fontsize=9)
                ax.set_xlabel('V (pu)',fontsize=8);ax.set_ylabel('Q (MVAr)',fontsize=8);ax.tick_params(labelsize=7);ax.grid(alpha=.2)
            for ax in list(axes.flat)[len(subset):]:ax.set_visible(False)
            fig.suptitle(f'All-generator zero-deadband droop comparisons — page {page}\nEmergency curves are feasible controller witnesses; loss-optimal design remains open',fontsize=12)
            fig.legend(handles,[x[0] for x in models],loc='upper center',bbox_to_anchor=(.5,.945),ncol=3,fontsize=9)
            fig.subplots_adjust(top=.88,bottom=.05,hspace=.5,wspace=.4)
            name=f'droop-curves-page-{page}';images.append(name)
            fig.savefig(FIG/f'{name}.png',dpi=160);fig.savefig(FIG/f'{name}.pdf');plt.close(fig)
    for summary in summaries:images.extend(coverage_figures(summary))
    lines=['# Targeted 500-bus S2 diagnosis and independent emergency designs','',
        'Confirmed campaign: all 131 taps and 11 continuous shunt banks corrective within the previously stated absolute bounds, '
        'with no additional movement budgets. All 51 slopes and 51 references are free and shared across base/outages '
        'within each independent-demand master. Exact active response remains hard.','',
        '## Results','',
        '| Demand / policy | Targeted master | Connected-outage qualification | Last retained priority |',
        '| --- | --- | --- | --- |']
    for s in summaries:
        covered=[r['coverage'] for r in s['rounds'] if r['coverage']]
        coverage=covered[-1] if covered else None
        text=('389/389 passed' if s['qualified'] else
              f"{coverage['evaluated']-len(coverage['failed'])}/{coverage['evaluated']} checked; {389-coverage['evaluated']} unchecked" if coverage else 'Not triggered')
        lines.append(f"| {s['factor']:.0%} / approved emergency | {'Accepted' if s['selected_path'] else 'Unresolved'} | {text} | {s['selected_stage'] or 'None'} |")
    lines+=['','Base states retain normal limits and full demand. Outages allow voltage intervals expanded by 0.05 pu, '
        '110% Rate A at both branch terminals, up to 1% DR per positive load, up to 10 MW shedding per outage, '
        'and a 10% combined per-load relief cap with proportional Q reduction. The 110% thermal cap is an approved study assumption.','',
        'A retained feasibility or shedding point establishes physical feasibility for its included states. '
        'Later priority failures do not invalidate that point, but it is not a completed minimum-DR/emergency/loss optimum. '
        'Only an exhaustive, independently replayed 389-event scan qualifies a connected-security controller.','',
        'In the retained 105% six-state master, all voltages stay within normal bounds. B36 and B562 use '
        'emergency capacity on lines 309 and 422; line 309 reaches about 109.93% of Rate A. '
        'Thus these validated states substantiate the thermal bottleneck suggested by the failed normal-limit iterates. '
        'The solution also uses DR, so this is not an isolated test of emergency ratings or network reduction alone.','',
        'Numerical exports: `droop-parameter-comparison.csv` includes every generator curve in the comparison; '
        '`emergency-10500-equipment-values.csv` includes all 55,380 base/outage tap and bank rows. '
        'Unavailable outaged taps are explicitly marked and excluded from envelopes.','',
        'The raw separator ledger is preserved. Its G60 and G14 witnesses shed 9.917915 and 9.913294 MW. '
        'The selected operating ledger reuses the already accepted native joint-master witnesses for those '
        'two outages, with approximately 0.00005012 MW shedding each, after verifying identical controller '
        'parameters and preventive base state/equipment. Every other separator witness is retained. '
        'This is witness selection within one design, not a union of different controllers, a new optimizer run '
        'or a minimum-relief claim. The selected 389-outage ledger is independently replayed again.','',
        'A separate DR-first allocation removes the remaining approximately 0.00005012 MW of shedding in '
        'the G14/G60 master witnesses by replacing it with permitted DR at the same loads. This preserves '
        'total nodal P/Q relief, all electrical states, controller parameters and equipment. Original-network '
        'and reduction audits pass. Together with the other 387 native zero-shedding witnesses, this constructs '
        'a zero-shedding feasible allocation for all 389 connected outages at 105%. '
        'It makes zero optimizer calls and is explicitly not a new native optimization or a minimum-DR/loss result. '
        'See `dr-first-connected-witness.json` and `relief_priority_witness.json`.','',
        '## CCOpt diagnosis','']
    for r in ccopt:
        lines.append(f"- `{r['path']}`: {r['status']}; accepted={r['accepted']}; {r['native_optimizer_calls']} native call(s)."+
                     (' Snapshot export failed after feasibility; the repair attempt is separate.' if r.get('export_error') else ''))
    lines+=['','The earlier nominal campaign reached native constant-objective convergence once and then lost convergence on loss minimization. '
        'The new attempts preserve stage values and named constraints where available. Final relaxed-NLP stationarity '
        'is not an original MPCC optimality certificate; failed iterates never qualify a controller.','',
        'The instrumented expanded master had maximum AC balance residual below 6e-8 pu, but its exact droop '
        'residual reached 7.076e-5 pu for G71 at bus 319 during the G32 outage. Its relaxation remained near '
        '1.845e-6, with dual feasibility about 0.105. Large mapped bound duals occur on normalized upper-Q '
        'projection slacks. This points to complementarity saturation/scaling as a convergence issue; it is '
        'not proof of a unique cause. The objective never switched to loss in that attempt. '
        'Its legacy `snapshot-loss.json` is a duplicate final feasibility snapshot; `actual_stage` in '
        '`stage-physical-audit.json` records this explicitly. The smaller unregularized master passed physical '
        'replay for its three states but retained TIME_LIMIT, without a loss stage or security qualification. '
        'The final recovery adds temporary normalized droop-distance curvature during feasibility, then removes '
        'that term completely before any original loss solve; all 102 parameters remain free.','',
        'The regularized recovery reached relaxation 9.09e-13 and complementarity product 3.08e-10, '
        'but ended SLOW_PROGRESS with relaxed-NLP primal feasibility 0.0885 and dual feasibility 1000. '
        'Its original-network replay fails. Tightening the relaxation alone therefore did not recover '
        'the coupled problem, and no new CCOpt loss-optimal design is accepted.','',
        '## Normal-limit 105% bottleneck analysis','',
        'The saved accepted normal-limit master has only 0.059936 MW and 0.013347 MW remaining in the G14/G60 '
        'balancing coordinates at its fixed preventive dispatch. These are not demand margins. '
        'Line 309 appears in both failed B36/B562 retry diagnostics, whose nonzero nodal residuals are not required relief amounts.','',
        (f"The stronger joint G14/G60/B36/B562 necessary-condition relaxation made {len(lp.get('history',[]))} LP calls. "
         f"Exact replay verified {bound['rows']:,} rows; certified infeasible={bound['certified_infeasible']}. "
         'Absence of a positive ray remains inconclusive about AC feasibility.' if bound else 'Necessary-condition audit pending.'),'',
        (f"The corresponding joint emergency 110% relaxation made {len(emergency_lp.get('history',[]))} LP calls, "
         f"including B562 and the approved relief caps. Exact replay verified {emergency_bound['rows']:,} rows; "
         f"certified infeasible={emergency_bound['certified_infeasible']}. The 110% emergency target remains numerically unresolved."
         if emergency_bound else 'Emergency 110% necessary-condition audit pending.'),'',
        'The original normal-limit 110% certificate remains valid in its original scope and does not exclude the emergency policy. '
        'Islanding events remain separate. No shared multi-demand optimum, full N−1 closure or physical-remedy result is claimed.','',
        f"Master native calls: {stage_calls} emergency, {sum(r['native_optimizer_calls'] for r in ccopt)} CCOpt; "
        f"{separator_calls} emergency separator calls, and {len(lp.get('history',[]))+len(emergency_lp.get('history',[]))} "
        'necessary-condition LP calls. Setup failures before optimization are not native calls.','']
    for name in images:
        rel=f'../../../../docs/src/assets/s2_500bus_targeted/{name}'
        lines += [f'![{name}]({rel}.png)',f'[PDF]({rel}.pdf)','']
    (OUT/'REPORT.md').write_text('\n'.join(lines))
    docs=ROOT/'docs/src/s2_500bus.md';marker='\n## Targeted diagnosis and independent emergency designs\n'
    original=docs.read_text().split(marker)[0]
    section=[marker.strip(),'','The confirmed targeted campaign retains corrective taps/shunts, exact active response, '
        'and 102 free droop parameters within each independent-demand master. Original normal-limit and approved emergency results remain separate.','']
    section+=lines[lines.index('| Demand / policy | Targeted master | Connected-outage qualification | Last retained priority |'):lines.index('## CCOpt diagnosis')]
    section+=['The joint normal-limit 105% necessary-condition test found no positive infeasibility certificate. '
        'The original normal-limit 110% certificate does not establish emergency-policy infeasibility. '
        'CCOpt remains qualified only if its native original loss design and full physical/security checks pass.','']
    for name in images:section += [f'![{name}](assets/s2_500bus_targeted/{name}.png)',f'[PDF](assets/s2_500bus_targeted/{name}.pdf)','']
    section+=['Detailed records: `artifacts/s2_scopf/ieee500_native/targeted_demand_diagnostics/REPORT.md` and `RESULTS.json`.','']
    docs.write_text(original+'\n'+'\n'.join(section))
    followup=dict(report='targeted_demand_diagnostics/REPORT.md',results='targeted_demand_diagnostics/RESULTS.json',
        emergency_connected_qualified_factors=[s['factor'] for s in summaries if s['qualified']],
        emergency_unresolved_factors=[s['factor'] for s in summaries if not s['qualified']],
        ccopt_recovered=any(r['accepted'] for r in ccopt),normal_105_infeasibility_certified=bool(bound and bound['certified_infeasible']),
        multi_demand_qualified=False,full_n1_accepted=False)
    for filename in ('STATUS.json','CURRENT_RESULTS.json'):
        path=BASE/filename;parent=load(path);parent['targeted_demand_diagnostics']=followup
        path.write_text(json.dumps(parent,indent=2)+'\n')
    parent=BASE/'REPORT.md';marker='\n## Targeted demand diagnosis and emergency qualification\n'
    parent.write_text(parent.read_text().split(marker)[0]+marker+'\n'+
        'See the [targeted campaign report](targeted_demand_diagnostics/REPORT.md) for the confirmed corrective-control '
        'CCOpt diagnostics, joint necessary-condition checks and independent emergency-policy demand results. '
        'Original normal-limit results, S1 closure and the sampled 14-bus S2 closure retain their declared scope.\n')
    note='The [targeted demand diagnosis and emergency-design follow-up](docs/src/s2_500bus.md#targeted-diagnosis-and-independent-emergency-designs) '
    qualified=', '.join(f"{s['factor']:.0%}" for s in summaries if s['qualified']) or 'none'
    note+=f'qualifies independent emergency-policy connected-outage designs at {qualified}. '
    note+='The 110% emergency target and CCOpt remain unresolved; normal-limit results and full N−1/islanding gates stay separate. '
    note+='The reports retain stage snapshots, exact joint-relaxation replay, all-generator parameter comparisons and original-network checks.'
    readme=ROOT/'README.md';text=readme.read_text();marker='\nThe [targeted demand diagnosis and emergency-design follow-up]'
    text=text.split(marker)[0]
    text=text.replace('The best 105% controller passes 387/389; 105% remains unresolved.',
                      'Under original normal limits, the best 105% controller passes 387/389; that normal-limit target remains unresolved.')
    readme.write_text(text.rstrip()+'\n\n'+note+'\n')
    roadmap=ROOT/'ROADMAP.md';marker='\nThe targeted independent emergency-design campaign '
    roadmap.write_text(roadmap.read_text().split(marker)[0].rstrip()+'\n'+marker+
        f'qualifies connected-outage designs at {qualified}; see the [targeted results](docs/src/s2_500bus.md#targeted-diagnosis-and-independent-emergency-designs). '
        'The 110% emergency gate and CCOpt remain unresolved. No shared multi-demand or full N−1 closure is implied.\n')
    changelog=ROOT/'CHANGELOG.md';text=changelog.read_text()
    entry=f'- Targeted 500-bus CCOpt stage diagnostics and independent emergency-policy design qualification at {qualified}, with exact network reduction, original-network outage replay, joint necessary-condition audits and parameter/operating figures. The 110% emergency target and CCOpt remain unresolved; original normal-limit results retain their separate scope.\n\n'
    if '- Targeted 500-bus CCOpt stage diagnostics' not in text:
        text=text.replace('### Added\n\n','### Added\n\n'+entry,1)
    text=text.replace('CCOpt and 105% remain unqualified after bounded retries;',
                      'CCOpt and original normal-limit 105% remain unqualified after bounded retries;')
    changelog.write_text(text)
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.rglob('*') if p.is_file() and p.name!='source_manifest.json'}
    for p in list(FIG.glob('*'))+list((ROOT/'src').rglob('*.jl'))+[Path(__file__),ROOT/'examples/plot_s2_500bus_targeted_coverage.py',docs,readme,roadmap,changelog,BASE/'REPORT.md',BASE/'STATUS.json',BASE/'CURRENT_RESULTS.json',ROOT/'Project.toml',ROOT/'Manifest.toml',ROOT/'AGENTS.md',BASE/'pilot_study.json',ROOT/'artifacts/s1_arpae500/calibrated-study.json',ROOT/'artifacts/s1_free_droop/500/angle_limits.json',ROOT/'examples/s2_500bus_targeted_emergency.jl',ROOT/'examples/s2_500bus_targeted_ccopt.jl',ROOT/'examples/s2_arpae500_recovery.jl',ROOT/'examples/s2_arpae500_loadability.jl',ROOT/'examples/audit_s2_500bus_targeted_coverage.py',ROOT/'examples/audit_s2_500bus_targeted_ccopt.py',ROOT/'examples/s2_500bus_shared_active_bound.jl',ROOT/'examples/audit_s2_500bus_shared_active.py',ROOT/'examples/s2_followup_physics.py',ROOT/'examples/audit_s2_500bus_loadability.py',ROOT/'examples/audit_s2_500bus_network_reduction.py',ROOT/'examples/s2_500bus_network_reduction.jl']:
        hashes[str(p.relative_to(ROOT))]=hashlib.sha256(p.read_bytes()).hexdigest()
    (OUT/'source_manifest.json').write_text(json.dumps(hashes,indent=2)+'\n')
    print(json.dumps(dict(emergency_master_native_calls=stage_calls,ccopt_master_native_calls=sum(r['native_optimizer_calls'] for r in ccopt),figures=len(images),demands=len(summaries))))


if __name__=='__main__':main()
