"""Reject corrupted batched witnesses using the same independent physical audit."""
import copy,json,tempfile
from pathlib import Path
from audit_p2_s2_numerics import audit
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/p2_s2_multidemand_20261022'
source=OUT/'frozen-zero/stage-1/500/progressive/round-1/scan/batch-2/primary'
assert audit(source)['accepted']
files={n:json.loads((source/n).read_text()) for n in ('controller-solve.json','point-solve.json','contract.json')}
def reject(name,mutation):
    data=copy.deepcopy(files);mutation(data)
    with tempfile.TemporaryDirectory(prefix='p2-md-audit-') as d:
        p=Path(d)
        for n,v in data.items():(p/n).write_text(json.dumps(v))
        try:accepted=audit(p)['accepted']
        except (AssertionError,KeyError,ValueError,StopIteration):accepted=False
        assert not accepted,name
    return name
names=[]
names.append(reject('missing_batch_member',lambda f:f['contract.json']['outages'].pop()))
names.append(reject('wrong_demand_label',lambda f:f['point-solve.json']['states'][-1].__setitem__('factor',.91)))
names.append(reject('shared_controller_drift',lambda f:f['controller-solve.json']['data']['case']['controls'][0].__setitem__('slope',1.)))
names.append(reject('native_failure_flag',lambda f:f['point-solve.json']['record'].__setitem__('native_success',False)))
r={'accepted_original_batch':True,'rejected_corruptions':names}
(OUT/'batch-audit-tests.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))
