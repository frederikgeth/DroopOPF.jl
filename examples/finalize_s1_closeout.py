"""Seal the completed scoped S1 study after audits, tests and documentation."""
from pathlib import Path
import json,hashlib
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'artifacts/s1_closeout'
load=lambda p:json.loads(p.read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
v=load(OUT/'validation.json');assert v['full_regression']['passed']==2876 and v['full_regression']['failed']==0;assert v['documentation']['status']=='passed'
a=load(OUT/'cleanup_checks.json');assert not a['retired_network_files'] and not a['broken_doc_links']
p=load(OUT/'profile_summary.json');assert len(p['groups'])==96 and all(r['accepted'] for r in p['groups'])
for n in (14,500):
 for folder in (ROOT/'artifacts/s1_free_droop'/str(n),OUT/'profile'/str(n)):
  a=load(folder/'independent_audit.json');assert a['discrepancies']==0
  rows=list((folder/'attempts').glob('*.json'));assert a['states_replayed']==len(rows)
# The provenance transition records only code/prose/registry updates; no physical input/result changed.
transition=load(OUT/'provenance_transition.json')
for r in transition['registries']:
 for c in r['changes']:
  q=c['path']
  if c.get('new_sha256'):assert not (q.startswith('test/data/arpae/') or '/attempts/' in q or '/models/' in q),q
removed=load(OUT/'removal_manifest.json')['files'];gone=[r for r in removed if not (ROOT/r['path']).exists()]
status=dict(status='closed',date='2026-10-15',scope='14/500 buses; Pmin0 symmetric Q; base-case AC; declared controls/anchors and sampled demands; bounded numerical recoveries',profile_combinations=96,profile_accepted_after_recovery=96,full_regression_passes=2876,independent_campaign_states=856,independent_profile_states=108,discrepancies=0,retired_files_still_absent=len(gone),retired_file_bytes_still_absent=sum(r['bytes'] for r in gone),limitations=['Original-Q fixed-equipment compatibility unresolved','Final 14-bus original-limit requalification outside scope','Profile reuses known same-model witnesses','No continuous-range, dynamic, global or N-1 guarantee'])
(OUT/'STATUS.json').write_text(json.dumps(status,indent=2)+'\n')
paths=[*OUT.rglob('*'),*(ROOT/'src').glob('*.jl'),*(ROOT/'test').glob('*.jl'),*(ROOT/'docs/src').glob('*.md'),ROOT/'docs/make.jl',ROOT/'README.md',ROOT/'ROADMAP.md',ROOT/'TRANSFORMER_SHUNT_PLAN.md',ROOT/'test/README.md',ROOT/'Project.toml',ROOT/'Manifest.toml']
paths += [ROOT/'examples'/n for n in ('s1_closeout_benchmark.jl','audit_s1_closeout.py','audit_s1_retirement.py','report_s1_closeout.py','migrate_s1_closeout_provenance.py','finalize_s1_closeout.py')]
(OUT/'manifest.json').write_text(json.dumps(dict(hashes={str(p.relative_to(ROOT)):sha(p) for p in sorted(set(paths)) if p.is_file() and p.name!='manifest.json'}),indent=2)+'\n')
print(json.dumps(status))
