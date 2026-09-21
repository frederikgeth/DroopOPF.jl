"""Warm-start comparisons in physical units; retain unsuccessful attempts."""
from pathlib import Path
import json, shutil
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
root=Path("artifacts/s1_warmstarts")
rows=json.loads((root/"summary.json").read_text())
selected=json.loads((root/"selection.json").read_text())
assert len(rows)==16
fig,axes=plt.subplots(2,2,figsize=(12,8),layout="constrained")
for ax,selection in zip(axes.flat,selected):
    group=[r for r in rows if r['name'] in selection['attempts']]
    ax.bar(range(4),[r.get('iterations',0) for r in group],color=['#238b65' if r['valid'] else '#bd4545' for r in group])
    ax.set_xticks(range(4),['Source','Primal','Warm / zero dual','Warm / saved dual'],rotation=12,fontsize=8)
    ax.set_title(f"IEEE {selection['buses']} | load {selection['load_factor']}")
    ax.set_ylabel('Iterations');ax.set_ylim(0,1250)
    for i,row in enumerate(group):ax.text(i,row.get('iterations',0)+15,(row.get('status','ERROR').replace('_','\n')+f"\n{row.get('iterations','?')} iter"),ha='center',va='bottom',fontsize=7)
fig.suptitle('Restart comparison: green = validated; red = rejected')
for ext in ('png','pdf'):fig.savefig(root/f'warmstarts.{ext}',dpi=160)
plt.close(fig)
fig,axes=plt.subplots(2,2,figsize=(12,8),layout="constrained")
for ax,selection in zip(axes.flat,selected):
    for name in selection['attempts']:
        detail=json.loads((root/f'{name}-diagnostics.json').read_text())
        trace=[t for t in detail['trace'] if 'unscaled_stationarity' in t]
        if trace:ax.plot([t['iteration'] for t in trace],[max(t['unscaled_stationarity'],1e-16) for t in trace],label=detail['tags']['mode'],marker='.' if len(trace)<3 else None)
    ax.set_yscale('log');ax.set_xlabel('Iterations within each attempt')
    ax.set_ylabel('Unscaled stationarity residual');ax.set_title(f"IEEE {selection['buses']} | load {selection['load_factor']}")
    ax.legend(fontsize=8)
fig.suptitle('Ipopt stationarity histories (plot floor 1e-16); independent physics checked separately')
for ext in ('png','pdf'):fig.savefig(root/f'stationarity.{ext}',dpi=160)
plt.close(fig)
lines=['# S1 primal/dual restart checkpoint' ,'',f"**{sum(r['valid'] for r in rows)}/16 attempts validate, including four source attempts. S1 remains open.**",'',
'All three restart arms use the same persisted terminal iterate from the source solve, on the same formulation. Primal restarts use ordinary initialization; both warm-start arms share identical warm-start options, with either zero or saved dual multipliers. The zero-dual arm separates the effect of warm-start initialization from retaining multipliers. Failed source iterates are numerical seeds only, never accepted as feasible solutions.', '',
'Each attempt retains the 1000-iteration/60 CPU-second budget, epsilon 1e-6, original objective, zero bound relaxation and unchanged physical tolerances. A source plus a restart has a larger cumulative budget than the source alone. A separate uninterrupted equal-budget comparison below tests the one failed source case. These dependent probes are not independent multistart trials or isolated performance benchmarks.', '',
'The start JSON contains builder defaults; restart tags point to the persisted seed that overrides them. Seeds store JuMP/MOI primal and dual values, including variable bounds and legacy nonlinear constraints. A model-layout signature, explicit formulation context, dimensions and finite-value checks guard application. This is an example-level, same-formulation Ipopt experiment; transfer across cases, smoothing levels, model revisions, or solvers is not supported. It does not preserve the full internal Ipopt state, barrier history or factorization.', '',
'![Warm-start results](warmstarts.png)','', '![Stationarity histories](stationarity.png)', '',
'| Attempt | Status | Valid | Iterations | Valid objective | Physical failures |','|---|---|---|---|---|---|']
for row in rows:
    p=row.get('physical')
    why=', '.join(p['violations']) if p else 'not evaluated'
    obj=f"{row['objective']:.10g}" if row['valid'] else '—'
    lines.append(f"| [{row['name']}]({row['name']}-diagnostics.json) | {row.get('status','ERROR')} | {row['valid']} | {row.get('iterations','—')} | {obj} | {why or 'none'} |")
lines += ['', '## Declared candidate selection', '', 'Select the lowest objective among fully validated source/restart attempts; if none validate, retain an unresolved result. This experimental selection rule does not certify global optimality or establish a production restart policy.', '', '| Case | Selected attempt | Persisted seed |', '|---|---|---|']
for s in selected:lines.append(f"| {s['buses']} / demand ×{s['load_factor']} | {s['selected'] or 'Unresolved'} | [Seed](public{s['buses']}-load{s['load_factor']}-seed.json) |")
equal_root=Path('artifacts/s1_equal_budget')
equal=json.loads((equal_root/'summary.json').read_text())[0]
source=next(r for r in rows if r['name']=='public300-load1.05-source')
recoveries=[r for r in rows if r['buses']==300 and r['tags']['load_factor']==1.05 and r['tags']['mode']!='source']
fig,ax=plt.subplots(figsize=(9,5),layout='constrained')
comparison=[equal]+recoveries
counts=[equal['iterations']]+[source['iterations']+r['iterations'] for r in recoveries]
ax.bar(range(4),counts,color=['#238b65' if r['valid'] else '#bd4545' for r in comparison])
ax.set_xticks(range(4),['Uninterrupted','Source + primal','Source + warm / zero dual','Source + warm / saved dual'],rotation=10,fontsize=8)
ax.set_ylabel('Total iterations including source solve');ax.set_ylim(0,2300)
ax.set_title('Stressed IEEE 300: equal total budget of 2000 iterations / 120 CPU seconds')
for i,(count,row) in enumerate(zip(counts,comparison)):ax.text(i,count+20,f"{count}\n{'Validated' if row['valid'] else 'Rejected'}",ha='center')
for ext in ('png','pdf'):fig.savefig(root/f'equal_budget.{ext}',dpi=160)
plt.close(fig)
for path in equal_root.glob('*-diagnostics.json'):shutil.copy2(path,root/path.name)
lines += ['', '## Equal-total-budget comparison', '', '![Equal total budget](equal_budget.png)', '',
    f"The uninterrupted stressed IEEE 300 solve uses 2000 iterations and 120 CPU seconds, matching the maximum combined budget of source plus one restart. It ends with {equal['status']} and validation={equal['valid']}. The source objective trace matches the shared initial portion exactly. Zero-dual warm initialization validates in 1000+40 iterations; ordinary primal restart validates in 1000+491. Saved-dual restart fails after 1000+1000. [Uninterrupted diagnostics](public300-load1.05-uninterrupted-diagnostics.json).", '',
    'This is evidence for recovery on this retained case, not statistical evidence of universal reliability. Saved duals preserve validated solutions on the other three cases, but should not be assumed useful after a failed solve. Validation and finite-value checks must control acceptance; termination status alone is insufficient.', '',
    '## Interpretation', '', 'The matrix validates 9/16 attempts. Saved-dual restarts validate in 3, 3 and 55 iterations for the three validated sources. The failed source is recovered by resetting multipliers, and a longer uninterrupted solve still fails. This motivates testing a status-dependent restart policy, while retaining a known validated incumbent and accepting candidates only after independent physical checks. The current experiment tries all arms; it does not yet implement or validate an automatic production policy.', '']
lines += ['', '## Remaining work', '', 'Explicit variable normalization, broader start variation, broader equal-total-budget comparisons and a reliable restart policy remain open. M9 is not unlocked. Equipment equations, physical bounds, objective and validation tolerances are unchanged.', '']
text='\n'.join(lines);(root/'report.md').write_text(text)
assets=Path('docs/src/assets/s1_warmstarts');assets.mkdir(parents=True,exist_ok=True)
for path in root.glob('*'):
    if path.suffix in ('.png','.pdf') or path.name in ('summary.json','selection.json') or path.name.endswith(('-diagnostics.json','-seed.json')):shutil.copy2(path,assets/path.name)
text=text.replace('](equal_budget.png)','](assets/s1_warmstarts/equal_budget.png)').replace('](public300-load1.05-uninterrupted-diagnostics.json)','](assets/s1_warmstarts/public300-load1.05-uninterrupted-diagnostics.json)')
text=text.replace('](warmstarts.png)','](assets/s1_warmstarts/warmstarts.png)').replace('](stationarity.png)','](assets/s1_warmstarts/stationarity.png)')
for sel in selected:
    seed=f"public{sel['buses']}-load{sel['load_factor']}-seed.json"
    text=text.replace(f']({seed})',f'](assets/s1_warmstarts/{seed})')
for row in rows:text=text.replace(f"]({row['name']}-diagnostics.json)",f"](assets/s1_warmstarts/{row['name']}-diagnostics.json)")
Path('docs/src/s1_warmstarts.md').write_text(text)
