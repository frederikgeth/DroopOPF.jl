"""Summarize fresh P2 evidence; do not equate solver failure with infeasibility."""
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'artifacts/p2_s2_implementation_20261022'
load=lambda p:json.loads(p.read_text())
def timings(path):
    records=[load(p)['record'] for p in path.rglob('summary.json') if 'record' in load(p)]
    return dict(optimizer_calls=len(records),build_seconds=sum(r['build_seconds'] for r in records),solve_seconds=sum(r['solve_seconds'] for r in records),
                peak_model_variables=max((r['variables'] for r in records),default=0),
                timing_scope='sum of measured build/solver wall seconds; excludes audits, I/O and orchestration; single pass including compilation')
results={}
for size in (14,500):
    p=OUT/str(size);summary=p/'progressive/summary.json'
    result=dict(progressive=load(summary) if summary.exists() else {'status':'running'},timings=timings(p/'progressive'))
    if size==14:
        full=load(p/'full/summary.json');result['full']=full;result['full_timings']=timings(p/'full')
        rounds=result['progressive'].get('rounds',[])
        if rounds and result['progressive'].get('accepted'):
            a=full['record']['objective'];b=rounds[-1]['master']['record']['objective']
            result['relative_objective_difference']=(b-a)/abs(a)
            result['quality_interpretation']='descriptive local-solution comparison; no post-hoc tolerance used to declare optimal equivalence'
    else:
        result['full']={'status':'not_run_resource_bound','required_states':390,'max_states':12,'physical_infeasibility_proven':False}
    cross=p/'final-cross-file-audit.json'
    if cross.exists():result['final_cross_file_audit']=load(cross)
    results[str(size)]=result
result={'scope':'Initial S1-calibrated, exact-S2 P2 implementation','cases':results,'p2_closed':False,'s2_resumed':False,
        'audit_tests':load(OUT/'audit-tests.json'),
        'limitations':['500-bus 105% feasibility pilot, not multi-demand or full S2 priority optimization',
                       'connected outages only; no full-N-1/islanding claim','continuous taps and shunt susceptances; no switching/timing or transient certification',
                       'known S2 warm starts; no unseen-start, held-out-demand or repeatable speedup qualification']}
(OUT/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:{'status':v['progressive']['status'],'calls':v['timings']['optimizer_calls']} for k,v in results.items()},indent=2))

lines=["# Initial P2 implementation on S1/S2 networks", "", "Fresh exact-S2 numerical evidence. P2 remains open; the source S2 campaign remains paused.", "", "| Case | Progressive result | Completed rounds | Optimizer calls | Build / solve seconds |", "|---|---|---:|---:|---:|"]
for size,r in results.items():
    t=r['timings'];lines.append(f"| {size} | {r['progressive']['status']} | {len(r['progressive'].get('rounds',[]))} | {t['optimizer_calls']} | {t['build_seconds']:.2f} / {t['solve_seconds']:.2f} |")
lines += ["", "Timings sum all primary/retry calls and scans. Audits, I/O and orchestration are excluded; these are single-pass development measurements with known S2 starts.", "", "The 14-bus full-enumeration reference includes 125 states (five demands × base plus 24 outages). Both its native solve and independent audit passed."]
f=results['14']['full_timings'];lines.append(f"Its build / solve times were {f['build_seconds']:.2f} / {f['solve_seconds']:.2f} seconds.")
if 'relative_objective_difference' in results['14']:
    lines.append(f"The final progressive nominal loss differs by {100*results['14']['relative_objective_difference']:.4f}% from this local reference. No global-optimality equivalence or speedup is certified.")
if 'final_cross_file_audit' in results['500']:
    c=results['500']['final_cross_file_audit'];lines += ["", f"Final 500-bus replay verified {c['unique_validated_states']} unique states, a common controller and preventive base, and a maximum AC balance residual of {c['max_balance_residual_pu']:.3g} pu. Maximum permitted demand response used was {c['max_dr_mw']:.4f} MW; shedding remained zero."]
lines += ["", "The 500-bus pilot uses the S2 independent 105% demand contract, with zero shedding and permitted DR. Its full 390-state master was not attempted under the declared 12-state budget. This configured resource boundary does not prove physical infeasibility or hardware exhaustion.", "", "Controls: S2 corrective taps/banks, absolute bounds without extra movement budgets; continuous susceptance; one shared droop design; exact stored Pmax proportional response. The 14-bus objective is nominal loss; the 500-bus objective is feasibility only. Further S2 resource/loss priorities and multi-demand testing remain outstanding.", "", "Validation: independent original-network AC/equipment/response replay, exact outage coverage and cross-file shared-controller/base checks. Deliberate corruptions are recorded in `audit-tests.json`. Final per-case coverage is recorded in `final-cross-file-audit.json`.", "", "## Remaining qualification", ""]
lines += ['- '+s+'.' for s in result['limitations']]
lines += ["", "Sources and runner snapshots are recorded in `manifest.json` and `source_snapshot/`. The original protocol records setup-time hashes; `execution-notes.json` identifies development fixes. Native failure statuses and every attempted witness are retained."]
(OUT/'REPORT.md').write_text('\n'.join(lines)+'\n')
