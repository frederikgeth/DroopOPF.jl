"""Optimizer-free mutation guards for native, full-network and reduction gates."""
import copy
import json
from pathlib import Path
import shutil
import tempfile
from audit_s2_500bus_solver_demand import audit,campaign,OUT,load

def main():
    phase=load(OUT/'solver_demand_qualification/summary-ipopt-10000.json')
    source=OUT/phase['selected'];checks=[]
    with tempfile.TemporaryDirectory(prefix='s2-sdq-audit-',dir='/tmp') as tmp:
        folder=Path(tmp)
        names=['summary.json','optimized-1.0.json','result-1.0.json','network_reduction_maps.json']
        original={n:load(source/n) for n in names}
        def write(values):
            for n,v in values.items():(folder/n).write_text(json.dumps(v))
        write(original);audit(folder);assert load(folder/'independent-audit.json')['accepted']
        checks.append(dict(name='accepted_original_point',passed=True))
        values=copy.deepcopy(original);values['summary.json']['solver_status']='TIME_LIMIT';values['summary.json']['native_success']=False
        values['result-1.0.json']['data']['termination_status']='TIME_LIMIT'
        write(values);audit(folder);assert not load(folder/'independent-audit.json')['accepted']
        checks.append(dict(name='physically_valid_timeout_not_accepted',passed=True))
        values=copy.deepcopy(original);values['result-1.0.json']['data']['states']['base']['pg'][0]+=.001
        write(values);audit(folder);assert not load(folder/'independent-audit.json')['accepted']
        checks.append(dict(name='AC_balance_corruption_rejected',passed=True))
        for label,mutate in [('rating',lambda d:d['network_reduction_maps.json'][0]['reduction']['original_branch_ratings'].update({'1':999.})),
                             ('native_flag',lambda d:d['summary.json'].update(native_success=False))]:
            values=copy.deepcopy(original);mutate(values);write(values)
            try:audit(folder)
            except AssertionError:pass
            else:raise AssertionError(label+' corruption accepted')
            checks.append(dict(name=label+'_corruption_rejected',passed=True))
    with tempfile.TemporaryDirectory(prefix='s2-sdq-graph-',dir='/tmp') as tmp:
        root=Path(tmp);master=root/'round-1/master';master.mkdir(parents=True)
        for name in ('optimized-1.0.json','result-1.0.json','summary.json','independent-audit.json'):
            shutil.copyfile(source/name,master/name)
        scan=load(source.parent/'demand-1.0/scan.json')
        first=scan['attempts'][0];single_source=OUT/first['final']['name'];single=root/'single';single.mkdir()
        originals={name:load(single_source/name) for name in ('input.json','result.json','summary.json')}
        originals['summary.json']['name']=str(single)
        scan['attempts'][0]['final']=copy.deepcopy(originals['summary.json'])
        phasefile=root/'summary-guard.json';phasecopy=copy.deepcopy(phase);phasecopy['selected']=str(master)
        phasefile.write_text(json.dumps(phasecopy))
        scanpath=master.parent/'demand-1.0/scan.json';scanpath.parent.mkdir()
        for label in ('controller','preventive_base','native_status','incomplete_scan'):
            values=copy.deepcopy(originals);current_scan=copy.deepcopy(scan)
            if label=='controller':values['input.json']['data']['case']['controls'][0]['slope']*=1.001
            elif label=='preventive_base':values['result.json']['data']['states']['base']['pg'][0]+=.001
            elif label=='native_status':values['result.json']['data']['termination_status']='TIME_LIMIT'
            else:current_scan['attempts'].pop()
            for name,value in values.items():(single/name).write_text(json.dumps(value))
            scanpath.write_text(json.dumps(current_scan))
            try:campaign(phasefile)
            except AssertionError:pass
            else:raise AssertionError(label+' graph corruption accepted')
            checks.append(dict(name=label+'_graph_corruption_rejected',passed=True))
    report=dict(optimizer_calls=0,passed=True,checks=checks)
    (OUT/'solver_demand_qualification/audit-guard-checks.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))
if __name__=='__main__':main()
