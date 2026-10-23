"""Mutation guards for original-network acceptance and reduction records."""
import json
from pathlib import Path
import shutil
import tempfile
from audit_s2_500bus_network_reduction import audit, BASE

out=BASE/'network_reduction';source=out/'refined-regression-1.05';results=[]
for mutation in ('baseline','map_coefficient','rating_identity','voltage_reconstruction','native_record','original_source'):
    with tempfile.TemporaryDirectory(prefix='nr-acceptance-') as td:
        p=Path(td)
        for name in ('contract.json','stages.json','controller-feasibility.json','point-feasibility.json','network_reduction_maps.json'):
            shutil.copyfile(source/name,p/name)
        if mutation in ('map_coefficient','rating_identity'):
            f=p/'network_reduction_maps.json';d=json.loads(f.read_text())
            if mutation=='map_coefficient':d[0]['reduction']['reconstruction'][0]['real']+=.01
            else:
                k=next(iter(d[0]['reduction']['original_branch_ratings']));d[0]['reduction']['original_branch_ratings'][k]*=1.1
            f.write_text(json.dumps(d))
        if mutation in ('voltage_reconstruction','native_record'):
            f=p/'point-feasibility.json';d=json.loads(f.read_text())
            if mutation=='voltage_reconstruction':d['states'][0]['state']['vm'][0]+=.01
            else:d['record']['native_success']=False
            f.write_text(json.dumps(d))
        if mutation=='original_source':
            f=p/'controller-feasibility.json';d=json.loads(f.read_text())
            d['data']['case']['network']['branches'][0]['thermal_limit']*=1.1
            f.write_text(json.dumps(d))
        try:
            ck=audit(p,'feasibility');accepted=ck['accepted']
        except AssertionError:
            accepted=False
        assert accepted==(mutation=='baseline'),mutation
        results.append(dict(mutation=mutation,accepted=accepted,passed=True))
(out/'audit_guard_checks.json').write_text(json.dumps(results,indent=2)+'\n')
print(results)
