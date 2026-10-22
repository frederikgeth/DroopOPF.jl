"""Corruption tests against a real independently accepted 14-bus witness."""
import copy,json,tempfile
from pathlib import Path
from audit_p2_s2_numerics import audit
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'artifacts/p2_s2_implementation_20261022/14/full'
def check(name,mutate,source=SOURCE):
    with tempfile.TemporaryDirectory(prefix='p2-audit-') as d:
        p=Path(d)
        files={n:json.loads((source/n).read_text()) for n in ('contract.json','controller-solve.json','point-solve.json')}
        mutate(files)
        for n,v in files.items():(p/n).write_text(json.dumps(v))
        try: accepted=audit(p)['accepted']
        except (AssertionError,KeyError,ValueError,StopIteration):accepted=False
        assert not accepted,name
        return name
point=lambda f:f['point-solve.json']
post=lambda f:next(r for r in point(f)['states'] if r['id']!='base')
rejected=[]
rejected.append(check('response_signal',lambda f:post(f).__setitem__('delta',post(f)['delta']+1)))
rejected.append(check('AC_state',lambda f:post(f)['state']['vm'].__setitem__(0,2.)))
rejected.append(check('equipment_bound',lambda f:post(f)['taps'].__setitem__(next(iter(post(f)['taps'])),5.)))
rejected.append(check('unallowed_relief',lambda f:post(f)['dr'].__setitem__(next(iter(post(f)['dr'])),1.)))
rejected.append(check('missing_outage',lambda f:point(f)['states'].pop()))
rejected.append(check('duplicate_state',lambda f:point(f)['states'].append(copy.deepcopy(point(f)['states'][0]))))
rejected.append(check('native_failure',lambda f:point(f)['record'].__setitem__('native_success',False)))
rejected.append(check('response_policy',lambda f:f['contract.json'].__setitem__('active_response','limit_aware_v1')))
rejected.append(check('relaxation',lambda f:post(f).__setitem__('artificial_max_pu',1.)))
rejected.append(check('nonfinite_state',lambda f:post(f)['state']['vm'].__setitem__(0,float('nan'))))
scan_source=next(p.parent for p in (SOURCE.parent/'progressive/round-3/scan').rglob('summary.json') if json.loads(p.read_text())['accepted'])
rejected.append(check('fixed_base_drift',lambda f:next(r for r in point(f)['states'] if r['id']=='base')['state']['pg'].__setitem__(0,10.),scan_source))
rejected.append(check('fixed_controller_drift',lambda f:f['controller-solve.json']['data']['case']['controls'][0].__setitem__('slope',1.),scan_source))
assert audit(SOURCE)['accepted']
result={'passed':True,'accepted_original':True,'rejected_corruptions':rejected}
(ROOT/'artifacts/p2_s2_implementation_20261022/audit-tests.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
