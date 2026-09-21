"""Paired staged-initialization evidence; includes every preparation and final attempt."""
from pathlib import Path
import hashlib,json,shutil,re
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
root=Path('artifacts');out=root/'s1_staged';out.mkdir(exist_ok=True)
for name,digest in json.loads((out/'frozen-baseline.json').read_text()).items():
    assert hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest, name
solvers=('ipopt','madnlp');strategies=('release','load')
baselines={s:{r['name']:r for r in json.loads((root/f's1_policy_{s}'/'summary.json').read_text())} for s in solvers}
runs={(s,t):json.loads((root/f's1_{t}_{s}'/'summary.json').read_text()) for s in solvers for t in strategies}
for (s,t),rs in runs.items():
 assert len(rs)==(12 if t=='release' else 6)
 for r in rs:
  assert all(not a['seed_transferred'] or a['valid'] for a in r['preparations'])
  assert r['valid']==bool(r['final'] and r['final']['valid'])
  charged=sum(a['iterations'] if a.get('iterations') is not None else r['budget']['preparation_cap'] for a in r['preparations'])
  assert r['iterations']==charged+(r['final']['iterations'] if r['final'] else 0)
  assert r['iterations']<=r['budget']['iterations']

def baseline(r):return baselines[r['solver']][r['name'].rsplit('-',1)[0]]
def attempts(r):return r['preparations']+((r['final'] or {}).get('attempts',[]))
def objective(r):
    f=r.get('final',r)
    return next((a['objective'] for a in (f or {}).get('attempts',[]) if a['valid']),None)
def fmt(v):return '—' if v is None else f'{v:.8g}'
lines=['# S1 staged initialization and load continuation','',
'Two separate experiments use the existing physical coordinates and the frozen direct-solve baseline. Equipment equations, objective, limits, smoothing (epsilon 1e-6), and physical validation tolerances are unchanged. These experimental runners do not change the default optimizer API.', '',
'**Control release:** first fix selected taps, banks and all selected droop parameters at their declared initial settings; next free taps and banks while keeping droops fixed; finally free every selected setting to its original design bounds. In this public matrix only droop slopes are design variables. All stages use the target demand.', '',
'**Load continuation:** solve the full joint problem at nominal load, then +2.5%, then the target +5%. This is tested separately from control release. P and Q loads change together; droop references, generator dispatch references, equipment models and bounds remain unchanged.', '',
'Only stages that pass native termination, independent physical checks and controller-policy checks can seed the next stage. Transferred settings must also satisfy the strict initialization domain. Otherwise the last accepted seed (or declared initialization) remains in use. No duals transfer between changed formulations. Failed preparation stages do not establish infeasibility.', '',
'Every workflow shares 2000 iterations and 120 seconds of cooperative wall budget, including preparation. Each preparation receives at most 500 iterations and 30 seconds; the final joint policy receives the remaining budget and permits at most one multiplier-reset recovery. The clock is checked at solver callbacks and cannot preempt construction, factorization or validation. Timing includes compilation and concurrent work and is not an isolated performance comparison. A validated restricted preparation point is retained separately and never counted as a converged final joint design.', '',
'The pinned PGLib IEEE 118/300 cases use the same synthetic overlays as the baseline: respectively 37/35 droops, 11/129 taps and 12/32 banks. Three declared starts are anchor, flat/20% settings, and flat/80% settings. Release has 12 cases per solver; load continuation has the six stressed cases per solver. These are repeated tuning cases, not independent holdout validation.', '',
'![Paired acceptance](acceptance.png)', '',
'| Solver | Strategy | Direct accepted | Staged accepted | Gained / lost cases | Preparation seeds transferred | Iteration / wall overruns |',
'|---|---|---|---|---|---|---|']
fig,axes=plt.subplots(1,2,figsize=(11,4.5),layout='constrained')
for ax,s in zip(axes,solvers):
 vals=[];labels=[]
 for t in strategies:
  rs=runs[s,t];bs=[baseline(r) for r in rs]
  n=len(rs);bv=sum(b['valid'] for b in bs);sv=sum(r['valid'] for r in rs)
  gains=sum(r['valid'] and not b['valid'] for r,b in zip(rs,bs));losses=sum(b['valid'] and not r['valid'] for r,b in zip(rs,bs))
  transfer=sum(a['seed_transferred'] for r in rs for a in r['preparations'])
  over=[sum(r['budget_exceeded'][k] for r in rs) for k in ('iterations','wall')]
  lines.append(f'| {s} | {t} | {bv}/{n} | {sv}/{n} | {gains} / {losses} | {transfer}/{2*n} | {over[0]} / {over[1]} |')
  vals.extend([bv/n*100,sv/n*100]);labels.extend([f'{t}\ndirect ({bv}/{n})',f'{t}\nstaged ({sv}/{n})'])
 ax.bar(range(4),vals,color=['#78909c','#238b65']*2);ax.set_xticks(range(4),labels,fontsize=9)
 ax.set_ylim(0,110);ax.set_ylabel('Validated final designs (%)');ax.set_title(s)
for ext in ('png','pdf'):fig.savefig(out/f'acceptance.{ext}',dpi=160)
plt.close(fig)
lines += ['', '## Paired case ledger', '', '| Case | Direct / staged valid | Total iterations direct / staged | Joint seed | Direct / staged objective | Retained restricted points |', '|---|---|---|---|---|---|']
for (s,t),rs in runs.items():
 for r in rs:
  b=baseline(r);f=r['final'] or {};seed=f.get('tags',{}).get('seed_source','no final solve')
  lines.append(f"| [{r['name']}]({r['name']}-staged.json) | {b['valid']} / {r['valid']} | {b['iterations']} / {r['iterations']} | {seed.replace(r['name'],'stage')} | {fmt(objective(b))} / {fmt(objective(r))} | {len(r['restricted_feasible_fallbacks'])} |")
lines += ['', '## Stage acceptance and failures', '', 'Green denotes independently accepted, orange denotes native convergence rejected by validation, and red denotes other rejected attempts. Gray means no attempt. A green preparation cell does not count as a final joint-design success.', '', '![Stage outcomes](stages.png)', '', '| Attempt | Status | Accepted | Seed transferred | Physical failure categories | Seed transfer error |', '|---|---|---|---|---|---|']
allruns=[r for rs in runs.values() for r in rs]
fig,ax=plt.subplots(figsize=(11,13),layout='constrained');matrix=[]
for r in allruns:
 aa=attempts(r)
 code=lambda a:2 if a['valid'] else 1 if a.get('solver_valid') else 0
 pre=[code(a) for a in r['preparations']];fin=[code(a) for a in (r['final'] or {}).get('attempts',[])]
 matrix.append(pre+[-1]*(2-len(pre))+fin+[-1]*(2-len(fin)))
 for a in aa:
  physical=a.get('physical') or {}
  lines.append(f"| [{a['name']}]({a['name']}-diagnostics.json) | {a.get('status','ERROR')} | {a['valid']} | {a.get('seed_transferred','final stage')} | {', '.join(physical.get('violations',[])) or ('none' if physical else 'not evaluated')} | {a.get('seed_transfer_error','—')} |")
ax.imshow(matrix,aspect='auto',cmap=ListedColormap(['#e2e5e7','#c74b50','#e1a445','#238b65']),vmin=-1,vmax=2)
ax.set_yticks(range(len(allruns)),[r['name'].replace('public','') for r in allruns],fontsize=8)
ax.set_xticks(range(4),['Preparation 1','Preparation 2','Joint initial','Joint recovery'])
ax.set_title('Per-stage results: green accepted · orange validation failure · red rejected')
for ext in ('png','pdf'):fig.savefig(out/f'stages.{ext}',dpi=160)
plt.close(fig)
lines += ['', '## Interpretation and scope', '',
'The paired ledger reports gains and regressions, so a better aggregate count alone is insufficient to promote a default. Objectives are the existing dispatch-deviation objective and are shown only for accepted final designs. Preparation objectives belong to more restricted problems or different load levels and are not compared as joint-design quality.', '',
'Run `julia --project=. examples/s1_staged_matrix.jl artifacts/s1_release_ipopt ipopt release` (substitute `madnlp` for the other backend and `load` for the continuation strategy), then `python examples/plot_s1_staged.py` after all four matrices finish. The plotting script verifies baseline hashes, accepted-seed gates and total iteration accounting before generating the tables and figures.', '',
'No global optimum or infeasibility certificate is claimed. Source branch-angle audits accompany accepted final cases in the machine-readable summary; source economic costs and angle limits are not part of this adapter’s optimization formulation. S1 remains open until reliability generalizes beyond the tuning matrix. Transformer AVR, complex bank models and M9 remain deferred.', '']
for (s,t),rs in runs.items():
 folder=root/f's1_{t}_{s}'
 for p in folder.glob('*.json'):
  if p.name!='summary.json':shutil.copy2(p,out/p.name)
 # Save the final row including source audit, which is added after the runner returns.
 for r in rs:(out/(r['name']+'-staged.json')).write_text(json.dumps(r,indent=2)+'\n')
(out/'summary.json').write_text(json.dumps(allruns,indent=2)+'\n')
for s,b in baselines.items():(out/f'baseline-{s}.json').write_text(json.dumps(list(b.values()),indent=2)+'\n')
text='\n'.join(lines);(out/'report.md').write_text(text)
assets=Path('docs/src/assets/s1_staged');assets.mkdir(parents=True,exist_ok=True)
for p in out.glob('*'):
 if p.suffix in ('.json','.png','.pdf'):shutil.copy2(p,assets/p.name)
Path('docs/src/s1_staged.md').write_text(re.sub(r'\]\(([^)]+)\)',lambda m:'](assets/s1_staged/'+m.group(1)+')',text))
print('\n'.join(lines[18:26]))
