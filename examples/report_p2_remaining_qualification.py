import os
"""Summarize bounded P2 qualification without promoting unresolved gates."""
import json,statistics,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=Path(os.environ.get('P2_QUALIFICATION_OUTPUT',str(ROOT/'artifacts/p2_remaining_qualification_20261022')))
def load(p):return json.loads(p.read_text())
def optional(p):return load(OUT/p) if (OUT/p).exists() else None
def phases(row):
 if 'build_seconds' in row:return row['build_seconds'],row['solve_seconds']
 records=row.get('records')
 if records is None:
  records=[]
  for rel in row.get('paths',[row.get('path')]):
   if not rel:continue
   folder=ROOT/rel
   for p in folder.rglob('stages.json'):records.extend(load(p))
 return sum(r['build_seconds'] for r in records),sum(r['solve_seconds'] for r in records)
result={'heldout_500':optional('heldout-500/cross-demand-audit.json'),'heldout_14':optional('heldout-14/RESULTS.json'),'filtering':optional('filtering/RESULTS.json'),'priorities':optional('priorities/RESULTS.json'),'regressions':optional('regression-results.json'),'fullcatalog_repeats':optional('fullcatalog-repeat/RESULTS.json'), 'ranking':optional('ranking-results.json'),'combined_coverage':optional('COMBINED_DEMAND_COVERAGE.json'),'independent_audit':optional('independent-audit.json'),'warm_recovery':optional('warm-recovery/RESULTS.json')}
for name in ('benchmarks','comparison','progressive-reference','design-14'):
 d=optional(name+'/RESULTS.json')
 if d:
  groups={}
  for row in d['rows']:
   if row['warmup']:continue
   key=(row.get('size',d.get('case_size',500)),row.get('initialization',row.get('method')))
   groups.setdefault(key,[]).append(row)
  result[name]={'raw':d,'actual_outage_counts':sorted({len(r['events']) for r in d['rows'] if 'events' in r}), 'groups':[{'case_size':k[0],'policy':k[1],'repetitions':len(v),'accepted':sum(r['accepted'] for r in v),'median_build_seconds':statistics.median(phases(r)[0] for r in v),'median_solve_seconds':statistics.median(phases(r)[1] for r in v),'outages_per_trial':sorted({len(r['events']) for r in v if 'events' in r}),'median_wall_seconds':statistics.median(r['wall_seconds'] for r in v),'min_wall_seconds':min(r['wall_seconds'] for r in v),'max_wall_seconds':max(r['wall_seconds'] for r in v)} for k,v in groups.items()]}
held500=result['heldout_500'];held14=result['heldout_14']
bench_rows=result.get('benchmarks',{}).get('raw',{}).get('rows',[])
init_pass=sum(not r['warmup'] for r in bench_rows)==24 and all(r['accepted'] for r in bench_rows if not r['warmup'])
def complete_group(name,total):
 rows=result.get(name,{}).get('raw',{}).get('rows',[])
 return len(rows)==total and all(r['accepted'] for r in rows if not r['warmup'])
gates=[{'gate':'500-bus frozen-controller held-out demands','status':'passed' if held500 and len(held500['accepted_factors'])==4 else 'unresolved'},
 {'gate':'14-bus frozen-controller held-out demands','status':'passed' if held14 and len(held14['rows'])==4 and all(r['accepted'] for r in held14['rows']) else 'unresolved'},
 {'gate':'Repeated initialization measurements','status':'measured; see accepted counts' if result.get('benchmarks') else 'not completed'},
 {'gate':'Repeated matched enumeration comparisons','status':'passed: full 14-bus catalogue and 12-outage 500-bus subset' if complete_group('comparison',16) else 'unresolved'},
 {'gate':'500-bus progressive/full reference','status':'passed: fixed curves, 12-outage subset' if complete_group('progressive-reference',8) else 'unresolved'},
 {'gate':'14-bus full/progressive shared-curve loss design','status':'passed: five demands, all 24 outages' if complete_group('design-14',8) else 'unresolved'},
 {'gate':'Predictive ranking/filtering under corrective S2 policy','status':'conservative exact fallback; general predictive qualification open'},
 {'gate':'Repeated exhaustive 500-bus evaluation','status':'passed' if result['fullcatalog_repeats'] and len(result['fullcatalog_repeats']['rows'])==3 and all(r['accepted'] for r in result['fullcatalog_repeats']['rows']) else 'unresolved'},
 {'gate':'Pure flat initialization on 500 buses','status':'passed' if init_pass else 'unresolved; native failures retained'},
 {'gate':'Explicit base-state recovery after flat failure','status':'passed on declared subset' if result['warm_recovery'] and len(result['warm_recovery']['rows'])==3 and all(r['accepted'] for r in result['warm_recovery']['rows']) else 'unresolved'},
 {'gate':'Five-outage S2 priority pilot','status':'passed staged native/physical/cap checks' if result['priorities'] and len(result['priorities']['rows'])==4 and all(r['accepted'] for r in result['priorities']['rows']) else 'unresolved'},
 {'gate':'Full S2 lexicographic optimization','status':'open; bounded resource pilot is not exhaustive priority completion'},
 {'gate':'Stable research release/remote CI','status':'open; local regression results do not establish remote CI passage'}]
result['gates']=gates;result['p2_closed']=False;result['source_s2_resumed']=False
(OUT/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
lines=['# Remaining P2 qualification attempts','','Fresh evidence under exact S2 data/control semantics. Original S2 and prior sealed P2 records remain unchanged.','','| Gate | Outcome |','|---|---|']
lines += [f"| {r['gate']} | {r['status']} |" for r in gates]
if held500:lines += ['',f"500-bus held-out factors: {held500['accepted_factors']}; {held500['unique_validated_states']} independently validated states; controller identity {held500['controller_sha256']}. S2 relief including up to 10 MW shedding is permitted."]
if held14:lines += ['',f"14-bus held-out factors accepted: {[r['factor'] for r in held14['rows'] if r['accepted']]}; 24 connected outages per demand; no relief."]
if result['fullcatalog_repeats']:
 lines += ['', '## Exhaustive 500-bus repeatability', '', '| Pass | Accepted outages | Total active wall seconds | Deferred singleton fallback seconds |', '|---:|---:|---:|---:|']
 for r in result['fullcatalog_repeats']['rows']:
  lines.append(f"| {r['rep']} | {r['accepted_outages']}/389 | {r['wall_seconds']:.3f} | {r.get('fallback_wall_seconds',0)+r.get('additional_start_repair_seconds',0):.3f} |")
 lines += ['', 'Each pass uses fresh native solves at 100% with the same fixed base and curves. Failed pairs and their retries remain. Deferred singleton fallbacks are additional measurement segments; total active wall cost includes them. These are warm evaluations with matching accepted scenario starts.']
if result['warm_recovery']:
 lines += ['', '## Explicit recovery from flat starts', '', '| Repetition | Accepted | Added base-start seconds | Total including failed flat workflow |', '|---:|---|---:|---:|']
 for r in result['warm_recovery']['rows']:
  lines.append(f"| {r['rep']} | {r['accepted']} | {r['base_fallback_seconds']:.3f} | {r['total_active_wall_seconds']:.3f} |")
 lines += ['', 'Pure-flat trials remain failed. Recovery uses a different, declared initialization and preserves every physical bound and the frozen base/controller.']
for name in ('benchmarks','comparison','progressive-reference','design-14'):
 if name in result:
  lines += ['',f'## {name}','','Warm-up excluded. Wall time includes building, solving, serialization and physical replay. Failed attempts remain in timing summaries. These are local observations.','','| Buses | Policy | Accepted / repetitions | Median wall seconds | Build / solve medians | Range |','|---:|---|---:|---:|---|---|']
  for g in result[name]['groups']:lines.append(f"| {g['case_size']} | {g['policy']} | {g['accepted']}/{g['repetitions']} | {g['median_wall_seconds']:.3f} | {g['median_build_seconds']:.3f} / {g['median_solve_seconds']:.3f} | {g['min_wall_seconds']:.3f}–{g['max_wall_seconds']:.3f} |")
lines += ['','## Interpretation','','Held-out curves are frozen; preventive dispatch and corrective continuous equipment retain their declared S2 freedom. Finite samples do not certify every intermediate demand, islanded service, actuator timing or transient security. Unsupported filtering routes receive exact solves. No physical limits, response equation or independent physical-validation tolerances are relaxed.','','The initial neighbouring-start preparation error and restarted measurements are retained in benchmarks-preparation-error and initialization-repair.json. The benchmark samples contain 10 outages on 14 buses and 11 on 500 buses; exact IDs are recorded. Flat fallback is deferred and stops each repetition after its first unresolved singleton. Timings include all those failed calls.', '',
          'P2 remains open where the evidence above does not meet the broader declared gate. Certified capacity exclusions remain completed negative tests, and numerical failures remain unresolved. ExaModels/distributed decomposition remain conditional engineering options rather than mandatory implementation tasks.']
(OUT/'REPORT.md').write_text('\n'.join(lines)+'\n')
print(json.dumps({'gates':gates},indent=2))
