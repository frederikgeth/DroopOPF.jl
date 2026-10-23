"""Report P2-02 saved replay, new held-out misses and measured runtime savings."""
import hashlib,json,statistics,sys
from pathlib import Path

def report(out):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    saved=json.loads((out/'frozen_discovery/RESULTS.json').read_text())
    audit=json.loads((out/'heldout_audit.json').read_text())
    policies=['legacy','guarded','exhaustive'];totals=[]
    for policy in policies:
        for family in ['line','transformer','generator']:
            rows=[r for r in audit['families'] if r['policy']==policy and r['family']==family]
            counts={key:sum(r[key] for r in rows) for key in ['total','screened','unresolved','misses','physical_misses','unstable']}
            counts['unresolved_recall']=1-counts['misses']/counts['unresolved'] if counts['unresolved'] else None
            totals.append(dict(policy=policy,family=family,**counts))
    inputs=[r for r in audit['inputs'] if r['complete']];timings={}
    for policy in policies:
        medians=[statistics.median(t['elapsed'] for t in r['timings'] if t['policy']==policy and t['repetition'] in [2,3]) for r in inputs]
        timings[policy]=dict(sum_per_input_warm_medians_seconds=sum(medians),inputs=len(medians))
    for policy in ['legacy','guarded']:
        seconds=timings[policy]['sum_per_input_warm_medians_seconds'];exact=timings['exhaustive']['sum_per_input_warm_medians_seconds']
        timings[policy].update(speedup=exact/seconds if seconds else None,runtime_saving_fraction=1-seconds/exact if exact else None)
    guarded=[r for r in totals if r['policy']=='guarded'];branch_failures=sum(r['unresolved'] for r in guarded if r['family']!='generator')
    missed=sum(r['misses'] for r in guarded)
    status='QUALIFICATION_FAILED' if missed else 'INCOMPLETE_COVERAGE' if len(inputs)!=24 else 'NO_BRANCH_FAILURE_EVIDENCE' if not branch_failures else 'NO_OBSERVED_MISSES_FINITE_SCOPE'
    result=dict(status=status,new_heldout_inputs=len(audit['inputs']),
        complete_inputs=len(inputs),unassessed_inputs=[r for r in audit['inputs'] if not r['complete']],saved_false_screens=saved['original_false_screens'],
        saved_remaining_misses=saved['enhanced_false_screens'],new_heldout_guarded_misses=missed,branch_unresolved=branch_failures,
        families=totals,timings=timings,replayed_states=audit['replayed_states'],replay_discrepancies=len(audit['discrepancies']),
        accepted_control_regimes=audit['accepted_control_regimes'],default_guard_enabled=False,
        limitation='Finite sample only; unresolved solver/physical outcomes are not infeasibility certificates; exhaustive final audit remains mandatory')
    size_by_id={item['case']['id']:len(item['case']['network']['buses']) for item in json.loads((out/'plan.json').read_text())['inputs']}
    per_size=[]
    for size in sorted(set(size_by_id.values())):
        selected=[r for r in inputs if size_by_id[r['id']]==size]
        ids={r['id'] for r in selected}
        measured={p:sum(statistics.median(t['elapsed'] for t in r['timings'] if t['policy']==p and t['repetition'] in [2,3]) for r in selected) for p in policies}
        phases={p:sum(statistics.median(t['phases'].get('filter',0) for t in r['timings'] if t['policy']==p and t['repetition'] in [2,3]) for r in selected) for p in policies}
        counts={p:{key:sum(r[key] for r in audit['families'] if r['input'] in ids and r['policy']==p) for key in ['total','screened','unresolved','misses','physical_misses','unstable']} for p in policies}
        phase_totals={p:{phase:sum(statistics.median(t['phases'].get(phase,0) for t in r['timings'] if t['policy']==p and t['repetition'] in [2,3]) for r in selected) for phase in ['filter','prepare_build','optimize_extract','validate_rank']} for p in policies}
        per_size.append(dict(buses=size,complete_inputs=len(selected),timings=measured,filter_seconds=phases,phase_seconds=phase_totals,counts=counts,
            guarded_runtime_saving_fraction=1-measured['guarded']/measured['exhaustive'] if measured['exhaustive'] else None))
    cfg_path=out/'configuration_audit.json'
    if cfg_path.exists():
        result['configuration_results_checked']=sum(r['exact_results_checked'] for r in json.loads(cfg_path.read_text())['inputs'])
    route_path=out/'routing_audit.json'
    if route_path.exists():
        result['guarded_routing']=json.loads(route_path.read_text())['inputs']
    result['per_size']=per_size
    result['guarded_screened_outages']=sum(r['screened'] for r in guarded)
    result['accuracy_evidence_note']='Zero misses is conditional on complete inputs; if no outages are screened, exact routing alone explains zero misses.'
    result['scaling_note']='Network size, droop width and anchor regime vary across cohorts; per-size totals describe these cohorts and do not isolate size as the sole cause.'
    result['timing_note']='Two warmed repetitions per input; measured differences are descriptive, with no confidence interval or significance claim.'
    result['planned_unique_outages']=sum(len(item['case']['network']['branches'])+len(item['case']['generators']) for item in json.loads((out/'plan.json').read_text())['inputs'])
    result['assessed_unique_outages']=sum(r['total'] for r in guarded)
    result['configuration']='fixed supplied taps/shunts; zero equipment movement; frozen shared droop; preventive equal-weight active response'
    (out/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    fig,axes=plt.subplots(1,2,figsize=(10.5,4.2))
    for k,policy in enumerate(['legacy','guarded']):
        rs=[r for r in totals if r['policy']==policy];axes[0].bar([i+(k-.5)*.35 for i in range(3)],[r['misses'] for r in rs],.35,label=policy)
    axes[0].set_xticks(range(3),['line','transformer','generator']);axes[0].set(ylabel='Screened unresolved outages',title='New held-out false screens');axes[0].legend()
    axes[1].bar(policies,[timings[p]['sum_per_input_warm_medians_seconds'] for p in policies]);axes[1].set(ylabel='Summed per-input warm median time (s)',title='Routing + AC evaluation + validation')
    fig.tight_layout();fig.savefig(out/'qualification.png',dpi=160);plt.close(fig)
    fig2,ax2=plt.subplots(1,2,figsize=(10.5,4.2))
    for policy in policies:
        ax2[0].plot([r['buses'] for r in per_size],[r['timings'][policy]/r['complete_inputs'] if r['complete_inputs'] else float('nan') for r in per_size],marker='o',label=policy)
    ax2[0].set(xlabel='Buses',ylabel='Warm median seconds per completed input',title='Time by synthetic cohort');ax2[0].legend()
    ax2[1].bar([str(r['buses']) for r in per_size],[100*r['filter_seconds']['guarded']/r['timings']['guarded'] if r['timings']['guarded'] else 0 for r in per_size])
    ax2[1].set(xlabel='Buses',ylabel='Filtering share of guarded runtime (%)',title='Filter + dense predictor overhead')
    fig2.tight_layout();fig2.savefig(out/'scaling.png',dpi=160);plt.close(fig2)
    lines=['# P2 02 scale qualification' ,'',f'New held-out result: **{result["status"]}** across {len(inputs)}/{len(audit["inputs"])} completely assessed inputs. Historical false screens in the prior study: {saved["original_false_screens"]}; prior remaining after the guard: {saved["enhanced_false_screens"]}.','',
        '## Frozen comparison contract','',
        'Old discovery and old held-out inputs are known regression evidence. Twenty-four new 12/24/48-bus synthetic inputs with distributed generators and two meshed topologies were specified and all numerical guard/source settings frozen before any new base or outage solve. Transformer ratios, shunts and droop curves are fixed; the same base state and preventive participation policy are used by all paths. The guard is opt-in and only escalates legacy screened branches. Per-unit reactive headroom uses both generator and controller bounds. A bounded nonlinear AC/droop predictor detects projected voltage/thermal/active/reactive risks and regime changes; uncertainty always goes to exact evaluation. It is not a security certificate.','',
        '## Coverage and misses','', '| Policy | Family | Outages | Screened | Unresolved | Missed unresolved | Missed invalid physical states |','|---|---|---:|---:|---:|---:|---:|']
    for r in totals:lines.append(f'| {r["policy"]} | {r["family"]} | {r["total"]} | {r["screened"]} | {r["unresolved"]} | {r["misses"]} | {r["physical_misses"]} |')
    lines+=['',f'Guarded branch unresolved count: {branch_failures}. Recall is undefined when a family has no unresolved cases. Unresolved means rejection/error or physical invalidity, not proven infeasibility. Classification changes across repetitions are retained and any unresolved exhaustive repetition counts against screening. Incomplete or invalid-base inputs are listed explicitly in RESULTS.json; none is counted as a pass.','',
        'All initial attempts remain retained in heldout/. If retries were needed, heldout_retry/ and retry_protocol.json retain the unchanged-settings retry outcomes and selected inputs; only a complete retry replaces an incomplete input in audit scoring. No guard setting was changed. Invalid bases and incomplete inputs remain explicit and are not counted as successful validation.','', '## Runtime','', '| Policy | Summed warm median seconds | Exhaustive / policy | Runtime saving |','|---|---:|---:|---:|']
    for p in policies:
        t=timings[p];lines.append(f'| {p} | {t["sum_per_input_warm_medians_seconds"]:.6f} | '+(f'{t["speedup"]:.3f}x | {100*t["runtime_saving_fraction"]:.2f}%' if p!='exhaustive' and t.get('speedup') is not None else '1.000x | 0%' if p=='exhaustive' else 'N/A | N/A')+' |')
    lines+=['','Three rotating-order repetitions were run serially. Repetition 1 is excluded from warmed timing. Filter/predictor overhead, exact evaluation and validation are included; serialization and disk I/O are excluded. These finite, synthetic-network measurements do not establish deployment safety or a large-network speedup. A negative saving is reported as a slowdown, not omitted.','',
        '![Qualification and runtime](qualification.png)','',
        '## Evidence and reproduction','',f'Independent exact-state replay checked {audit["replayed_states"]} states, with {len(audit["discrepancies"])} discrepancies. Accepted exact-state control regimes: `{json.dumps(audit["accepted_control_regimes"],sort_keys=True)}`.','',
        'The previous small-network study and pre-P2 source archive remain in ../p2_02_droop_guard/. Its guard/source identity is retained, and this study uses the same numerical guard. The copied frozen_discovery/RESULTS.json refers to that previous known replay, not new scale-study evidence. plan.json and frozen.json retain the fresh partition and frozen source/code/dependency identities; heldout/ and heldout_retry/ contain every input, base, result and timing record. Guard defaults remain disabled. S2 is unchanged.','',
        '```sh','study_out=artifacts/p2_02_scale_guard_reproduction','mkdir -p "$study_out/frozen_discovery"','cp artifacts/p2_02_droop_guard/frozen_discovery/RESULTS.json "$study_out/frozen_discovery/RESULTS.json"','julia --project=. examples/p2_02_scale_qualification.jl plan "$study_out"','julia --project=. examples/p2_02_scale_qualification.jl freeze "$study_out"','# Standing fixed-equipment configuration is authorized; record it for the run:','JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=. examples/p2_02_scale_qualification.jl run "$study_out" confirmed-fixed-controls','# If any input is incomplete, retain bounded retries separately:','JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=. examples/p2_02_scale_retry_incomplete.jl "$study_out"','julia --project=. examples/p2_02_scale_audit.jl "$study_out"','python3 examples/report_p2_02_scale.py "$study_out"','```','',
        'Use fresh directories for a new campaign. The plotting report requires Matplotlib. A new policy following held-out failures needs a new independent holdout; these cases must not be reused as unseen validation after tuning.']
    lines+=['','## Scaling and predictor overhead','',
        '| Buses | Complete inputs | Guarded screened / total | Guarded misses | Guarded seconds | Exhaustive seconds | Guarded filter seconds | Saving |',
        '|---|---:|---:|---:|---:|---:|---:|---:|']
    for row in per_size:
        c=row['counts']['guarded']; saving=row['guarded_runtime_saving_fraction']
        label=f'{100*saving:.2f}%' if saving is not None else 'N/A'
        lines.append(f"| {row['buses']} | {row['complete_inputs']} | {c['screened']} / {c['total']} | {c['misses']} | {row['timings']['guarded']:.6f} | {row['timings']['exhaustive']:.6f} | {row['filter_seconds']['guarded']:.6f} | {label} |")
    lines+=['','![Runtime and filter overhead by cohort](scaling.png)','','Zero misses with no screened outages reflects exhaustive routing and does not demonstrate useful screening. Timing differences use two warmed repetitions per input; no confidence interval or significance claim is made.','', 'Filter time includes the dense predictor and legacy risk checks. It is part of total elapsed time, not subtracted. A per-size negative saving is a slowdown. Sizes with incomplete inputs do not establish full coverage. Network size, deadband width and anchor regime vary across cohorts, so size alone does not explain differences. The 12/24/48-bus cases are synthetic, so this study does not qualify IEEE or production networks.','',
        'Configuration: fixed supplied taps and shunts; zero equipment movement; frozen shared droop; preventive equal-weight active response.']
    if 'guarded_routing' in result:
        lines+=['','## Guarded routing reasons','', '| Buses | Reason | Outages |','|---|---|---:|']
        for size in sorted(set(size_by_id.values())):
            reasons={}
            for r in result['guarded_routing']:
                if size_by_id[r['id']]==size:
                    for name,count in r['reasons'].items():reasons[name]=reasons.get(name,0)+count
            for name,count in sorted(reasons.items()):lines.append(f'| {size} | {name} | {count} |')
        lines+=['','Reasons are the saved first-repetition decisions; screened sets were checked across all three repetitions. Prediction uncertainty always escalates to exact evaluation.']
    anchor_path=out/'anchor_audit.json'
    if anchor_path.exists():
        anchors=json.loads(anchor_path.read_text())['rows']
        rejected=[r for r in anchors if not r['comparison_complete']]
        lines+=['','## Rejected or incomplete anchor attempts','', '| Input | Attempt | Native status | Physical valid | Error |','|---|---|---|---|---|']
        for r in rejected:
            valid=r['physical_validation']['valid'] if r['physical_validation'] is not None else 'no state'
            lines.append(f"| {r['id']} | {r['attempt']} | {r['termination_status']} | {valid} | {r['error']} |")
        if not rejected:lines.append('| None | — | — | — | — |')
        lines+=['','Anchor residuals, margins and violations are retained in anchor_audit.json. Local infeasibility or a time limit is not a global infeasibility certificate. No case bounds, equipment policy or guard settings were changed to repair invalid anchors.']
    (out/'REPORT.md').write_text('\n'.join(lines)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ['families','timings','unassessed_inputs','accepted_control_regimes','guarded_routing','per_size']}))
if __name__=='__main__':report(Path(sys.argv[1]).resolve())
