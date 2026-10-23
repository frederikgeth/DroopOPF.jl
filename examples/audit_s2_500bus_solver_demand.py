"""Independent original-network replay for individual-demand joint masters."""
import copy
import hashlib
import json
import sys
from pathlib import Path
from audit_s2_arpae500 import replay
from s2_followup_physics import equipment_valid
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/s2_scopf/ieee500_native'
load=lambda p:json.loads(Path(p).read_text())
data=lambda p:load(p)['data']

def audit(folder):
    folder=Path(folder)
    record=load(folder/'summary.json')
    assert record['native_success']==(record['solver_status'] in ('LOCALLY_SOLVED','ALMOST_LOCALLY_SOLVED','OPTIMAL'))
    original=data(OUT/'pilot_study.json')
    calibrated=data(ROOT/'artifacts/s1_arpae500/calibrated-study.json')['case']
    angles=load(ROOT/'artifacts/s1_free_droop/500/angle_limits.json')
    rows=[]
    reduction_checks=[]
    maps=load(folder/'network_reduction_maps.json') if (folder/'network_reduction_maps.json').exists() else []
    for f in record['training_factors']:
        if not (folder/f'optimized-{float(f)}.json').exists():
            rows.append(dict(factor=f,states=[],physical_valid=False,missing_primal_point=True))
            continue
        study=data(folder/f'optimized-{float(f)}.json')
        result=data(folder/f'result-{float(f)}.json')
        assert result['termination_status']==record['solver_status']
        expected=copy.deepcopy(original['case'])
        for l in expected['loads']:
            l['p']*=f;l['q']*=f
        # The droop curves alone may change in the source case.
        expected['controls']=study['case']['controls']
        assert expected==study['case'], 'Source equipment/capability/loads changed'
        assert study['control_policy']==original['control_policy']
        assert study['tap_controls']==original['tap_controls']
        assert study['shunt_controls']==original['shunt_controls']
        assert len(study['case']['controls'])==51
        assert {a['generator_id'] for a in study['case']['attachments']}=={g['id'] for g in study['case']['generators'] if g['available']}
        for control,reference in zip(study['case']['controls'],calibrated['controls']):
            assert control['capability']==reference['capability']
            span=reference['capability']['q_max']-reference['capability']['q_min']
            assert .02/span-1e-8<=control['slope']<=.08/span+1e-8
            assert abs(control['schedule']['v_ref']-reference['schedule']['v_ref'])<=.02+1e-8
            assert control['schedule']['v_db_low']==control['schedule']['v_ref']==control['schedule']['v_db_high']
            assert control['q_at_deadband']==0
        ck=replay(study,result,angles)
        rows.append(dict(factor=f,states=ck,physical_valid=all(r['valid'] for r in ck)))
        if maps:
            import numpy as np
            from analyse_s2_500bus_network_reduction import admittance,partition
            for mapping in [m for m in maps if m['factor']==f]:
                sid=mapping['id'];m=mapping['reduction'];case=copy.deepcopy(study['case'])
                if sid!='base':
                    event=next(e for e in study['contingencies'] if e['id']==sid)
                    for b in case['network']['branches']:
                        if b['id'] in event['branch_ids']:b['available']=False
                    for g in case['generators']:
                        if g['id'] in event['generator_ids']:g['available']=False
                kept,eliminated=partition(original,m['elimination_mode'])
                ids=[b['id'] for b in case['network']['buses']]
                assert m['retained_bus_ids']==[ids[i] for i in kept]
                assert m['eliminated_bus_ids']==[ids[i] for i in eliminated]
                branches=[b for b in case['network']['branches'] if b['available']]
                assert m['original_online_branch_ids']==[b['id'] for b in branches]
                assert m['original_branch_ratings']=={str(b['id']):b['thermal_limit'] for b in branches}
                y=admittance(case,result['tap_settings'][sid],result['shunt_settings'][sid])
                h=-np.linalg.solve(y[np.ix_(eliminated,eliminated)],y[np.ix_(eliminated,kept)])
                stored=np.zeros_like(h)
                for t in m['reconstruction']:stored[t['row']-1,t['column']-1]=complex(t['real'],t['imag'])
                v=np.array(result['states'][sid]['vm'])*np.exp(1j*np.array(result['states'][sid]['va']))
                err=float(np.max(abs(h-stored)));reconstruction=float(np.max(abs(v[eliminated]-h@v[kept])))
                current=float(np.max(abs((y@v)[eliminated])))
                reduction_checks.append(dict(factor=f,id=sid,map_error_max=err,reconstruction_error_max_pu=reconstruction,
                    eliminated_current_residual_max_pu=current,original_ratings_verified=True,
                    valid=err<=1e-10 and reconstruction<=1e-8 and current<=1e-6))
    reduction_valid=all(r['valid'] for r in reduction_checks)
    accepted=record['native_success'] and all(r['physical_valid'] for r in rows) and record['accepted'] and reduction_valid
    report=dict(accepted=accepted,native_success=record['native_success'],original_network_physical_valid=all(r['physical_valid'] for r in rows),demands=rows,
        reduction_valid=reduction_valid,reduction_checks=reduction_checks,auditor_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.iterdir() if p.is_file() and (p.name.startswith(('result-','optimized-','executed_')) or p.name=='free-controls.json')})
    (folder/'independent-audit.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:report[k] for k in ('accepted','native_success','original_network_physical_valid')}))

def campaign(summary):
    summary=Path(summary).resolve();phase=load(summary)
    if not phase['accepted']:
        return dict(accepted=False,reason='Joint master or exhaustive native gate incomplete')
    dest=summary.with_name(summary.name.replace('summary-','audit-'))
    if dest.exists():
        prior=load(dest)
        if prior.get('input_hashes') and all((ROOT/p).is_file() and hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==digest for p,digest in prior['input_hashes'].items()):
            return prior
    master=OUT/phase['selected'];f=phase['factor']
    inputs=[summary,Path(__file__),ROOT/'examples/audit_s2_arpae500.py',ROOT/'examples/s2_followup_physics.py',
            master/f'optimized-{float(f)}.json',master/f'result-{float(f)}.json',master/'summary.json',master/'independent-audit.json']
    if (master/'network_reduction_maps.json').exists():inputs.append(master/'network_reduction_maps.json')
    full=data(master/f'optimized-{float(f)}.json');base=data(master/f'result-{float(f)}.json')
    assert load(master/'independent-audit.json')['accepted']
    scanpath=master.parent/f'demand-{float(f)}'/'scan.json'
    scan=load(scanpath)
    inputs.append(scanpath)
    assert scan['exhaustive'] and len(scan['attempts'])==389 and not scan['failed']
    original=data(OUT/'pilot_study.json')
    inputs.append(OUT/'pilot_study.json')
    from audit_s2_arpae500 import topology
    islands={r['branch'] for r in topology(original['case'])['islands']}
    expected={f"branch_{b['id']}" for b in original['case']['network']['branches'] if b['available'] and b['id'] not in islands}
    expected|={f"generator_{g['id']}" for g in original['case']['generators'] if g['available']}
    assert {r['event'] for r in scan['attempts']}==expected
    angles=load(ROOT/'artifacts/s1_free_droop/500/angle_limits.json')
    inputs.append(ROOT/'artifacts/s1_free_droop/500/angle_limits.json')
    checked=[]
    for row in scan['attempts']:
        directory=OUT/row['final']['name']
        single,result=data(directory/'input.json'),data(directory/'result.json')
        assert row['final']['accepted'] and row['final']['native_success']
        assert load(directory/'summary.json')==row['final']
        assert result['termination_status']==row['final']['native_status']
        assert result['termination_status'] in ('LOCALLY_SOLVED','ALMOST_LOCALLY_SOLVED','OPTIMAL')
        inputs.extend([directory/'input.json',directory/'result.json',directory/'summary.json'])
        assert single['case']==full['case']
        assert single['control_policy']==full['control_policy']
        for key in ('states','tap_settings','shunt_settings'):
            assert result[key]['base']==base[key]['base']
        checks=replay(single,result,angles)
        assert all(r['valid'] for r in checks)
        checked.append(dict(event=row['event'],directory=str(directory.relative_to(OUT)),valid=True))
    report=dict(accepted=True,solver=phase['solver'],factor=f,common_controller_and_preventive_base_verified=True,
                connected_outages=389,unique_states=390,checks=checked,full_n1_accepted=False,
                selected=phase['selected'],input_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})
    dest.write_text(json.dumps(report,indent=2)+'\n')
    return report
if __name__=='__main__':
    if sys.argv[1]=='--campaign':
        r=campaign(sys.argv[2]);print(json.dumps({k:v for k,v in r.items() if k!='checks'}))
    else:
        audit(sys.argv[1])
