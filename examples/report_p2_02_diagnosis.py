"""Explain saved anchor, response and runtime failures; no optimization."""
from pathlib import Path
import json,statistics,cmath,collections
root=Path(__file__).resolve().parents[1];out=root/'artifacts/p2_02_diagnosis';old=root/'artifacts/p2_02_scale_guard'
def load(p):return json.loads(p.read_text())
def save(p,x):p.write_text(json.dumps(x,indent=2)+'\n')
details=[]
for row in load(old/'anchor_audit.json')['rows']:
 if row['attempt']!='heldout' or row['comparison_complete']:continue
 case=load(old/'planned_cases'/(row['id']+'.json'))['data']['case'];state=load(old/'heldout'/row['id']/'anchor.json')['state'];net=case['network'];v=[m*cmath.exp(1j*t) for m,t in zip(state['vm'],state['va'])];ids={b['id']:i for i,b in enumerate(net['buses'])};inj=[0j]*len(v)
 for b in net['branches']:
  if not b['available']:continue
  i,j=ids[b['from_bus']],ids[b['to_bus']];y=1/complex(b['resistance'],b['reactance']);tap=b['tap_ratio']*cmath.exp(1j*b['phase_shift']);internal=v[i]/tap;cur=y*(internal-v[j]);sh=complex(0,b['charging']/2);inj[i]+=v[i]*((cur+sh*internal)/tap.conjugate()).conjugate();inj[j]+=v[j]*(-cur+sh*v[j]).conjugate()
 for sh in net['shunts']:
  if sh['available']:inj[ids[sh['bus_id']]]+=abs(v[ids[sh['bus_id']]])**2*complex(sh['conductance'],-sh['susceptance'])
 gens=[]
 for k,g in enumerate(case['generators']):
  required=inj[ids[g['bus_id']]].imag+sum(l['q'] for l in case['loads'] if l['bus_id']==g['bus_id']);gens.append(dict(generator=g['id'],bus=g['bus_id'],q=state['qg'][k],qmax=g['q_max'],required_at_saved_voltage=required,excess=required-g['q_max']))
 # Check terminal-flow reconstruction against the retained validation report.
 p=[0.0]*len(v);q=[0.0]*len(v)
 for k,g in enumerate(case['generators']):p[ids[g['bus_id']]]+=state['pg'][k];q[ids[g['bus_id']]]+=state['qg'][k]
 for l in case['loads']:p[ids[l['bus_id']]]-=l['p'];q[ids[l['bus_id']]]-=l['q']
 balance=max([abs(p[i]-inj[i].real) for i in range(len(v))]+[abs(q[i]-inj[i].imag) for i in range(len(v))]);assert abs(balance-row['physical_validation']['power_balance_max'])<1e-10
 details.append(dict(input=row['id'],validation=row['physical_validation'],generators=gens,max_local_q_excess=max(g['excess'] for g in gens),reconstructed_power_balance=balance))
save(out/'anchor_constraints.json',details)
runtime=[]
for row in load(old/'heldout/summary.json'):
 if '-24-' not in row['id'] or not row['base_valid']:continue
 phases={p:{k:statistics.median(x['phases'].get(k,0) for x in row['attempts'] if x['policy']==p and x['repetition']>1) for k in ['filter','prepare_build','optimize_extract','validate_rank']} for p in ['guarded','exhaustive']}
 times={p:statistics.median(x['elapsed'] for x in row['attempts'] if x['policy']==p and x['repetition']>1) for p in ['guarded','exhaustive']}
 data=[{a['entry']['contingency']['id']:a for a in load(old/'heldout'/row['id']/('2-'+p+'.json'))['assessments']} for p in ['guarded','exhaustive']]
 identical=sum(data[0][k]['exact_assessment']==data[1][k]['exact_assessment'] for k in set(data[0])&set(data[1]) if data[0][k]['exact_assessment'] is not None)
 runtime.append(dict(input=row['id'],screened=next(x['screened'] for x in row['attempts'] if x['policy']=='guarded'),times=times,phases=phases,shared_exact_outputs_identical=identical,extra_guarded_seconds=times['guarded']-times['exhaustive']))
save(out/'runtime_attribution.json',runtime)
uncertain=load(out/'uncertainty.json')['rows'];counts=collections.Counter((r['buses'],r['diagnostic']['debug_cause']) for r in uncertain)
raw=load(out/'candidate_regression.json');agreement=load(out/'agreement_regression.json')
lines=['# P2 02 diagnosis and response recovery','','Configuration: fixed supplied taps/shunts, zero equipment movement, frozen shared droop, preventive equal-weight active response. No repeated equipment confirmation until further notice. S2 is unchanged.','','## Four rejected anchors','','Terminal-flow reconstruction matches every retained power-balance maximum to 1e-10. AVR voltage constraints and Q capability are active at the rejected points. Only power balance violates the retained validation tolerances: the approximately 1e-8 Q-bound excess is within the 1e-6 limit tolerance. Binding Qmax and fixed AVR voltage are the local bottleneck, rather than a reported equipment-limit violation. This is not a global infeasibility certificate. Old cases and bounds remain unchanged.','','| Input | Maximum balance residual (pu) | Largest local Q excess (pu) |','|---|---:|---:|']
for r in details:lines.append(f"| {r['input']} | {r['reconstructed_power_balance']:.9f} | {r['max_local_q_excess']:.9f} |")
restoration=load(out/'anchor_restoration.json')
lines+=['','A separate nonlinear power-flow restoration omits Q caps only for diagnosis, keeping AVR at 1.0, supplied equipment, loads and nonreference P dispatch fixed; reference P balances losses. Each local root has residual below 1e-8, but requires excess Q capability. These deliberately relaxed diagnostic states are not valid anchors and are never scored as passes.','','| Input | Required Q above local cap (pu) |','|---|---:|']
for r in restoration:lines.append(f"| {r['input']} | {r['max_q_excess']:.9f} |")
lines+=['','This demonstrates the local Q-capability conflict under the specified AVR/dispatch restoration, without proving no other admissible state exists.','','## Predictor uncertainty' ,'','All 124 uncertain decisions were reproduced with a separate instrumented copy of the frozen predictor and identical safe/reason outputs. The 48-bus subset contains 117 decisions.','','| Buses | Stopping cause | Count |','|---|---|---:|']
for (n,c),count in sorted(counts.items()):lines.append(f'| {n} | {c} | {count} |')
lines+=['','No replay stopped at the Jacobian condition check. The prototype uses sixteen steps, twenty backtracking levels, squared-residual merit, and augmented-QR damped least-squares rescue. It resolves 115/117 formerly uncertain 48-bus predictions, all into regime-transition risk routes. These remain exact evaluations.','',f"The raw prototype produced **{raw['candidate_misses']} false screen across {raw['outages']} exposed development outages**. That failed experiment and its source/results are retained. The agreement-gated prototype screens only if both new and reference predictors say safe; it has **{agreement['candidate_misses']} development misses across {agreement['outages']} outages**. Convergence alone does not certify safety. Production library code and defaults are unchanged; the prototype is process-local in the fresh study.",'','## Why the 24-bus screening did not yield a total speedup','','| Input | Screened | Guarded - exhaustive seconds | Identical shared exact outputs in repetition 2 |','|---|---:|---:|---:|']
for r in runtime:lines.append(f"| {r['input']} | {r['screened']} | {r['extra_guarded_seconds']:.6f} | {r['shared_exact_outputs_identical']} |")
lines+=['','The four light/loaded inputs save exact work. The negative-reactive inputs screen nothing; solver/extraction timing variation on those unchanged exact workloads outweighs the savings. Across the cohort, guarded filtering takes about 0.510 seconds versus 0.007 exhaustive, so dense filtering does not explain the 5.461-second net slowdown. Garbage collection or host effects were not separately recorded; those causes are not proven. Two warmed timings per input are descriptive evidence only.','', '## Fresh validation contract','','Four separately predeclared 16/32-bus inputs have light/deadband and positive-reactive/proportional regimes, with stressed per-generator Qmax .6. These are new fixtures, not repaired old inputs. The agreement-gated prototype and reference are frozen before fresh base/outage solves. Legacy, reference, gated and exhaustive policies use four rotating-order repetitions; medians of warm repetitions 2–4 include predictor and exact work. Sources, planned inputs and every result are retained in ../p2_02_response_recovery/. The pre-execution world-age dispatch fix and original preparation records are retained; no fresh solve preceded the final freeze.']
fresh=root/'artifacts/p2_02_response_recovery/RESULTS.json'
if fresh.exists():
 r=load(fresh);lines+=['','## Fresh outcome','',f"Status: **{r['status']}**. Completed {r['complete_inputs']}/4 cases, {r['outages']} unique outages. Gated misses: {r['misses']['guarded']}; reference misses: {r['misses']['reference']}; legacy misses: {r['misses']['legacy']}. Replayed {r['replayed_states']} states with zero discrepancies.",'','| Policy | Screened | Warm median sum (s) |','|---|---:|---:|']
 for p in ['legacy','reference','guarded','exhaustive']:lines.append(f"| {p} | {r['screened'][p]} | {r['timings'][p]:.6f} |")
 lines+=['','The gated prototype screens the same 30 outages as the reference and is 2.8% slower (5.588 s versus 5.436 s). It is not promoted to production. The original reference saves about 7.2% versus exhaustive on this narrow sample; the candidate saves about 4.6%. Those descriptive warm medians do not establish deployment safety or large-network throughput. The original four rejected anchors remain a historical coverage gap; fresh valid cases do not relabel them as passes. Keep the production guard opt-in and exhaustive final AC audit mandatory.']
(out/'REPORT.md').write_text('\n'.join(lines)+'\n');print('Saved anchor, uncertainty, runtime and development report')
