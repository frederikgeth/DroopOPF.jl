"""Independent physical replay of instrumented CCOpt stage snapshots; no solve."""
import copy
import hashlib
import json
from pathlib import Path
from s2_followup_physics import check_case, equipment_valid

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'artifacts/s2_scopf/ieee500_native/targeted_demand_diagnostics'


def audit(folder):
    folder=Path(folder)
    study=json.loads((folder/'input-1.0.json').read_text())['data']
    angles=json.loads((ROOT/'artifacts/s1_free_droop/500/angle_limits.json').read_text())
    rows=[]
    preliminary=folder/'feasibility-stage.json'
    loss_started=not preliminary.exists() or json.loads(preliminary.read_text())['native_success']
    for path in sorted(folder.glob('snapshot-*.json')):
        snapshot=json.loads(path.read_text());controller=copy.deepcopy(study)
        for key,setting in snapshot['settings'].items():
            d=controller['case']['controls'][int(key)-1]
            d['slope']=setting['slope']
            d['schedule'].update(v_ref=setting['v_ref'],v_db_low=setting['v_ref']-setting['deadband_low'],
                                 v_db_high=setting['v_ref']+setting['deadband_high'])
        events={'base':dict(branch_ids=[],generator_ids=[])}
        events.update({e['id']:e for e in controller['contingencies']})
        entries={x['id']:x for x in snapshot['states']};states=[]
        assert set(entries)==set(events)
        for sid,event in events.items():
            case=copy.deepcopy(controller['case']);entry=entries[sid]
            for b in case['network']['branches']:
                if b['id'] in event['branch_ids']:b['available']=False
            for g in case['generators']:
                if g['id'] in event['generator_ids']:g['available']=False
            check=check_case(case,entry['state'],entry['taps'],entry['banks'],angles)
            check['leading_droop_residuals']=sorted(check['droop_by_generator'],key=lambda x:x['residual_pu'],reverse=True)[:5]
            for key in ('bus_balance','branch_max_terminal_s_pu','droop_by_generator'):check.pop(key)
            eq=equipment_valid(controller,case,entry['taps'],entry['banks'])
            response=0.
            if sid!='base':
                total=sum(controller['participation'][str(g['id'])] for g in case['generators'] if g['available'])
                response=max(abs(entry['state']['pg'][i]-entries['base']['state']['pg'][i]
                                 -controller['participation'][str(g['id'])]/total*entry['delta'])
                             for i,g in enumerate(case['generators']) if g['available'])
            states.append(dict(id=sid,**check,equipment_valid=eq,response_coupling_max_pu=response))
        finite_duals=[c for c in snapshot['constraints'] if c['dual'] is not None]
        active_bounds=[v for v in snapshot['variables'] if v['value'] is not None and any(
            v[k] is not None and abs(v['value']-v[k])<1e-6 for k in ('lower','upper'))]
        rows.append(dict(snapshot=path.name,actual_stage='loss' if loss_started and path.stem=='snapshot-loss' else 'feasibility',
                         loss_stage_started=loss_started,status=snapshot['status'],objective=snapshot['objective'],
                         source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),states=states,
                         physical_valid=all(s['valid'] and s['equipment_valid'] and s['response_coupling_max_pu']<=1e-6 for s in states),
                         diagnostics=snapshot['diagnostics'],
                         largest_named_constraint_duals=sorted(finite_duals,key=lambda x:abs(x['dual']),reverse=True)[:20],
                         active_variable_bounds=active_bounds,
                         limitation='Stage replay only; no exhaustive security or original MPCC optimality certificate.'))
    output=dict(optimizer_calls=0,stages=rows,auditor_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    (folder/'stage-physical-audit.json').write_text(json.dumps(output,indent=2)+'\n')
    print(json.dumps(dict(stages=[{k:v for k,v in r.items() if k in ('snapshot','status','objective','physical_valid','diagnostics')} for r in rows])))
    return output


if __name__=='__main__':
    import sys
    audit(sys.argv[1])
