"""Summarize the crossed, fixed-control droop sensitivity ledger."""
from pathlib import Path
from collections import defaultdict, Counter
import json
root=Path(__file__).resolve().parents[1]
out=root/'artifacts/s1_arpae14_joint_sensitivity'
rows=[json.loads(s) for s in (out/'rows.jsonl').read_text().splitlines() if s.strip()]
assert len(rows)==1080 and len({r['name'] for r in rows})==1080
assert not any('error' in r for r in rows), 'execution errors must be investigated before reporting'
configs=json.loads((out/'configurations.json').read_text())
assert len(configs)==60 and all(c['calibration_pass'] for c in configs)
precursors=json.loads((out/'source_precursors.json').read_text())
negatives=json.loads((out/'negative_controls.json').read_text())
assert len(precursors)==6 and all(c['check']['valid'] for c in precursors)
assert len(negatives)==6 and not any(c['calibration_pass'] for c in negatives)
count=lambda rs:sum(bool(r['point_pass']) for r in rs)
accept=lambda rs:sum(bool(r['accepted']) for r in rs)
def grouped(keys):
 d=defaultdict(list)
 for r in rows:d[tuple(r['tags'][k] if k!='solver' else r['solver'] for k in keys)].append(r)
 return d
configrows=grouped(['config']);rank=[]
for c in configs:
 rs=configrows[(c['config'],)];assert len(rs)==18
 n={str(f):count([r for r in rs if r['tags']['factor']==f]) for f in (.9,1.,1.1)}
 coverage=all(n[str(f)]>0 or f==1. for f in (.9,1.,1.1))
 rank.append(dict(c,verified=count(rs),accepted=accept(rs),demand_verified=n,coverage='feasible' if coverage else 'unresolved'))
rank.sort(key=lambda c:(-int(c['coverage']=='feasible'),-c['verified'],-c['accepted'],c['config']))
lines=['# S1 14-bus joint droop sensitivity','',
'Completed 1,080 solver runs: 60 fixed controller configurations × 2 demand-matched OPF initialization objectives × 3 demands × 3 solvers. All use five generator droops (G1–G5), source transformer taps and shunts, Pmin=0, and symmetric Q bounds. G6 is offline. Membership is held fixed; this study does not select which generators receive droop.','',
'All six cost/loss OPF seeds pass independent source AC and equipment replay. All 60 nominal controller calibration checks pass. Six negative controls that set zero-Q deadband centers directly to the nonzero-Q OPF voltages fail calibration and are rejected before optimization.','',
'## Definitions and parameter ranges','',
'Let m = (droop percent / 100)/(Qmax−Qmin), h = half the total voltage deadband width, and B_h(e) = sign(e) max(abs(e)−h,0). Every curve is Q(V)=clip(Q0+B_h(Vref−V)/m,Qmin,Qmax). Slopes therefore use the previously agreed full reactive capability span, not one-sided Qmax.','',
'- **zero_q_shifted:** Q0=0 and Vref=V*+mQ*+sign(Q*)h. The voltage reference is back-calculated to reproduce the calibration OPF.\n- **opf_q_centered:** Q0=Q* and Vref=V*. The deadband holds the OPF reactive injection.\n- **Uniform profiles:** 2%, 4%, 8% for all five generators.\n- **Mixed profiles:** G1–G5 percentages [2,4,8,4,2] and [8,4,2,4,8]. These are declared exploratory profiles, not an exhaustive search over independent slopes.\n- **Total deadband widths:** 0, 0.005, 0.01 pu voltage (0%, 0.5%, 1%).\n- **Calibration objective:** cost or active-loss minimization at 100% demand. Curves then remain frozen across demand.\n- **Initialization objective:** independently crossed cost or loss OPF at the demand being tested.\n- **Demand:** 90%, 100%, 110%; Ipopt, MadNLP, CCOpt.','',
'At zero deadband the two definitions yield identical exact curves for a fixed calibration point and slope. Their separate results measure numerical formulation sensitivity; they are not distinct physical control laws. A change to the calibration OPF changes the controller model, whereas a change to the initialization OPF changes only the solve starting point.','',
'For Ipopt/MadNLP, the library sets the absolute reactive smoothing width to 1e-6 × min(Q0−Qmin, Qmax−Q0). Changing Q0 therefore changes this numerical regularization as well as the expression graph. Definition comparisons here include library-default numerical effects; they do not isolate a physical-definition effect. CCOpt uses the exact complementarity formulation. All feasibility gates replay the exact unsmoothed law.','',
'## Acceptance and budget','',
'S1 retains the native dispatch-deviation objective, 600 iterations / 20 native solver seconds per run, smooth epsilon 1e-6 for Ipopt/MadNLP, and the preceding tight exact-complementarity CCOpt profile. Every returned point is independently checked for AC balance, exact droop response, source voltage/generator/thermal/angle limits and fixed-equipment policy. Verified counts describe physical witnesses; accepted counts additionally require accepted native solver termination. Time is descriptive and includes compilation; it is not a solver performance benchmark.','',
'Every configuration is already known feasible at 100% demand from its calibration witness, irrespective of optimizer termination. Demand-scope coverage is feasible only when all three demands have a witness; otherwise it is unresolved. No global infeasibility certificates are computed.','',
f"**Verified points: {count(rows)}/1080; accepted solver results: {accept(rows)}/1080. Configurations with feasible coverage across all three demands: {sum(c['coverage']=='feasible' for c in rank)}/60.**",'',
'## Calibration versus initialization','',
'| Definition | Calibration OPF | Initializing OPF | Verified | Accepted |','|---|---|---|---:|---:|']
for keys,rs in sorted(grouped(['definition','calibration_objective','initialization_objective']).items()):
 lines.append('| '+' | '.join(map(str,keys))+f' | {count(rs)}/{len(rs)} | {accept(rs)}/{len(rs)} |')
lines+=['','## Definition and deadband','', '| Definition | Total deadband, pu | Verified | Accepted |','|---|---:|---:|---:|']
for keys,rs in sorted(grouped(['definition','deadband_total_width_pu']).items()):
 lines.append('| '+' | '.join(map(str,keys))+f' | {count(rs)}/{len(rs)} | {accept(rs)}/{len(rs)} |')
lines+=['','## Slope profiles','', '| Definition | Profile | Verified | Accepted |','|---|---|---:|---:|']
for keys,rs in sorted(grouped(['definition','profile']).items()):
 lines.append('| '+' | '.join(map(str,keys))+f' | {count(rs)}/{len(rs)} | {accept(rs)}/{len(rs)} |')
lines+=['','## Solvers by demand','', '| Solver | Demand | Verified | Accepted |','|---|---:|---:|---:|']
for keys,rs in sorted(grouped(['solver','factor']).items()):
 lines.append(f'| {keys[0]} | {100*keys[1]:.0f}% | {count(rs)}/{len(rs)} | {accept(rs)}/{len(rs)} |')
lines+=['','## Configuration ranking','',
'Ranking prioritizes coverage across all demands, then verified count and accepted count. Every configuration has 18 runs (six per demand). Equal scores are ties; the display order is not a performance distinction. These are exploratory tuning results, not held-out validation or a globally best controller search.','',
'| Definition | Calibration | Profile | Total deadband, pu | 90% | 100% | 110% | Verified | Accepted | Demand-scope gate |','|---|---|---|---:|---:|---:|---:|---:|---:|---|']
for c in rank:
 n=c['demand_verified']
 lines.append(f"| {c['definition']} | {c['calibration_objective']} | {c['profile']} | {c['deadband_total_width_pu']} | {n['0.9']}/6 | {n['1.0']}/6 | {n['1.1']}/6 | {c['verified']}/18 | {c['accepted']}/18 | {c['coverage']} |")
lines+=['','## Interpretation and practical candidate','',
'Loss-OPF calibration yields 457/540 verified points versus 245/540 for cost-OPF calibration. No cost-calibrated configuration produced a verified 90%-demand point in this grid (0/180). Switching initialization alone is not the improvement: cost initializations yield 358/540 verified points and loss initializations 344/540.','',
'A simple candidate for further validation is the loss-calibrated, zero-Q shifted definition with uniform 8% droop. Each tested deadband width produces 18/18 verified and solver-accepted results. The mixed [2,4,8,4,2]% profile ties this result. Increasing the voltage-per-reactive-span droop from 4% to 8% halves the magnitude of dQ/dV outside the deadband and saturation. These are tested candidates, not a globally optimal slope or a validation on the 500-bus case.','',
'For the uniform-8%, zero-deadband candidate, an active branch thermal limit remains within 6.1e-10 pu of binding across the 18 results; some points also bind the 1.1 pu voltage upper limit. Improved solver acceptance therefore does not establish extra operating headroom. Maximum replayed AC-balance and droop residuals are approximately 7.54e-11 and 5.46e-9 pu.','',
'All 1,080 saved final states were independently replayed from the 60 serialized configurations, with zero discrepancies against the recorded point gates (serialization_audit.json). Fourteen physically verified points lack successful solver termination, so the 702 witness count must not be reported as 702 successful optimizations.','']
lines+=['','## Native solver terminations','', '| Termination | Runs |','|---|---:|']
for status,n in Counter(r.get('solver_status','ERROR') for r in rows).most_common():lines.append(f'| {status} | {n} |')
lines+=['','Cases are serialized once per configuration. The rows.jsonl ledger stores final states, source seed identifiers, solver status and independent physical audits for every run, including failed points. protocol.json and source_precursors.json retain the design and input hashes.','']
(out/'report.md').write_text('\n'.join(lines))
(out/'ranking.json').write_text(json.dumps(rank,indent=2)+'\n')
summary=dict(cells=len(rows),verified=count(rows),accepted=accept(rows),configs_feasible=sum(c['coverage']=='feasible' for c in rank),top=rank[:10],aggregate=[dict(definition=k[0],calibration=k[1],initialization=k[2],verified=count(rs),accepted=accept(rs),n=len(rs)) for k,rs in sorted(grouped(['definition','calibration_objective','initialization_objective']).items())])
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
