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
    status='INCOMPLETE_COVERAGE' if len(inputs)!=24 else 'QUALIFICATION_FAILED' if missed else 'NO_BRANCH_FAILURE_EVIDENCE' if not branch_failures else 'NO_OBSERVED_MISSES_FINITE_SCOPE'
    result=dict(status=status,new_heldout_inputs=len(audit['inputs']),
        complete_inputs=len(inputs),unassessed_inputs=[r for r in audit['inputs'] if not r['complete']],saved_false_screens=saved['original_false_screens'],
        saved_remaining_misses=saved['enhanced_false_screens'],new_heldout_guarded_misses=missed,branch_unresolved=branch_failures,
        families=totals,timings=timings,replayed_states=audit['replayed_states'],replay_discrepancies=len(audit['discrepancies']),
        accepted_control_regimes=audit['accepted_control_regimes'],default_guard_enabled=False,
        limitation='Finite sample only; unresolved solver/physical outcomes are not infeasibility certificates; exhaustive final audit remains mandatory')
    (out/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    fig,axes=plt.subplots(1,2,figsize=(10.5,4.2))
    for k,policy in enumerate(['legacy','guarded']):
        rs=[r for r in totals if r['policy']==policy];axes[0].bar([i+(k-.5)*.35 for i in range(3)],[r['misses'] for r in rs],.35,label=policy)
    axes[0].set_xticks(range(3),['line','transformer','generator']);axes[0].set(ylabel='Screened unresolved outages',title='New held-out false screens');axes[0].legend()
    axes[1].bar(policies,[timings[p]['sum_per_input_warm_medians_seconds'] for p in policies]);axes[1].set(ylabel='Summed per-input warm median time (s)',title='Routing + AC evaluation + validation')
    fig.tight_layout();fig.savefig(out/'qualification.png',dpi=160);plt.close(fig)
    lines=['# P2 02 droop response screening qualification','',f'New held-out result: **{result["status"]}** across {len(inputs)}/{len(audit["inputs"])} completely assessed inputs. Saved false screens reproduced: {saved["original_false_screens"]}; remaining after the guard: {saved["enhanced_false_screens"]}.','',
        '## Frozen comparison contract','',
        'Old discovery and old held-out inputs are known regression evidence. Twenty-four new 7/8-bus inputs were specified and all numerical guard/source settings frozen before any new base or outage solve. Transformer ratios, shunts and droop curves are fixed; the same base state and preventive participation policy are used by all paths. The guard is opt-in and only escalates legacy screened branches. Per-unit reactive headroom uses both generator and controller bounds. A bounded nonlinear AC/droop predictor detects projected voltage/thermal/active/reactive risks and regime changes; uncertainty always goes to exact evaluation. It is not a security certificate.','',
        '## Coverage and misses','', '| Policy | Family | Outages | Screened | Unresolved | Missed unresolved | Missed invalid physical states |','|---|---|---:|---:|---:|---:|---:|']
    for r in totals:lines.append(f'| {r["policy"]} | {r["family"]} | {r["total"]} | {r["screened"]} | {r["unresolved"]} | {r["misses"]} | {r["physical_misses"]} |')
    lines+=['',f'Guarded branch unresolved count: {branch_failures}. Recall is undefined when a family has no unresolved cases. Unresolved means rejection/error or physical invalidity, not proven infeasibility. Classification changes across repetitions are retained and any unresolved exhaustive repetition counts against screening. Incomplete or invalid-base inputs are listed explicitly in RESULTS.json; none is counted as a pass.','',
        'The first initial anchor hit its five-second time limit. Its original output is retained in heldout/. A separate warm-up and retry used the same numerical settings and completed the comparison in heldout_retry/. retry_protocol.json records the orchestration driver and selected input. Audit uses complete retry data for that input; no guard setting was changed.','', '## Runtime','', '| Policy | Summed warm median seconds | Exhaustive / policy | Runtime saving |','|---|---:|---:|---:|']
    for p in policies:
        t=timings[p];lines.append(f'| {p} | {t["sum_per_input_warm_medians_seconds"]:.6f} | '+(f'{t["speedup"]:.3f}x | {100*t["runtime_saving_fraction"]:.2f}%' if p!='exhaustive' and t.get('speedup') is not None else '1.000x | 0%' if p=='exhaustive' else 'N/A | N/A')+' |')
    lines+=['','Three rotating-order repetitions were run serially. Repetition 1 is excluded from warmed timing. Filter/predictor overhead, exact evaluation and validation are included; serialization and disk I/O are excluded. These finite, small-network measurements do not establish deployment safety or a large-network speedup. A negative saving is reported as a slowdown, not omitted.','',
        '![Qualification and runtime](qualification.png)','',
        '## Evidence and reproduction','',f'Independent exact-state replay checked {audit["replayed_states"]} states, with {len(audit["discrepancies"])} discrepancies. Accepted exact-state control regimes: `{json.dumps(audit["accepted_control_regimes"],sort_keys=True)}`.','',
        'The unchanged pre-P2 source is archived against M10.3 hashes in pre_change_source/. Saved inputs/reports remain protected by preservation.json. plan.json and frozen.json retain the fresh partition and frozen source/code/dependency identities; heldout/ and heldout_retry/ contain every input, base, result and timing record. Guard defaults remain disabled. S2 is unchanged.','',
        '```sh','julia --project=. examples/p2_02_qualification.jl plan artifacts/p2_02_droop_guard','julia --project=. examples/p2_02_saved_replay.jl artifacts/p2_02_droop_guard/frozen_discovery','julia --project=. examples/p2_02_qualification.jl freeze artifacts/p2_02_droop_guard','# After confirming fixed-equipment controls for the campaign:','julia --project=. examples/p2_02_qualification.jl run artifacts/p2_02_droop_guard confirmed-fixed-controls','julia --project=. examples/p2_02_audit_heldout.jl artifacts/p2_02_droop_guard','python3 examples/report_p2_02.py artifacts/p2_02_droop_guard','```','',
        'Use fresh directories for a new campaign. The plotting report requires Matplotlib. A new policy following held-out failures needs a new independent holdout; these cases must not be reused as unseen validation after tuning.']
    (out/'REPORT.md').write_text('\n'.join(lines)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ['families','timings','unassessed_inputs','accepted_control_regimes']}))
if __name__=='__main__':report(Path(sys.argv[1]).resolve())
