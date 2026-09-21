"""Policy outcomes with paired initial/final acceptance and all attempts retained."""
from pathlib import Path
import json, shutil
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
from matplotlib.patches import Patch
root=Path('artifacts');out=root/'s1_restart_policy';out.mkdir(exist_ok=True)
folders={'ipopt':root/'s1_policy_ipopt','madnlp':root/'s1_policy_madnlp'}
data={solver:json.loads((folder/'summary.json').read_text()) for solver,folder in folders.items()}
assert all(len(rows)==12 for rows in data.values())
rows=[r for items in data.values() for r in items]
groups=[(118,1.),(118,1.05),(300,1.),(300,1.05)]
columns=[(s,start) for s in data for start in ('anchor','flat_low','flat_high')]
fig,ax=plt.subplots(figsize=(13,7),layout='constrained');matrix=np.zeros((4,6))
for i,(n,load) in enumerate(groups):
 for j,(solver,start) in enumerate(columns):
    r=next(r for r in data[solver] if r['buses']==n and r['tags']['load_factor']==load and r['tags']['start']==start)
    matrix[i,j]=1 if r['valid'] and len(r['attempts'])==1 else 2 if r['valid'] else 0
    end=r['events'][-1]
    label={'accept':'Accepted','diagnose_validation_failure':'Validation failure','budget_exhausted':'Budget exhausted','retry_limit_reached':'Retry exhausted','termination_not_retryable':'Other termination','no_compatible_finite_seed':'No seed','attempt_error':'Error'}.get(end,end)
    ax.text(j,i,f"{label}\n{len(r['attempts'])} attempt(s)\n{r['iterations']} iterations",ha='center',va='center',fontsize=8)
ax.imshow(matrix,cmap=ListedColormap(['#edaaa6','#a6d5c8','#a9c7ef']),vmin=0,vmax=2,aspect='auto')
ax.set_xticks(range(6),[f'{s}\n{start}' for s,start in columns]);ax.set_yticks(range(4),[f'IEEE {n} / load {load}' for n,load in groups])
ax.set_title('Bounded policy: at most one multiplier-reset recovery, unchanged physical acceptance')
fig.legend(handles=[Patch(color=c,label=l) for c,l in [('#edaaa6','Unresolved'),('#a6d5c8','Accepted first attempt'),('#a9c7ef','Recovered')]],loc='outside lower center',ncol=3)
for ext in ('png','pdf'):fig.savefig(out/f'policy_matrix.{ext}',dpi=160)
plt.close(fig)
fig,axes=plt.subplots(1,2,figsize=(11,5),layout='constrained')
for ax,(solver,group) in zip(axes,data.items()):
    first=sum(bool(r['attempts']) and r['attempts'][0]['valid'] for r in group)
    final=sum(r['valid'] for r in group)
    ax.bar(['Initial attempt','After bounded policy'],[first,final],color=['#7099a6','#238b65'])
    ax.set_ylim(0,13);ax.set_ylabel('Validated cases out of 12');ax.set_title(solver)
    for i,value in enumerate([first,final]):ax.text(i,value+.2,str(value),ha='center')
for ext in ('png','pdf'):fig.savefig(out/f'policy_acceptance.{ext}',dpi=160)
plt.close(fig)
lines=['# S1 bounded restart policy','',
'The runner accepts the first independently validated solution and stops. A finite, compatible iterate after an iteration limit, time limit, interruption or slow progress may receive one multiplier-reset recovery. Solver convergence with failed physical/policy validation stops for diagnosis; other termination reasons and missing seeds are unresolved. No other initialization or backend switch occurs silently. A failed attempt is never returned as an accepted design. This is experimental execution logic outside the core equipment formulation.', '',
'Each policy run has a total allowance of 2000 iterations and 120 wall seconds, with at most 1000 iterations and 60 seconds per attempt. The recovery receives only remaining budget. Both adapters check wall deadlines at iteration callbacks; model construction, a long solver step and validation cannot be preempted, so this is a cooperative deadline, not a hard process timeout. Elapsed time and overruns are retained. Native Ipopt CPU and MadNLP wall limits are supplementary. Runs include compilation and some concurrent regression work; no isolated runtime ranking is claimed.', '',
'Context hashes include full physical case data, declared controls, smoothing, backend and version. A model-layout signature, array dimensions and finite-value checks are also required. Persisted recovery seeds override the builder defaults recorded in start files. Seeds contain numerical iterates, not assertions of physical validity. The policy preserves an accepted result by returning immediately; it does not perform optional objective polishing or import an external incumbent.', '',
'Ipopt recovery uses warm-start initialization with zero constraint and bound dual starts. MadNLP recovery sets zero constraint multipliers and dual_initialized=true; the installed solver initializes bound multipliers internally to one. This behavior was checked in a native callback test. The two adapters are explicit solver-specific implementations, not identical numerical algorithms. Full saved-bound-multiplier restoration in MadNLP is not implemented.', '',
'![Policy matrix](policy_matrix.png)','', '![Acceptance](policy_acceptance.png)', '',
'| Solver | Initial valid / 12 | Final valid / 12 | Recovered | Attempts |', '|---|---|---|---|---|']
for solver,group in data.items():
    first=sum(bool(r['attempts']) and r['attempts'][0]['valid'] for r in group);final=sum(r['valid'] for r in group)
    lines.append(f"| {solver} | {first} | {final} | {final-first} | {sum(len(r['attempts']) for r in group)} |")
lines += ['', '## Complete policy ledger', '', '| Case / solver / start | Outcome | Attempts | Total iterations | Final decision | Accepted objective |', '|---|---|---|---|---|---|']
for r in rows:
    chosen=next((a for a in r['attempts'] if a['name']==r['selected']),None)
    objective=f"{chosen['objective']:.10g}" if chosen else '—'
    lines.append(f"| [{r['name']}]({r['name']}-policy.json) | {'Accepted' if r['valid'] else 'Unresolved'} | {len(r['attempts'])} | {r['iterations']} | {r['events'][-1]} | {objective} |")
lines += ['', '## Every attempt and physical failure category', '', '| Attempt | Native status | Valid | Physical failures |', '|---|---|---|---|']
for r in rows:
 for a in r['attempts']:
    p=a.get('physical');why=', '.join(p['violations']) if p else 'not evaluated'
    lines.append(f"| [{a['name']}]({a['name']}-diagnostics.json) | {a.get('status','ERROR')} | {a['valid']} | {why or 'none'} |")
lines += ['', '## Remaining acceptance gate', '',
'This paired matrix measures recovery within the declared starts and budget. It does not establish global optimality, universal convergence or scalability under contingencies. The policy stops at the first validated solution, so objective-quality comparisons need a separately declared study budget. No equipment equations, objective terms or physical tolerances changed. Variable normalization and broader reliability/quality studies remain open before M9. CCOpt is not part of this smooth joint-design policy.', '']
for solver,folder in folders.items():
 for p in folder.glob('*.json'):
    if p.name!='summary.json':shutil.copy2(p,out/p.name)
(out/'summary.json').write_text(json.dumps(rows,indent=2)+'\n')
text='\n'.join(lines);(out/'report.md').write_text(text)
assets=Path('docs/src/assets/s1_restart_policy');assets.mkdir(parents=True,exist_ok=True)
for p in out.glob('*'):
 if p.suffix in ('.json','.png','.pdf'):shutil.copy2(p,assets/p.name)
import re
text=re.sub(r'\]\(([^)]+)\)',lambda m:'](assets/s1_restart_policy/'+m.group(1)+')',text)
Path('docs/src/s1_restart_policy.md').write_text(text)
