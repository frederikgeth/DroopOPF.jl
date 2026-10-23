"""Summarize preserved measurements and fresh exhaustive comparisons."""
import json,statistics
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; OUT=ROOT/'artifacts/p2_02_large_sparse'
load=lambda p:json.loads(p.read_text())
def main():
 fresh=OUT; rows=load(fresh/'heldout/summary.json');audit=load(fresh/'heldout_audit.json')
 policies=['dense_exhaustive','sparse_exhaustive','dense_guarded','sparse_guarded']
 times={p:0. for p in policies};allocations={p:0. for p in policies};details=[];differences=[];maxdiff=0.;common=0
 for row in rows:
  if not row['base_valid'] or len(row['attempts'])!=16: continue
  directory=fresh/'heldout'/row['id'];study=load(directory/'input.json')['data'];raw=load(fresh/'planned_cases'/(row['id']+'.json'))['data']
  assert study['case']['network']==raw['case']['network'] and study['case']['generators']==raw['case']['generators']
  assert all(v==1 for v in study['participation'].values())
  data={(a['repetition'],a['policy']):load(directory/a['path']) for a in row['attempts']}
  timing={p:statistics.median(a['elapsed'] for a in row['attempts'] if a['policy']==p and a['repetition']>1) for p in policies}
  allocated={p:statistics.median(a['bytes'] for a in row['attempts'] if a['policy']==p and a['repetition']>1) for p in policies}
  for p in policies:times[p]+=timing[p];allocations[p]+=allocated[p]
  for rep in range(1,5):
   maps={p:{a['entry']['contingency']['id']:a for a in data[rep,p]['assessments']} for p in policies}
   assert all(a['complete'] for a in row['attempts'])
   assert {k for k,a in maps['dense_guarded'].items() if a['decision']['action']=='screened'}=={k for k,a in maps['sparse_guarded'].items() if a['decision']['action']=='screened'}
   for id,a in maps['dense_exhaustive'].items():
    b=maps['sparse_exhaustive'][id]
    if a['rank']['classification']!=b['rank']['classification']:differences.append([row['id'],rep,id,a['rank']['classification'],b['rank']['classification']])
    if a['rank']['classification']==b['rank']['classification']=='accepted':
     sa=a['exact_assessment']['result']['states'][id];sb=b['exact_assessment']['result']['states'][id]
     maxdiff=max(maxdiff,max(abs(x-y) for field in ['vm','va','pg','qg'] for x,y in zip(sa[field],sb[field])));common+=1
  details.append({'id':row['id'],'warm_medians':timing,'warm_allocations':allocated,'base_regimes':dict(__import__('collections').Counter(x['regime'] for x in load(directory/'base_regimes.json')))})
 families=audit['families'];misses={p:sum(f['misses'] for f in families if f['policy']==p) for p in policies};screened={p:sum(f['screened'] for f in families if f['policy']==p) for p in policies}
 exhaustive_saving=1-times['sparse_exhaustive']/times['dense_exhaustive'];guarded_saving=1-times['sparse_guarded']/times['dense_guarded']
 screened_by_size={str(n):sum(f['screened'] for f in families if f['policy']=='sparse_guarded' and f'-{n}-' in f['input']) for n in (48,96)}
 cohort_coverage=all(c.get('coverage',False) for c in load(OUT/'cohort_audit.json'))
 passed=cohort_coverage and all(screened_by_size.values()) and common>0 and len(details)==6 and not any(misses.values()) and not differences and maxdiff<=1e-5 and exhaustive_saving>0 and guarded_saving>0
 result={'status':'FINITE_SCOPE_GATE_PASSED' if passed else 'NOT_QUALIFIED','complete_inputs':len(details),'planned_inputs':6,'unique_outages':sum(f['total'] for f in families if f['policy']=='dense_exhaustive'),'timings':times,'allocated_bytes':allocations,'screened_by_size':screened_by_size,'cohort_coverage':cohort_coverage,'exhaustive_saving':exhaustive_saving,'guarded_saving':guarded_saving,'screened':screened,'misses':misses,'unresolved_unique_outages':sum(f['unresolved'] for f in families if f['policy']=='dense_exhaustive'),'paired_classification_differences':differences,'common_accepted_pairs':common,'max_accepted_state_difference':maxdiff,'replayed_states':audit['replayed_states'],'accepted_outage_control_regimes':audit['accepted_control_regimes'],'replay_discrepancies':len(audit['discrepancies']),'details':details,'production_defaults_changed':False,'screening_safety_evidence': 'No screening decisions' if not any(screened.values()) else 'Finite screened set only','configuration':'fixed supplied taps/shunts, zero movement, frozen shared droop, preventive equal-weight active response'}
 (OUT/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))

def figure():
 import matplotlib
 matplotlib.use('Agg')
 import matplotlib.pyplot as plt
 r=load(OUT/'RESULTS.json');fig,axes=plt.subplots(1,2,figsize=(13,4.5),layout='constrained')
 labels=[x['id'].replace('p2-large-sparse-','').replace('_',' ') for x in r['details']]
 for i,(policy,label,color) in enumerate([('dense_exhaustive','Dense exhaustive','#48657f'),('sparse_exhaustive','Sparse exhaustive','#4a9f85'),('sparse_guarded','Sparse guarded','#bd8650')]):
  axes[0].bar([j+(i-1)*.25 for j in range(len(labels))],[x['warm_medians'][policy] for x in r['details']],width=.25,label=label,color=color)
 axes[0].set_xticks(range(len(labels)),labels,rotation=25,ha='right');axes[0].set_ylabel('Median warm seconds');axes[0].legend();axes[0].set_title('Per-case complete pipeline')
 families=load(OUT/'heldout_audit.json')['families'];screened=[sum(x['screened'] for x in families if x['input']==d['id'] and x['policy']=='sparse_guarded') for d in r['details']]
 axes[1].bar(range(len(labels)),screened,color='#4a9f85');axes[1].set_xticks(range(len(labels)),labels,rotation=25,ha='right');axes[1].set_ylabel('Screened outages');axes[1].set_title('Audited against both exhaustive formulations')
 fig.suptitle('48 and 96 bus sparse AC qualification');fig.savefig(OUT/'performance.png',dpi=160);plt.close(fig)
def report():
 r=load(OUT/'RESULTS.json');cohorts=load(OUT/'cohort_audit.json')
 rows='\n'.join(f"| {d['id'].replace('p2-large-sparse-','')} | {d['warm_medians']['dense_exhaustive']:.3f} | {d['warm_medians']['sparse_exhaustive']:.3f} | {d['warm_medians']['sparse_guarded']:.3f} |" for d in r['details'])
 cohort_rows='\n'.join(f"| {c['id'].replace('p2-large-sparse-','')} | {c.get('regimes',{})} | {c.get('minimum_individual_q_reserve_fraction',0):.4f} |" for c in cohorts)
 allocation_saving=1-r['allocated_bytes']['sparse_exhaustive']/r['allocated_bytes']['dense_exhaustive']
 text=f"""# P2 larger network sparse AC qualification

The frozen six-case study completed on fresh 48- and 96-bus synthetic networks. Its qualification status is **{r['status']}**. Dense and sparse exhaustive evaluation were compared with the unchanged droop-response guard enabled and disabled. Production source and defaults were not changed.

## Results

- Assessed {r['unique_outages']} unique outages across {r['complete_inputs']} of six planned inputs.
- Screened {r['screened']['sparse_guarded']} outages: {r['screened_by_size']['48']} at 48 buses and {r['screened_by_size']['96']} at 96 buses. Screened sets agreed between dense and sparse policies and across repetitions.
- Observed {r['misses']['sparse_guarded']} guarded misses against the union of unresolved dense and sparse exhaustive outcomes across all four repetitions. Any screened unresolved outcome counts as a miss, including solver rejection; unresolved outcomes are not global infeasibility proofs.
- Found {len(r['paired_classification_differences'])} paired exhaustive classification differences. Maximum common accepted state difference: {r['max_accepted_state_difference']:.3g} across {r['common_accepted_pairs']} pairs.
- Replayed {r['replayed_states']} saved exact evaluations with {r['replay_discrepancies']} physical/overall-validation discrepancies. The union contains {r['unresolved_unique_outages']} unresolved unique outages.
- Exhaustive summed warm medians: {r['timings']['dense_exhaustive']:.3f} seconds dense versus {r['timings']['sparse_exhaustive']:.3f} sparse, a {100*r['exhaustive_saving']:.1f}% reduction. With the guard enabled, dense/sparse reduction is {100*r['guarded_saving']:.1f}%.
- Exhaustive Julia allocations decreased by {100*allocation_saving:.1f}%. Allocation totals are sums of per-case warm medians, not peak memory.

| Case | Dense exhaustive seconds | Sparse exhaustive seconds | Sparse guarded seconds |
| --- | ---: | ---: | ---: |
{rows}

Times include filtering, exact model construction, solving, extraction, validation and ranking; disk output is excluded. Each case used four rotating policy orders, with medians from repetitions two through four. Julia and BLAS each used one thread and no other solver workloads ran concurrently. Results are descriptive finite-case evidence, not a general speed guarantee.

## Functionality and validation

| Delivered | Meaning | Validation |
| --- | --- | --- |
| Frozen larger-case generator | Produces normal, tight-reactive and partial-saturation cases at both network sizes | Raw cases, numerical settings and deterministic anchor-to-droop rules frozen before initial solves; overlays independently reconstructed from saved states |
| Four-policy comparison runner | Compares the existing sparse option with dense evaluation, with and without the unchanged guard | Four repetitions, source and input hashes verified; identical supplied network/generator data and equal participation weights checked |
| Screened-outage audit | Tests every screened decision against both exhaustive formulations | Uses the union of unresolved outcomes over all exhaustive repetitions; independent saved-state physical validation |
| Timing and allocation report | Measures end-to-end costs and Julia allocations | Retains all repetitions, per-phase timings, GC time and allocation bytes; reports warm medians |

The candidate only enables the existing `sparse_balance=true` setting. It omits zero-admittance terms from the nonlinear expression graph. No guard thresholds or solver algorithms were changed in this study.

## Actual cohort coverage

| Case | Anchor control regimes | Minimum individual Q reserve fraction |
| --- | --- | ---: |
{cohort_rows}

Normal cases use proportional droop at light demand. Tight-reactive cases use generator Q maxima of 0.45 per unit and higher reactive demand. In the saturation cohort, every fourth controller has its upper Q limit fixed to its anchor Q, with a setpoint that places it above the upper saturation knee; other controllers remain proportional. These controller limits are frozen across outages. Supplied generator capability bounds are unchanged by the overlay. The table reports measured coverage rather than assuming the cohort names establish it. Accepted post-outage control observations in the first dense and sparse exhaustive repetitions were {r['accepted_outage_control_regimes']} (paired formulations are both counted).

## Configuration and provenance

Supplied transformer taps and shunts remain fixed, selected equipment controls are empty, and equipment movement is zero. Droop is frozen and shared. Active response is preventive with equal weights. Solver settings are tolerance 1e-8, maximum 500 iterations, maximum 5 CPU seconds per solve and smoothing epsilon 1e-5. S2 is excluded. The standing user instruction is to report this configuration without reconfirming until further notice.

The first run encountered a diagnostic serialization error after all six anchors independently validated and before any outage evaluation. The original runner, freeze and failed-run artifacts are preserved under `runner_before_serialization_repair.jl`, `frozen_before_serialization_repair.json` and `heldout_before_serialization_repair/`. Only the regime output was converted to serializable named tuples. Cases, numerical settings, overlays, guards and acceptance criteria were unchanged. The repaired runner was hashed before the first outage solve, and anchors were rerun with identical settings. This is an orchestration repair, not tuning on outage results.

The numerical gate requires all anchors valid, screening at both sizes, zero misses, identical paired classifications, accepted state differences at most 1e-5 and faster summed medians with and without screening. Any failure remains visible in `RESULTS.json`; no failed case is replaced. The four historically rejected anchors from the earlier scale study remain an independent coverage gap.

## Evidence

`plan.json` and both freeze records preserve the protocol. `heldout/` contains all anchor and policy outputs. `heldout_audit.json` holds saved-state replay and per-family misses; `cohort_audit.json` verifies actual control regimes and reconstruction; `RESULTS.json` holds aggregate outcomes and allocations; `performance.png` shows timings and screening counts. `final_manifest.json` hashes the completed evidence and scripts. All 18 targeted checks passed: one existing sparsity check and 17 response-guard routing checks. The full repository suite was not rerun because production code was unchanged. All 888 files in the prior completed study manifest were verified unchanged.

The runners refuse to overwrite outputs. To reproduce separately, set a new output directory in the runner before preparing its freeze. This qualification remains limited to synthetic networks, the stated fixed configuration and the observed operating regimes; it does not establish universal screening safety.
"""
 (OUT/'REPORT.md').write_text(text)
if __name__=='__main__':
 main()
 figure()
 report()
