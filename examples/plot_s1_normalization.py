"""Frozen paired normalization comparison; no failed attempts are discarded."""
from pathlib import Path
import json, hashlib, shutil
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
root=Path('artifacts');out=root/'s1_normalization';out.mkdir(exist_ok=True)
manifest=json.loads((out/'frozen-baseline.json').read_text())
for name,digest in manifest.items():assert hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest
solvers=['ipopt','madnlp']
baseline={s:json.loads((root/f's1_policy_{s}'/'summary.json').read_text()) for s in solvers}
normalized={s:json.loads((root/f's1_normalized_{s}'/'summary.json').read_text()) for s in solvers}
assert all(len(normalized[s])==12 for s in solvers)
fig,axes=plt.subplots(1,2,figsize=(11,5),layout='constrained')
for ax,s in zip(axes,solvers):
    values=[sum(r['attempts'][0]['valid'] for r in baseline[s]),sum(r['valid'] for r in baseline[s]),
        sum(r['attempts'][0]['valid'] for r in normalized[s]),sum(r['valid'] for r in normalized[s])]
    ax.bar(range(4),values,color=['#90a4ae','#607d8b','#91c9ad','#238b65'])
    ax.set_xticks(range(4),['Physical\ninitial','Physical\npolicy','Normalized\ninitial','Normalized\npolicy'])
    ax.set_ylim(0,13);ax.set_ylabel('Validated cases out of 12');ax.set_title(s)
    for i,v in enumerate(values):ax.text(i,v+.2,str(v),ha='center')
for ext in ('png','pdf'):fig.savefig(out/f'acceptance.{ext}',dpi=160)
plt.close(fig)
lines=['# S1 equivalent controller normalization','',
'Free settings use physical value = lower + (upper − lower) × z, with 0 ≤ z ≤ 1. Fixed settings remain fixed. This is an opt-in coordinate transformation (`control_normalization=:bounds`); the default `:none` retains physical coordinates. Equipment equations, objective, physical limits, smoothing, and independent validation tolerances are unchanged. Results and design JSON contain physical settings.', '',
'The 24-case benchmark and baseline hashes are frozen. Each normalized run uses the same network, loading, declared physical start, policy, numerical options and cumulative budget as its baseline. Solver bound pushes operate in the chosen numerical coordinates, so their physical displacement changes with interval width. This is part of the coordinate experiment, not a new initialization policy. Raw stationarity norms also depend on coordinates and are not directly compared as physical quantities.', '',
'The same one-reset policy and 2000-iteration/120-second cooperative wall budget apply. At most 1000 iterations/60 seconds are allowed per attempt. The clock is checked at callbacks, not a hard process timeout. Timing includes compilation and some concurrent work and is not an isolated performance benchmark. No extra smoothing or staged release is introduced in this comparison.', '',
'![Acceptance comparison](acceptance.png)', '',
'| Solver | Baseline initial → policy | Normalized initial → policy | Gained cases | Lost cases |', '|---|---|---|---|---|']
for s in solvers:
 b={r['name']:r for r in baseline[s]};n={r['name']:r for r in normalized[s]}
 gain=sum(n[k]['valid'] and not b[k]['valid'] for k in b);loss=sum(b[k]['valid'] and not n[k]['valid'] for k in b)
 lines.append(f"| {s} | {sum(r['attempts'][0]['valid'] for r in b.values())} → {sum(r['valid'] for r in b.values())} | {sum(r['attempts'][0]['valid'] for r in n.values())} → {sum(r['valid'] for r in n.values())} | {gain} | {loss} |")
lines += ['', '## Paired case ledger', '', '| Case | Baseline valid / iterations | Normalized valid / iterations | Normalized final decision | Baseline / normalized accepted objective |', '|---|---|---|---|---|']
accepted=lambda r:next((a['objective'] for a in r['attempts'] if a['name']==r['selected']),None)
fmt=lambda x:'—' if x is None else f'{x:.10g}'
for s in solvers:
 b={r['name']:r for r in baseline[s]}
 for n in normalized[s]:
  old=b[n['name']]
  lines.append(f"| [{n['name']}]({n['name']}-policy.json) | {old['valid']} / {old['iterations']} | {n['valid']} / {n['iterations']} | {n['events'][-1]} | {fmt(accepted(old))} / {fmt(accepted(n))} |")
lines += ['', '## Numerical convergence versus exact-droop validation', '', '| Attempt | Solver status | Valid | Smooth/exact droop gap (pu) | Exact droop residual (pu) | AC residual (pu) | Failure categories |', '|---|---|---|---|---|---|---|']
for s in solvers:
 for r in normalized[s]:
  for a in r['attempts']:
   p=a.get('physical') or {}
   lines.append(f"| [{a['name']}]({a['name']}-diagnostics.json) | {a.get('status','ERROR')} | {a['valid']} | {fmt(p.get('smooth_exact_droop_gap'))} | {fmt(p.get('droop_residual_max'))} | {fmt(p.get('power_balance_max'))} | {', '.join(p.get('violations',[])) if p else 'not evaluated'} |")
lines += ['', '## Verification and scope', '',
'Pointwise tests compare original and normalized equations and objectives at interval endpoints and interior points for capacitors and reactors. Jacobians and Lagrangian Hessians satisfy the affine chain rule. Fixed intervals bypass normalization, and solved settings round-trip through the existing physical JSON schema. Restart contexts include the coordinate mode, preventing reuse of incompatible numerical seeds.', '',
'This experiment does not establish global optimality or general convergence. Normalization stays opt-in pending evidence across starts, loads and controller placements. S1 remains open before M9. Controlled smoothing and staged initialization must be tested separately before combining changes.', '']
refine_root=root/'s1_normalization_refinement'
if (refine_root/'eligibility.json').exists():
    refinements=json.loads((refine_root/'summary.json').read_text())
    lines += ['', '## Separate smoothing refinement', '',
        'Eligibility was declared by failure type: the final attempt converged, failed only exact droop validation, and independently recomputed smooth-droop residual was at most 1e-6 pu. Every eligible point receives one separate solve at epsilon 1e-7, seeded by its physical state/settings, with no transferred duals. Each receives an additional 1000-iteration/60-second allowance. These extra solves are excluded from the frozen matrix counts; they are not a within-budget improvement claim.', '',
        f"**{sum(a['valid'] for a in refinements)}/{len(refinements)} refinement attempts validate.** Reducing approximation error does not guarantee numerical convergence.", '',
        '| Refinement | Native status | Valid | Source smooth residual | Source approximation gap | Final exact residual |', '|---|---|---|---|---|---|']
    fig,ax=plt.subplots(figsize=(11,5),layout='constrained')
    for i,a in enumerate(refinements):
        before=a['tags']['source_components'];after=a.get('physical') or {}
        lines.append(f"| [{a['name']}]({a['name']}-diagnostics.json) | {a.get('status','ERROR')} | {a['valid']} | {fmt(before['smooth_residual_max'])} | {fmt(before['approximation_gap_max'])} | {fmt(after.get('droop_residual_max'))} |")
        ax.scatter(i-.08,before['approximation_gap_max']/1e-5,marker='o',color='#607d8b',label='Source approximation gap' if i==0 else None)
        if after:
            ax.scatter(i+.08,max(after['droop_residual_max']/1e-5,1e-10),marker='x',color='#238b65' if a['valid'] else '#bd4545',label='Refined exact residual' if i==0 else None)
    ax.axhline(1,color='black',ls='--',label='Physical tolerance')
    ax.set_yscale('log');ax.set_ylabel('Residual / exact-droop tolerance')
    ax.set_xticks(range(len(refinements)),[a['name'].replace('public','').replace('-refine','').replace('-','\n') for a in refinements],fontsize=8)
    ax.set_title('Separate refinement: green × = validated; red × = rejected');ax.legend()
    for ext in ('png','pdf'):fig.savefig(out/f'refinement.{ext}',dpi=160)
    plt.close(fig)
    lines += ['', '![Separate refinement](refinement.png)', '']
    for p in refine_root.glob('*.json'):
        if p.name=='summary.json':shutil.copy2(p,out/'refinement-summary.json')
        else:shutil.copy2(p,out/p.name)
for s in solvers:
 for p in (root/f's1_normalized_{s}').glob('*.json'):
  if p.name!='summary.json':shutil.copy2(p,out/p.name)
 (out/f'baseline-{s}.json').write_text(json.dumps(baseline[s],indent=2)+'\n')
(out/'summary.json').write_text(json.dumps(normalized,indent=2)+'\n')
text='\n'.join(lines);(out/'report.md').write_text(text)
assets=Path('docs/src/assets/s1_normalization');assets.mkdir(parents=True,exist_ok=True)
for p in out.glob('*'):
 if p.suffix in ('.json','.png','.pdf'):shutil.copy2(p,assets/p.name)
import re
text=re.sub(r'\]\(([^)]+)\)',lambda m:'](assets/s1_normalization/'+m.group(1)+')',text)
Path('docs/src/s1_normalization.md').write_text(text)
