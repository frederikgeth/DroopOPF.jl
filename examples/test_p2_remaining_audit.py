"""Corrupt real accepted witnesses to test the new evidence gates."""
import copy,json,os,shutil,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'examples'))
OUT=Path(os.environ.get('P2_QUALIFICATION_OUTPUT',str(ROOT/'artifacts/p2_remaining_qualification_20261022')))
source=ROOT/'examples/audit_p2_remaining_qualification.py'
namespace={'__file__':str(source)}
exec(compile(source.read_text().split("result={'accepted_replayed'")[0],str(source),'exec'),namespace)
check=namespace['check_folder'];load=lambda p:json.loads(p.read_text())
flat=OUT/'benchmarks/14/rep-1/flat'
priority=ROOT/next(r for r in load(OUT/'priorities/RESULTS.json')['rows'] if r['kind']=='loss')['path']
passed=[]
with tempfile.TemporaryDirectory(prefix='p2-qualification-negative-') as temp:
 temp=Path(temp)
 for name,original,filename,mutate in [
  ('flat_log_drift',flat,'initialization.json',lambda d: next(r for r in d['states'] if r['id']!='base')['vm'].__setitem__(0,.99)),
  ('preventive_base_drift',flat,'contract.json',lambda d:d['fixed_base_reference'][0]['state']['pg'].__setitem__(0,d['fixed_base_reference'][0]['state']['pg'][0]+.01)),
  ('controller_drift',flat,'controller-solve.json',lambda d:d['data']['case']['controls'][0].__setitem__('slope',d['data']['case']['controls'][0]['slope']*1.01)),
  ('missing_outage',flat,'point-solve.json',lambda d:d['states'].pop()),
  ('resource_cap_drift',priority,'contract.json',lambda d:d['resource_caps'].__setitem__('shedding',0.))]:
  folder=temp/name;shutil.copytree(original,folder)
  assert check(folder)['accepted'],f'Original fixture failed: {name}'
  p=folder/filename;d=load(p);mutate(d);p.write_text(json.dumps(d))
  try:check(folder)
  except AssertionError:passed.append(name)
  else:raise AssertionError(f'Corruption accepted: {name}')
 folder=temp/'native_status_mismatch';shutil.copytree(flat,folder)
 assert check(folder)['accepted']
 for filename in ('point-solve.json','summary.json','stages.json'):
  p=folder/filename;d=load(p);record=d[-1] if isinstance(d,list) else d['record']
  record['status']='TIME_LIMIT';p.write_text(json.dumps(d))
 try:check(folder)
 except AssertionError:passed.append('native_status_mismatch')
 else:raise AssertionError('Inconsistent native success accepted')
r={'original_fixtures_passed':True,'rejected_corruptions':passed}
(OUT/'audit-negative-tests.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
