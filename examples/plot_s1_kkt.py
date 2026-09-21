"""Report original-unit stationarity and hypothetical row equilibration."""
from pathlib import Path
import json,shutil,re
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
root=Path('artifacts');out=root/'s1_kkt';out.mkdir(exist_ok=True)
rows=[];points={}
for solver in ['ipopt','madnlp']:
 folder=root/f's1_kkt_{solver}';rs=json.loads((folder/'summary.json').read_text());assert len(rs)==5
 for r in rs:
  p=json.loads((folder/r['kkt_file']).read_text());assert set(p)=={'initial','final'},(r['name'],p.keys())
  assert p['final']['dual_available']
  rows.append(r);points[r['name']]=p
  for a in folder.glob(r['name']+'-*.json'):shutil.copy2(a,out/a.name)
 (out/f'selection-{solver}.json').write_text((folder/'selection.json').read_text())
f=lambda x:'—' if x is None else f'{x:.3g}'
lines=['# S1 residual scaling, stationarity and active bounds','',
'This is a read-only diagnostic checkpoint. Ten declared runs cover accepted cases, numerical failures, physically feasible rejected solver outcomes, and a stalled recovery source on IEEE 118/300 with both Ipopt and MadNLP. The sample is selected from the existing tuning cases; it is not new reliability evidence or a solver-ranking study. Each run repeats the direct initial solve with physical coordinates, epsilon 1e-6, bound push/fraction 1e-8, at most 1000 iterations and a 60-second native solver time limit. No restart or staged preparation is added. Instrumentation and compilation affect elapsed time; no performance claim is made.', '',
'## What is computed', '',
'For the existing minimization model, the physical-coordinate Lagrangian gradient is reconstructed as', '',
'```math',r'\nabla_x L = \nabla_x f - J_g^\mathsf{T} y_g - J_b^\mathsf{T} y_b.', '```', '',
'The signs follow JuMP/MOI dual conventions. The report separates the dispatch objective gradient, nonlinear constraint contribution, and regular constraint/bound contribution for every variable. Fixed variables are excluded from the headline free-variable norm; their entries remain in JSON. Inequality dual-sign errors and complementarity are computed separately. Unit tests exercise equality duals, active bounds, active nonlinear inequalities, quadratic cross terms and reused nonlinear subexpressions on both solvers.', '',
'Row and column infinity norms are computed from the original nonlinear Jacobian. These are derivative magnitudes in the current units, not singular values or condition numbers. Bus-balance rows are in pu power, thermal rows use squared apparent power, and droop rows are smooth reactive-power residuals. A near-bound flag means distance at most 1e-6 in that variable’s physical units; it does not establish a nonzero multiplier or causation.', '',
'## Solver termination versus physical and KKT checks', '',
'![KKT decomposition](kkt.png)', '',
'| Case | Native termination | Accepted / physically valid | Free stationarity | Complementarity | Worst free coordinate | Worst exact physical failure |', '|---|---|---|---|---|---|---|']
fig,axes=plt.subplots(3,1,figsize=(12,9),sharex=True,layout='constrained')
for i,r in enumerate(rows):
 p=points[r['name']]['final'];free=[v for v in p['variables'] if not v['fixed']]
 worst=max(free,key=lambda v:abs(v['stationarity']))
 failures=r.get('physical_failures') or [];physical='none'
 if failures:
  a=failures[0];physical=f"{a['category']}: {a['equipment']} {a['id']} {a['component']} ({f(a['violation_pu'])} > {f(a['tolerance_pu'])})"
 lines.append(f"| [{r['name']}]({r['kkt_file']}) | {r['status']} | {r['valid']} / {r['physical_valid']} | {f(p['free_stationarity_max'])} | {f(p['complementarity_max'])} | {worst['name']} | {physical} |")
 for ax,key,label in zip(axes,['free_stationarity_max','complementarity_max','constraint_violation_max'],['Free stationarity (physical coordinates)','Complementarity (original model)','Constraint violation (mixed model units)']):
  ax.scatter(i,max(p[key],1e-16),c='#238b65' if r['valid'] else '#c74b50',s=45)
  ax.set_yscale('log');ax.set_ylabel(label);ax.grid(axis='y',alpha=.2)
axes[0].set_title('Green = accepted; red = rejected. These are different quantities, not a common acceptance scale.')
axes[-1].set_xticks(range(len(rows)),[r['name'].replace('public','').replace('-','\n') for r in rows],fontsize=8)
for ext in ['png','pdf']:fig.savefig(out/f'kkt.{ext}',dpi=160)
plt.close(fig)
lines += ['', '## What row equilibration would change', '',
'For diagnosis only, freeze a positive factor from each initial Jacobian row:', '', '```math',
 r'\alpha_i = 1/\max(1,\|J_{g_i}(x_0)\|_\infty),\qquad \widetilde g_i=\alpha_i g_i,\qquad \widetilde y_i=y_i/\alpha_i.', '```', '',
'With both the constraint function and its bound scaled, this preserves the exact feasible set. Transforming the multiplier as shown preserves the Lagrangian gradient and complementarity. The snapshots verify this identity numerically at the final points. No scaled formulation is sent to the solver in this checkpoint.', '',
'A small scaled residual alone does not prove a small physical residual: a scaled tolerance of 1e-8 permits an original-row error of 1e-8/alpha. The next table reports the largest such allowance per family across the ten starts. This is a hypothetical tolerance conversion, not a recommended stopping tolerance. Thermal values are in squared-power units, so they must not be compared directly with the independent apparent-power tolerance.', '',
'![Initial row magnitudes](rows.png)', '',
'| Equation family | Initial row norm min / max | Zero rows | Minimum alpha | Largest raw allowance at scaled 1e-8 |', '|---|---|---|---|---|']
families=['balance_P','balance_Q','thermal_squared','droop'];fig,ax=plt.subplots(figsize=(9,4.5),layout='constrained')
for i,family in enumerate(families):
 rr=[a for p in points.values() for a in p['initial']['nonlinear_rows'] if a['family']==family]
 norms=[a['jacobian_max'] for a in rr];scaled=[a['scaled_jacobian_max'] for a in rr]
 lo,hi=min(norms),max(norms);scale=min(a['scale'] for a in rr)
 lines.append(f'| {family} | {f(lo)} / {f(hi)} | {sum(v==0 for v in norms)} | {f(scale)} | {f(1e-8/scale)} |')
 for offset,vals,color,label in [(-.12,norms,'#607d8b','Original'),(.12,scaled,'#238b65','Hypothetically scaled')]:
  ax.plot([i+offset]*2,[min(v for v in vals if v>0),max(vals)],color=color,lw=5,marker='o',markersize=4,label=label if i==0 else None)
ax.set_title('Positive row-norm ranges; zero rows are counted in the table')
ax.set_yscale('log');ax.set_xticks(range(4),families);ax.set_ylabel('Initial Jacobian row infinity norm');ax.legend();ax.grid(axis='y',alpha=.2)
for ext in ['png','pdf']:fig.savefig(out/f'rows.{ext}',dpi=160)
plt.close(fig)
lines += ['', '## Controller bounds and weak derivative columns', '',
'Counts below refer to free controller variables. Weak means nonlinear Jacobian column infinity norm below 1e-10 at the final iterate. A weak droop slope column can occur in a deadband or saturated region; it alone neither proves rank deficiency nor explains the solver termination.', '',
'| Case | Controllers near bounds / total | Weak controller columns | Maximum controller stationarity | Largest free objective / nonlinear / bound contributions |', '|---|---|---|---|---|']
for r in rows:
 p=points[r['name']]['final'];free=[v for v in p['variables'] if not v['fixed']]
 controls=[v for v in free if v['name'].startswith(('design_','tap_','shunt_'))]
 terms=[max(abs(v[k]) for v in free) for k in ['objective_gradient','nonlinear_dual_term','regular_dual_term']]
 lines.append(f"| {r['name']} | {sum(v['near_bound'] for v in controls)}/{len(controls)} | {sum(v['jacobian_column_max']<1e-10 for v in controls)} | {f(max((abs(v['stationarity']) for v in controls),default=0))} | {' / '.join(f(v) for v in terms)} |")
lines += ['', '## Saturated droops and active reactive-power bounds', '',
'At a fully saturated droop point, the computed droop equality can have derivative 1 with respect to generator Q and zero derivatives with respect to all other variables. When Q is also at its capability bound, this row is numerically parallel to the active bound. The supplemental geometry pass rebuilds the identical formulation and evaluates its Jacobian at each retained final point without solving. It checks all variable names and regular constraint layouts before using saved multipliers.', '',
'This behavior appears in both accepted and rejected runs and on both solvers. It is evidence of local numerical dependence, not proof that it causes every failure or that the smooth model is exactly rank-deficient in real arithmetic. Removing a bound based on this observation would require a separate formulation review; no bound is removed here.', '',
'| Case | Droop rows parallel to active Q bounds | Largest absolute droop multiplier | Maximum relative stationarity |', '|---|---|---|---|']
for r in rows:
 g=json.loads((out/(r['name']+'-geometry.json')).read_text())
 parallel=sum(a['numerically_parallel_to_active_q_bound'] for a in g['droop_rows'])
 largest=max(abs(a['droop_multiplier']) for a in g['droop_rows'])
 relative=max(a['relative_residual'] for a in g['cancellation'] if not a['fixed'])
 lines.append(f"| [{r['name']}]({r['name']}-geometry.json) | {parallel} | {f(largest)} | {f(relative)} |")
lines += ['',
'For the accepted MadNLP IEEE 118 +5% flat-low case, generators 8 and 17 have droop multipliers about 1.8e15 and 3.6e15, balanced by reactive-power bound multipliers of the opposite sign. Their off-Q Jacobian derivatives evaluate to zero. The reconstructed maximum raw stationarity is 32, while the maximum coordinatewise relative residual is about 7.5e-14. The latter divides each residual by max(1, the sum of absolute individual Lagrangian-gradient contributions). These two quantities answer different questions; the relative value is not an optimality certificate. Extremely large cancelling terms make absolute residuals sensitive to floating-point precision.', '',
'The accepted MadNLP IEEE 300 +5% anchor likewise has a saturated generator-39 row and a multiplier around 2e14. The stalled nominal IEEE 300 flat-low case has six parallel rows and a relative stationarity residual of 1, so cancellation alone does not explain away that failure.', '',
'Installed MadNLP 0.10.1 computes native dual and complementarity measures with multiplier-dependent divisors (`get_sd`, `get_sc`, `get_inf_du`, `get_inf_compl` in `src/IPM/kernels.jl`). These can be large when multipliers are large, explaining why native scaled convergence can coexist with larger reconstructed raw residuals. The saved native values and raw decompositions are both retained. This does not change the existing native-plus-physical acceptance gate; it identifies a separate solution-quality issue to resolve.', '',
'**Next priority:** isolate saturated-droop/active-Q-bound numerical dependence in a small reproducer, compare multiplier behavior and stopping rules, then test an explicitly equivalent numerical remedy. Blind row equilibration is not sufficient: multiplying parallel rows by positive constants cannot make them independent. Full-network scaling experiments and holdout studies follow this focused investigation.', '']
lines += ['', '## Limits and next decision', '',
'All ten runs reproduce the frozen direct first-attempt status, acceptance decision and objective exactly. All original termination and independent physical-validation decisions are retained. A low KKT residual does not establish global optimality, and a low physical residual does not establish convergence. The diagnostic does not override either gate. Solver-native scaled norms and these reconstructed physical-coordinate norms need not coincide.', '',
'The initial adapter pilot failed when converting reused nonlinear expressions through JuMP’s expression-conversion API. Its outputs are retained in `artifacts/s1_kkt_adapter_pilot_ipopt` and `artifacts/s1_kkt_adapter_pilot_madnlp`; those interrupted development runs are excluded from the ten-case diagnostic sample. The corrected adapter reads nonlinear constraint sets directly from the installed JuMP nonlinear model and is covered by a subexpression regression test.', '',
'No equipment, objective, bounds, smoothing or acceptance tolerances changed. S1 remains open. Any row-scaling solve experiment must preserve physical validation, explicitly account for transformed stopping tolerances and multipliers, and use the frozen paired cases before broader holdout validation.', '']
(out/'summary.json').write_text(json.dumps(rows,indent=2)+'\n')
text='\n'.join(lines);(out/'report.md').write_text(text)
assets=Path('docs/src/assets/s1_kkt');assets.mkdir(parents=True,exist_ok=True)
for p in out.glob('*'):
 if p.suffix in ['.json','.png','.pdf']:shutil.copy2(p,assets/p.name)
Path('docs/src/s1_kkt.md').write_text(re.sub(r'\]\(([^)]+)\)',lambda m:'](assets/s1_kkt/'+m.group(1)+')',text))
