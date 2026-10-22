"""Replay demand/backend-matched S1 starts on the current unreduced S2 case."""
import copy
import hashlib
import json
from pathlib import Path
from s2_followup_physics import check_case,equipment_valid
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'artifacts/s2_scopf/ieee500_native'
load=lambda p:json.loads(Path(p).read_text())
def main():
    study=load(BASE/'pilot_study.json')['data'];angles=load(ROOT/'artifacts/s1_free_droop/500/angle_limits.json')
    reference=load(ROOT/'artifacts/s1_arpae500/calibrated-study.json')['data']['case']
    attempts=[load(p) for p in (ROOT/'artifacts/s1_free_droop/500/attempts').glob('*.json')]
    rows=[]
    for f in (.9,.95,1.,1.05):
        for solver in ('ipopt','madnlp','ccopt'):
            good=[r for r in attempts if r['accepted'] and r['solver']==solver and (r['tags'].get('stage')=='design' or r['tags'].get('target_stage')=='design') and r['tags']['family']=='droop_tap_shunt' and r['tags']['factor']==f]
            assert good,(f,solver)
            r=min(good,key=lambda r:(r['loss_mw'],r['name']));p=ROOT/r['result_path'];j=load(p)
            case=copy.deepcopy(study['case'])
            for l in case['loads']:l['p']*=f;l['q']*=f
            for cid,s in j['droops'].items():
                d=case['controls'][int(cid)-1];ref=reference['controls'][int(cid)-1]
                span=ref['capability']['q_max']-ref['capability']['q_min']
                assert .02/span-1e-8<=s['slope']<=.08/span+1e-8
                assert abs(s['v_ref']-ref['schedule']['v_ref'])<=.02+1e-8
                d['slope']=s['slope'];d['schedule'].update(v_ref=s['v_ref'],v_db_low=s['v_ref']-s['deadband_low'],v_db_high=s['v_ref']+s['deadband_high'])
            selected={str(c['branch_id']) for c in study['tap_controls']}
            assert all(j['taps'].get(str(b['id']),b['tap_ratio'])==b['tap_ratio'] for b in case['network']['branches'] if str(b['id']) not in selected)
            taps={k:v for k,v in j['taps'].items() if k in selected}
            ck=check_case(case,j['opf']['state'],taps,j['susceptances'],angles)
            assert ck['valid'] and equipment_valid(study,case,taps,j['susceptances']),(f,solver,ck['valid'])
            rows.append(dict(factor=f,solver=solver,result_path=r['result_path'],attempt=r['name'],
                result_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),native_status=j['opf']['termination_status'],
                physical_valid=True,equipment_valid=True,full_original_bus_count=500,
                power_balance_max_pu=ck['power_balance_max_pu'],scope='Base only; not an SCOPF acceptance'))
    dest=BASE/'solver_demand_qualification/s1-start-checks.json';dest.write_text(json.dumps(dict(optimizer_calls=0,passed=True,starts=rows),indent=2)+'\n')
    print(json.dumps(dict(optimizer_calls=0,passed=True,checked_starts=len(rows))))
if __name__=='__main__':main()
