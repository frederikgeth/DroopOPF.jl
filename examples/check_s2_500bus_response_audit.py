"""Ensure relaxed response cannot escape the original-network acceptance gate."""
import json
from pathlib import Path
import shutil
import tempfile
from audit_s2_500bus_network_reduction import audit, BASE

source=BASE/'network_reduction/refined-regression-1.05'
out=BASE/'response_continuation'
results=[]
for name,cap,deviation,ac_error,expected in [
    ('baseline',0.,0.,False,(True,False)),
    ('diagnostic_exact',1.,0.,False,(False,True)),
    ('diagnostic_deviation',1.,.1,False,(False,True)),
    ('exact_rejects_deviation',0.,.1,False,(False,False)),
    ('cap_rejects_deviation',.0001,.1,False,(False,False)),
    ('diagnostic_rejects_ac_error',1.,0.,True,(False,False))]:
    with tempfile.TemporaryDirectory(prefix='response-acceptance-') as td:
        p=Path(td)
        for file in ('contract.json','stages.json','controller-feasibility.json',
                     'point-feasibility.json','network_reduction_maps.json'):
            shutil.copyfile(source/file,p/file)
        f=p/'contract.json';d=json.loads(f.read_text());d['response_relaxation_cap']=cap
        f.write_text(json.dumps(d))
        f=p/'point-feasibility.json';d=json.loads(f.read_text())
        if deviation:
            post=next(s for s in d['states'] if s['id']!='base')
            post['delta']+=deviation
        if ac_error:d['states'][1]['state']['vm'][0]+=.01
        f.write_text(json.dumps(d))
        ck=audit(p,'feasibility')
        actual=(ck['accepted'],ck.get('diagnostic_accepted',False))
        assert actual==expected,(name,actual,expected)
        results.append(dict(case=name,accepted_original=actual[0],
                            accepted_diagnostic=actual[1],guard_passed=True))
out.mkdir(parents=True,exist_ok=True)
(out/'response_audit_guard_checks.json').write_text(json.dumps(results,indent=2)+'\n')
print(results)
