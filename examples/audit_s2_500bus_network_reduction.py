"""Independent reconstruction plus every original-network operating gate."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import numpy as np
from analyse_s2_500bus_network_reduction import admittance, partition
from audit_s2_500bus_loadability import audit_point, load, BASE


def audit(folder,stage):
    folder=Path(folder)
    full=audit_point(folder,stage)  # stdlib replay of untouched original Case
    contract=load(folder/'contract.json')
    study=load(folder/f'controller-{stage}.json')['data']
    point=load(folder/f'point-{stage}.json')
    native_record=next(r for r in load(folder/'stages.json') if r['stage']==stage)
    assert point['record']==native_record, 'Primal point/native stage record mismatch'
    assert point['record']['native_success']==(native_record['status'] in ('LOCALLY_SOLVED','ALMOST_LOCALLY_SOLVED','OPTIMAL'))
    maps=load(folder/'network_reduction_maps.json')
    checks=[]
    for row in point['states']:
        candidates=[r for r in maps if r['factor']==row['factor'] and r['id']==row['id']]
        if contract['fixed_base'] and row['id']=='base':
            assert not candidates
            continue
        record=candidates[0]['reduction'];case=copy.deepcopy(study['case']);post=row['id']!='base'
        kept,eliminated=partition(load(BASE/'pilot_study.json')['data'],record.get('elimination_mode','all'))
        if post:
            kind,num=row['id'].split('_')
            family=case['network']['branches'] if kind=='branch' else case['generators']
            next(b for b in family if b['id']==int(num))['available']=False
        if post and contract['emergency']:
            for b in case['network']['branches']:b['thermal_limit']*=contract['thermal_multiplier']
        ids=[b['id'] for b in case['network']['buses']]
        assert record['retained_bus_ids']==[ids[i] for i in kept]
        assert record['eliminated_bus_ids']==[ids[i] for i in eliminated]
        expected=[b for b in case['network']['branches'] if b['available']]
        assert record['original_online_branch_ids']==[b['id'] for b in expected]
        assert record['original_branch_ratings']=={str(b['id']):b['thermal_limit'] for b in expected}
        y=admittance(case,row['taps'],row['banks'])
        h=-np.linalg.solve(y[np.ix_(eliminated,eliminated)],y[np.ix_(eliminated,kept)])
        stored=np.zeros_like(h)
        for t in record['reconstruction']:stored[t['row']-1,t['column']-1]=complex(t['real'],t['imag'])
        map_error=float(np.max(abs(h-stored)))
        v=np.array(row['state']['vm'])*np.exp(1j*np.array(row['state']['va']))
        error=float(np.max(abs(v[eliminated]-h@v[kept])))
        current_error=float(np.max(abs((y@v)[eliminated])))
        checks.append(dict(factor=row['factor'],id=row['id'],retained_buses=len(kept),eliminated_buses=len(eliminated),
            map_error_max=map_error,reconstruction_error_max_pu=error,eliminated_current_residual_max_pu=current_error,
            original_online_branches=len(expected),original_ratings_verified=True,
            valid=map_error<=1e-10 and error<=1e-8 and current_error<=1e-6))
    reduction_valid=all(r['valid'] for r in checks)
    result=dict(accepted=bool(full['accepted'] and reduction_valid),native_success=full['native_success'],
        diagnostic_accepted=bool(full.get('diagnostic_accepted',False) and reduction_valid),
        response_free_physical_valid=full.get('response_free_physical_valid',full['physical_valid']),
        original_full_network_valid=full['physical_valid'],reduction_valid=reduction_valid,
        full_audit=f'audit-{stage}.json',checks=checks,
        auditor_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        maps_sha256=hashlib.sha256((folder/'network_reduction_maps.json').read_bytes()).hexdigest())
    (folder/f'network-audit-{stage}.json').write_text(json.dumps(result,indent=2)+'\n')
    return result


if __name__=='__main__':
    r=audit(sys.argv[1],sys.argv[2]);print(json.dumps({k:v for k,v in r.items() if k!='checks'},indent=2))
