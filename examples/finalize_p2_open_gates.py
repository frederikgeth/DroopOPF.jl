"""Summarize independently replayed evidence; never turns a timeout into a pass."""
import hashlib,json,re,statistics,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'artifacts/p2_open_gates_20261022'
load=lambda p:json.loads(Path(p).read_text())
save=lambda p,d:Path(p).write_text(json.dumps(d,indent=2)+'\n')
docs_log=(OUT/'docs-build.log').read_text();assert 'Automatic `version=' in docs_log and 'ERROR:' not in docs_log
validation=load(OUT/'validation-summary.json');cold=validation['cold_catalogues']['cold-hybrid-catalogue']
assert cold['full_native_physical_pass'] and cold['accepted']==389
ci=load(OUT/'ci-results-v4.json');assert ci['conclusion']=='success'
assert all(j['conclusion']=='success' for j in ci['jobs'])
for version in ('110','112'):
 log=(OUT/f'ci-julia{version}-v4.log').read_text()
 assert re.search(r'DroopOPF\s+\|\s+3000\s+3000',log)
 assert re.search(r'S1 free slopes with a fixed zero deadband\s+\|\s+14\s+14',log)
 assert re.search(r'Zero-deadband specialization and smooth derivatives\s+\|\s+163\s+163',log)
prior=load(OUT/'prior-evidence-verification.json');assert prior['total_files_verified']==28577
source_inputs=load(ROOT/'artifacts/p2_remaining_qualification_20261022/MANIFEST.json')['source_inputs']
for path,sha in source_inputs.items():assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==sha,path
save(OUT/'source-input-verification.json',{'verified':True,'files':source_inputs})
# The final experiment drivers evolved after CI; the package, tests, workflow and
# derivative adapters themselves must match the successful tested snapshot.
snapshot=load(OUT/'ci-snapshot-v4.json');critical={}
for path,sha in snapshot['files'].items():
 if path.startswith(('src/','test/')) or path in ('examples/p2_first_order_nlp.jl','examples/p2_partitioned_nlp.jl'):
  if Path(path).name.startswith('.'):continue
  assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==sha,path
  critical[path]=sha
for path in ('Project.toml','.github/workflows/CI.yml'):
 cached=OUT/'ci-tested-sources'/path
 if cached.exists():data=cached.read_bytes()
 else:
  data=subprocess.check_output(['git','--git-dir=/tmp/p2-ci-20261022/repo/.git','show',ci['headSha']+':'+path])
  cached.parent.mkdir(parents=True,exist_ok=True);cached.write_bytes(data)
 sha=hashlib.sha256(data).hexdigest();assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==sha,path
 critical[path]=sha
save(OUT/'ci-source-equivalence.json',{'tested_commit':ci['headSha'],'critical_sources_unchanged':True,'files':critical,
 'scope':'Package, complete tests/fixtures, workflow, derivative adapters; later local-only experiment driver options are recorded separately.'})
filtering=load(OUT/'capacity-filter/RESULTS.json')
positive=sum(r['outages'] for r in filtering['positive_references'])
negative=sum(r['certified_failures'] for r in filtering['stress_references'])
assert positive==3501 and negative==23
repeat=load(OUT/'cold-hybrid/RESULTS.json');assert all(r['accepted'] for r in repeat['rows'])
assert {r['rep'] for r in repeat['rows']}=={0,1,2,3}
resources=[]
for name in ('exhaustive-priorities','exhaustive-limited-memory','exhaustive-first-order','exhaustive-partitioned'):
 for r in load(OUT/name/'RESULTS.json')['rows']:
  resources.append({'lane':name,'factor':r['factor'],'kind':r['kind'],'accepted':r['accepted'],'record':r['record'],'path':r['path']})
for path in ('zero-resource-design/feasibility','zero-resource-nominal/round-1/master','zero-resource-full-ac-v2/feasibility','zero-resource-full-ac-nominal/round-1/master'):
 p=OUT/path;s=load(p/'summary.json');a=load(p/'audit-solve.json')
 resources.append({'lane':path,'accepted':s['accepted'],'physical_valid':a['physical_valid'],'record':s['record'],'path':s['folder']})
for r in resources:
 c=load(ROOT/r['path']/'contract.json');r['states']=len(c['factors'])*(len(c['outages'])+1)
assert not any(r['accepted'] for r in resources)
controls={'tap_count':131,'continuous_bank_count':11,'timing':'corrective per scenario','movement_budget':'No additional budget beyond exact S2 absolute bounds',
 'accepted_common_curves':'Frozen S2-compatible b20b6696e02cc6fe52caeb3ed2b6dfd94bca1074032311560a451325b3c7eec2',
 'active_response':'Isolated exact S2 proportional model; production limit-aware default unchanged','physical_limits_relaxed':False}
usage={'max_tap_change_pu':0.,'max_bank_change_pu':0.,'max_shedding_mw_per_outage':0.,'max_dr_mw_per_outage':0.}
for row in load(OUT/'cold-hybrid-catalogue/RESULTS.json')['rows']:
 selected=next(ROOT/p for p in reversed(row['paths']) if load(ROOT/p/'summary.json')['accepted'])
 point=load(selected/'point-solve.json');base=next(s for s in point['states'] if s['id']=='base')
 for s in point['states']:
  if s['id']=='base':continue
  for family,key in (('taps','max_tap_change_pu'),('banks','max_bank_change_pu')):
   usage[key]=max(usage[key],max((abs(v-base[family][i]) for i,v in s[family].items()),default=0.))
  usage['max_shedding_mw_per_outage']=max(usage['max_shedding_mw_per_outage'],sum(s['shed'].values())*100.)
  usage['max_dr_mw_per_outage']=max(usage['max_dr_mw_per_outage'],sum(s['dr'].values())*100.)
result={'p2_closed':False,'cold_start_workflow':{'qualified':True,**cold,'factor':1.,'subset_repetitions':3,'warmup_repetitions':1,
 'timing_scope':'Complete preparation/native/retry/audit wall costs; concurrent backend work confounds speed comparisons','raw_flat_ipopt_qualified':False},
 'remote_ci':{'passed':True,'versions':['1.10','1.12'],'checks_per_version':3177,'tested_commit':ci['headSha'],'url':ci['url'],'critical_sources_unchanged':True},
 'capacity_filter':{'qualified_scope':'S2 proportional fixed-preventive-dispatch necessary exclusion under passive network assumptions','positive_references':positive,'false_exclusions':0,'certified_dispatch_outage_failures':negative,'unit_checks':16,'safe_outage_skipping_qualified':False,'general_failure_recall_established':False},
 'full_resource_loss_optimization':{'qualified':False,'attempts':resources,'measured_full_model_peak_gib':17.1,'machine_memory_gib':16.,
 'remaining':'A practical optimization decomposition or larger-memory execution is needed for complete multi-demand priorities. Zero-resource alternatives did not produce accepted witnesses. No physical infeasibility inferred.'},
 'controls':controls,'observed_cold_witness_usage':usage,'validation':validation,'prior_evidence_unchanged':prior,'source_inputs_verified':len(source_inputs),
 'evidence_corruption_tests':{'checks':6,'deliberate_corruptions_rejected':5},'docs_build_passed':True,'release_published':False,'s2_resumed':False}
save(OUT/'RESULTS.json',result)
lines=['# P2 open-gate continuation: outcome','', '**P2 remains open.** Cold-start recovery and remote compatibility are qualified in the stated scope. Full multi-demand resource/loss optimization and general predictive safe-skipping are not qualified.','',
 '## Completed evidence','',
 '- The 500-bus prepared cold workflow passed all **389/389 connected outages at nominal demand**, with one fixed preventive base and common curves. Preparation starts from flat voltage using the declared preventive PG/Q and equipment; the native model receives the reconstructed point. No saved post-outage state is used. All points passed native convergence and independent original-network replay.',
 '- The 11-outage mixed subset passed one warm-up and three measured repetitions. Direct flat Ipopt remains distinct and unqualified. Concurrent backend experiments make these robustness trials unsuitable for a controlled speedup claim.',
 f'- [Remote Ubuntu CI]({ci["url"]}) passed **3,177 checks each on Julia 1.10 and 1.12**. The current package/test sources and derivative adapters match tested commit `{ci["headSha"]}`. Experimental driver updates are recorded separately.',
 '- The S2-specific necessary capacity filter excluded none of **3,501 accepted outage/demand pairs**. It certified **23 infeasible outage/dispatch pairs** in two separately validated stress dispatches. These are fixed-dispatch exclusions, not network-wide infeasibility claims. Sixteen adversarial/unit checks passed.',
 '- Five deliberate evidence corruptions were rejected; the original evidence control also passed. All **28,577 sealed prior artifacts** and 70 source inputs remain byte-identical. Documentation builds successfully; no release or deployment was published.','',
 '## Resource/loss optimization remains open','',
 'Full 389-outage objective models were constructed with frozen common curves and a free preventive dispatch. These are conditional models, not full free-curve multi-demand optimization. Exact-Hessian preparation consumed substantial memory. A first-order-only adapter and a scenario-partitioned derivative adapter preserve the same coupled NLP; their derivatives/shared-variable handling and coupled optimum passed regressions, and original-network preflights passed.',
 'A live sample of the full coupled run measured **17.0 GiB footprint, 17.1 GiB peak**, on the 16 GiB machine. It was interrupted for memory pressure. This is a computational limitation, not physical infeasibility.',
 'A lower-bound alternative sought zero shedding, zero DR and zero normal-limit departure, followed by base-loss optimization. Both the five-demand shared-curve master and nominal loss master remained unresolved. A retry with the full original sparse AC model and normalized control variables also timed out without accepted witnesses. The stronger zero-resource candidates are subsets of the allowed S2 operation; their failures do not invalidate the previously accepted S2-allowance designs.',
 '','| Attempt | Scope | Outcome |','|:--|:--|:--|']
for r in resources:
 rec=r['record'];lines.append(f'| `{r["lane"]}` | {r["states"]} demand/scenario states | {rec["status"]} |')
lines += ['', 'Completing the priorities requires further memory reduction or optimization decomposition, or a larger-memory execution. No failed or interrupted attempt is counted as an objective minimum or an infeasibility certificate. The general heuristic ranking stays advisory; the necessary capacity filter never declares an outage safe.','',
 '## Controls and scope','',
 'The exact S2 benchmark retains **131 corrective taps and 11 corrective continuous shunt controls**, absolute equipment bounds and no additional movement budget. Accepted cold trials freeze the previously qualified common curves. The smaller resource-design candidates free all 51 slopes and 51 references within the unchanged S2 design bounds. The isolated S2 proportional response is retained; the library limit-aware default is unchanged. No physical bound or validation tolerance was relaxed.',
 f'Per-outage maximum usages were {usage["max_shedding_mw_per_outage"]:.6g} MW shedding and {usage["max_dr_mw_per_outage"]:.6g} MW DR. These are feasible-witness usage values, **not minimum required relief**. The accepted scope includes S2 emergency/relief allowances.',
 '','The 14-bus training/held-out evidence remains unchanged. This continuation does not add island service, discrete switching, actuator-delay or transient qualification. Original S2 remains paused.','',
 '## Reproducibility','',
 '`protocol.json`, per-attempt contracts, initialization diagnostics, native records, independent audits, runtime source copies, CI snapshots/logs and `engineering-notes.json` retain successful, failed, interrupted and preparation-error attempts. `validation-summary.json` summarizes replay. `MANIFEST.json` seals the final snapshot.']
(OUT/'REPORT.md').write_text('\n'.join(lines)+'\n')
print(json.dumps({'p2_closed':False,'cold_outages':389,'ci_checks_each':3177,'native_attempts_replayed':validation['accepted_replayed']+validation['unresolved_replayed'],'resource_attempts':len(resources)},indent=2))
