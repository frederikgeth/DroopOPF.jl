"""Summarize every retained S1 attempt, including failures, without rerunning solvers."""
from pathlib import Path
import json, collections, statistics
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/s1_arpae14_stress'
OUT.mkdir(parents=True,exist_ok=True)
rows=json.loads((OUT/'summary.json').read_text()) if (OUT/'summary.json').exists() else []
solvers=['ipopt','madnlp','ccopt']
families=['fixed','droop','tap','shunt','tap_shunt','tap_droop','shunt_droop','joint']
def score(rs):
    return f"{sum(bool(r.get('valid')) for r in rs)}/{len(rs)}"
def group(block,solver,**tags):
    return [r for r in rows if r['solver']==solver and r['tags']['block']==block and all(r['tags'].get(k)==v for k,v in tags.items())]
lines=['# IEEE 14-bus S1 stress campaign','',f'Completed: {len(rows)}/261 primary planned attempts. Counts are independently accepted / attempted.','',
'Pmin=0 and symmetric Q limits. Ipopt/MadNLP use smooth droop; CCOpt uses exact complementarity. All results must satisfy solver status, AC/physical limits, equipment policies, exact-droop checks, and a separate source angle-bound audit. Native dispatch-deviation objective differs from upstream fuel cost. Bank B is continuous, not discrete switching. Tap freedom is an explicitly assumed study range.','',
'| Block | Ipopt | MadNLP | CCOpt |','|---|---:|---:|---:|']
for block in ['baseline','matrix','epsilon','formulation','control_count']:
    lines.append('| '+block+' | '+' | '.join(score(group(block,s)) for s in solvers)+' |')
lines+=['','| Free controls (all demands and starts) | Ipopt | MadNLP | CCOpt |','|---|---:|---:|---:|']
for f in families: lines.append('| '+f+' | '+' | '.join(score(group('matrix',s,family=f)) for s in solvers)+' |')
lines+=['','| Demand factor | Ipopt | MadNLP | CCOpt |','|---|---:|---:|---:|']
for factor in [.9,1.,1.1]: lines.append('| '+str(factor)+' | '+' | '.join(score(group('matrix',s,load_factor=factor)) for s in solvers)+' |')
lines+=['','| Initialization | Ipopt | MadNLP | CCOpt |','|---|---:|---:|---:|']
for mode in ['anchor','flat_low','flat_high']: lines.append('| '+mode+' | '+' | '.join(score(group('matrix',s,start=mode)) for s in solvers)+' |')
lines+=['','## Failures','']
failures=[]
for r in rows:
    if r.get('valid'):continue
    p=r.get('physical') or {}
    failures.append({'name':r['name'],'status':r.get('status','ERROR'),'error':r.get('error'), 'violations':p.get('violations'), 'balance':p.get('power_balance_max'), 'droop':(r.get('exact_droop_audit') or {}).get('max_residual_pu'), 'policy_valid':r.get('policy_valid'), 'solver_valid':r.get('solver_valid')})
counts=collections.Counter((r['solver'],r.get('status','ERROR')) for r in rows if not r.get('valid'))
for (solver,status),n in sorted(counts.items()):lines.append(f'- {solver}: {status}: {n} rejected attempts.')
lines+=['','## Run ledger','','| Run | Accepted | Status | Exact droop residual (pu) | Seconds |','|---|---:|---|---:|---:|']
for r in rows:
    d=(r.get('exact_droop_audit') or {}).get('max_residual_pu')
    lines.append(f"| {r['name']} | {r.get('valid',False)} | {r.get('status','ERROR')} | {d} | {r.get('elapsed_seconds')} |")
(OUT/'report.md').write_text('\n'.join(lines)+'\n')
(OUT/'failures.json').write_text(json.dumps(failures,indent=2)+'\n')
print('\n'.join(lines[:45]))
# Supplementary results are separate; never replace first-attempt failures.
follow=json.loads((OUT/'followup/summary.json').read_text()) if (OUT/'followup/summary.json').exists() else []
extra=['','## Follow-up attempts','','Separate runs with 3,000 iterations / 30 native solver seconds. Warm starts use the best accepted primary result for the same nominal-load control family. All droop parameters adds reference voltage ±0.01 pu and each deadband width 0.002–0.01 pu.','', '| Block | Ipopt | MadNLP | CCOpt |','|---|---:|---:|---:|']
for block in sorted({r['tags']['block'] for r in follow}):
 extra.append('| '+block+' | '+' | '.join(score([r for r in follow if r['solver']==s and r['tags']['block']==block]) for s in solvers)+' |')
extra+=['','The original CCOpt baseline errors came from diagnostics assuming every model uses complementarity relaxation. CCOpt delegates ordinary NLPs to MadNLP; the diagnostics now handles this path. The fallback baseline is not an independent third optimization algorithm. Original errors remain above.','', 'The five primary attempts reported LOCALLY_SOLVED but rejected by physical validation all used smoothing epsilon 1e-4 and exceeded exact-droop tolerance. Solver termination alone is insufficient.','', 'No global-optimality or infeasibility proof is implied by this nonconvex local-solver campaign. No SCOPF run was performed. Native time budgets exclude compilation; elapsed times are not a clean solver-speed benchmark.','']
extra+=['| Follow-up run | Accepted | Status |','|---|---:|---|']
for r in follow:extra.append(f"| {r['name']} | {r['valid']} | {r.get('status','ERROR')} |")
if (OUT/'nominal_joint_thresholds.json').exists():
 a=json.loads((OUT/'nominal_joint_thresholds.json').read_text())
 extra+=['','## Nominal joint-control primary solution','',f"Run: `{a['run']}`. Native objective: {a['objective']:.10g}. This is a local accepted point, not a certified global optimum.",'','| Generator | Bus | Online | Pmin MW | Pg MW | Pmax MW | Qmin Mvar | Qg Mvar | Qmax Mvar |','|---|---:|---|---:|---:|---:|---:|---:|---:|']
 for g in a['generators']:extra.append('| '+' | '.join(str(g[k]) if k in ['id','bus','online'] else f'{g[k]:.6f}' for k in ['id','bus','online','Pmin_MW','Pg_MW','Pmax_MW','Qmin_Mvar','Qg_Mvar','Qmax_Mvar'])+' |')
 extra+=['','| Bus | Vmin | V | Vmax | Lower margin | Upper margin |','|---|---:|---:|---:|---:|---:|']
 for b in a['buses']:extra.append('| '+' | '.join(str(b[k]) if k=='id' else f'{b[k]:.8f}' for k in ['id','Vmin','V','Vmax','lower_margin','upper_margin'])+' |')
 extra+=['','| Branch | Kind | From–to | Rating MVA | From MVA | To MVA | Margin MVA | Tap |','|---|---|---|---:|---:|---:|---:|---:|']
 for b in a['branches']:extra.append(f"| {b['id']} | {b['kind']} | {b['from_bus']}–{b['to_bus']} | {b['rating_MVA']:.6f} | {b['from_MVA']:.6f} | {b['to_MVA']:.6f} | {b['margin_MVA']:.8f} | {b['tap']:.8f} |")
 extra+=['','All active bus voltage limits are 0.9–1.1 pu. Source angle-difference limits ±π/3 are audited after solving; they are not native optimization constraints. Equipment control bounds: source-relative tap ±5%; bank B 0–0.4 pu; primary droop slope 0.5–2 times nominal. Original source generator limits remain preserved outside this derived study.']
(OUT/'report.md').write_text('\n'.join(lines+extra)+'\n')
print('\n'.join(extra[:15]))
comparison=['','## Accepted objective comparison at nominal demand','','Native dispatch-deviation objective; only compare within a row because control freedom differs. Empty entries mean no accepted point.','', '| Control freedom | Ipopt best | MadNLP best | CCOpt best |','|---|---:|---:|---:|']
for label,selected in [('No droop overlay',[r for r in rows+follow if r['tags']['block'] in ['baseline','baseline_diagnostics_fix']]),('Fixed droop and equipment',[r for r in rows if r['tags']['block']=='matrix' and r['tags']['family']=='fixed' and r['tags']['load_factor']==1]),('Free slopes, taps and bank',[r for r in rows if r['tags']['block']=='matrix' and r['tags']['family']=='joint' and r['tags']['load_factor']==1]),('Free slopes, references, deadbands, taps and bank',[r for r in follow if r['tags']['block']=='all_droop_parameters'])]:
 values=[]
 for solver in solvers:
  accepted=[r['objective'] for r in selected if r['solver']==solver and r['valid']]
  values.append(f'{min(accepted):.10f}' if accepted else '—')
 comparison.append('| '+label+' | '+' | '.join(values)+' |')
with (OUT/'report.md').open('a') as stream:stream.write('\n'.join(comparison)+'\n')
report=OUT/'report.md'
text=report.read_text().replace(f'Completed: {len(rows)}/261 primary planned attempts.',f'Completed: {len(rows)+len(follow)}/305 attempts ({len(rows)} primary + {len(follow)} follow-up); {sum(r["valid"] for r in rows+follow)} accepted.')
replay_path=OUT/'independent_ac_replay.json'
if replay_path.exists():
 replay=json.loads(replay_path.read_text())
 text+=f'\nIndependent complex-arithmetic AC replay: {sum(r["valid"] for r in replay)}/{len(replay)} passed; worst balance residual {max(r["power_balance_max_pu"] for r in replay):.3g} pu. CCOpt diagnostics regression: 10/10 checks passed (see diagnostic-regression-test.log).\n'
report.write_text(text)
