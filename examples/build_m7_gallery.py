"""Refresh the documentation gallery from the three retained M7 evidence bundles."""
from pathlib import Path
import json, shutil
root=Path(__file__).resolve().parents[1]
lines=['# M7 equipment and joint droop optimization','',
       'These synthetic three-bus studies demonstrate base-case continuous optimization. They do not establish security-constrained equipment performance, discrete implementability or scalability. All three slices use the same dispatch-deviation objective; losses and setting deviations are separate metrics.','',
       'The numerical tables and figures below are generated from retained evidence. Reproduce the solve and plot workflows in [Examples](examples.md), then run `python3 examples/build_m7_gallery.py`. Input studies, versioned designs, detailed reports and regression logs remain under `artifacts/m7_1`, `artifacts/m7_2` and `artifacts/m7_3`.','']
def table(headers,rows):
    lines.extend(['| '+' | '.join(headers)+' |','|'+'|'.join('---' for _ in headers)+'|'])
    for row in rows:lines.append('| '+' | '.join(f'{v:.7g}' if isinstance(v,float) else str(v) for v in row)+' |')
    lines.append('')
def figures(slice,names):
    source=root/'artifacts'/slice;dest=root/'docs/src/assets'/slice;dest.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source/'evidence.json',dest/'evidence.json')
    for name in names:
        for ext in ['png','pdf']:shutil.copy2(source/(name+'.'+ext),dest/(name+'.'+ext))
        title=name.replace('_',' ').capitalize()
        lines.extend([f'![{title}](assets/{slice}/{name}.png)',f'[Download {title.lower()} as PDF](assets/{slice}/{name}.pdf)',''])
    lines.extend([f'[Machine-readable evidence](assets/{slice}/evidence.json)',''])
d=json.loads((root/'artifacts/m7_1/evidence.json').read_text())
lines+=['## M7.1 — Transformer taps','', 'Fixed-bound and standalone equivalence, a 41-point tap sweep and one/two-free-tap comparisons. Transformer phase shifts, shunts and droops stay fixed.','']
table(['Configuration','Objective','Tap 11','AC residual (pu)','Branch loss (pu)'],[[r['name'],r['objective'],r['taps']['11'],r['ac_residual'],r['metrics']['branch_active_loss']] for r in d['runs']])
figures('m7_1',['tap_sweep','operating_points','tap_settings'])
d=json.loads((root/'artifacts/m7_2/evidence.json').read_text())
lines+=['## M7.2 — Simple capacitor/reactor banks','', 'Each bank has one step type. A fractional count scales G and B together. Taps and droops stay fixed. Each capacitor/reactor sweep contains 31 points. Complex-bank optimization is deferred until simple-bank/transformer/droop scaling is demonstrated.','']
table(['Equipment','Mode','Objective','AC residual (pu)','Branch loss (pu)','Shunt active consumption (pu)'],[[r['equipment'],r['mode'],r['objective'],r['ac_residual'],r['metrics']['branch_active_loss'],r['metrics']['shunt_active_consumption']] for r in d['runs']])
figures('m7_2',['susceptance_sweep','bank_envelopes','operating_points','active_losses'])
d=json.loads((root/'artifacts/m7_3/evidence.json').read_text())
lines+=['## M7.3 — Joint equipment and droop design','', 'Digits denote **tap / shunt / droop**, with 1 free and 0 fixed. Each configuration has two starts. Tables select the lowest-objective physically valid attempt; the evidence retains every attempt and failure. Tap 11 is bounded to [0.95,1.05], bank 201 B to [0,0.06] pu, and droop 2 slope to [0.04,0.10]. Other parameters are fixed in this grid; separate regression tests exercise reference and asymmetric deadband selection.','']
table(['T/S/D','Valid starts','Objective','Tap','B (pu)','Slope','AC residual (pu)'],[[r['configuration'],str(r['valid_starts'])+'/2',r['objective'],r['tap'],r['B'],r['slope'],r['ac_residual']] for r in d['selected']])
table(['T/S/D','Active objective','Reactive objective','Branch loss','Shunt consumption','Objective spread','Slope spread'],[[r['configuration'],r['metrics']['active_dispatch_component'],r['metrics']['reactive_dispatch_component'],r['metrics']['branch_active_loss'],r['metrics']['shunt_active_consumption'],r['objective_spread'],r['parameter_spread']['slope']] for r in d['selected']])
lines+=['The objective is the sum of the two listed components. Design penalty is zero in every configuration. Loss quantities are in pu. The second-start design values are tap=1, B=0.04 and slope=0.095 for enabled families, with the solved fixed operating state; the first start uses supplied settings and the declared proportional-regime state.','',
        '### Matched attribution and interactions','', 'Each comparison below changes only droop freedom. Variation across these four benefits measures its dependence on equipment freedom; isolated benefits must not be added without accounting for interactions.','']
table(['Equipment freedom held fixed','Objective decrease from freeing droop'],[[r['equipment'],r['droop_objective_improvement']] for r in d['matched_droop_benefits']])
lines+=['Some starts may reach different valid local solutions. Similar objectives with different settings indicate weak parameter identification on this case. Multi-start evidence is not a global-optimality certificate.','']
figures('m7_3',['objectives','settings','operating_points','multistart','matched_benefits'])
lines+=['## Acceptance and next scope','', 'Independent AC and exact-droop tolerances are 1e-6 and 1e-5 pu. Smooth epsilon is 1e-5. Fixed/free comparisons allow objective differences of 1e-8 for numerical equivalence. The full suite checks policy perturbations, physical replay, serialization and Ipopt/MadNLP agreement. M8 adds steady-state transformer AVR; M9 adds coordinated equipment decisions and response policies across contingencies.','']
(root/'docs/src/equipment_optimization.md').write_text('\n'.join(lines))
