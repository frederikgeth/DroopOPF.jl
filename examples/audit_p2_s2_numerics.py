"""Independent exact S2 AC, droop, equipment, response and relief acceptance."""
import copy,json,sys,hashlib,math
from pathlib import Path
from s2_followup_physics import check_case,equipment_valid
load=lambda p:json.loads(Path(p).read_text())
def audit(folder):
    folder=Path(folder);contract=load(folder/'contract.json');study=load(folder/'controller-solve.json')['data'];point=load(folder/'point-solve.json')
    assert load(folder/'controller-solve.json')['active_response']=='s2_proportional_v1'
    source=load(contract['source_study'])['data']
    c=copy.deepcopy(study['case']);c['controls']=source['case']['controls']
    assert c==source['case'],'Network, load or generator data changed'
    for key in ('mode','participation','redispatch_limits','reactive_assignments','control_policy'):
        assert study[key]==source[key],key
    for key in ('tap_controls','shunt_controls'):
        strip=lambda cs:[{k:v for k,v in c.items() if k!='initial'} for c in cs]
        assert strip(study[key])==strip(source[key]),key
    assert contract['active_response']=='s2_proportional_v1'
    assert contract['response_relaxation_cap']==0 and not contract['restore']
    if contract['fixed_controller']:assert study['case']['controls']==contract['initial_controller']
    assert len(study['case']['controls'])==len(contract['reference_controls'])
    droop_valid=True
    for d,ref in zip(study['case']['controls'],contract['reference_controls']):
        span=ref['capability']['q_max']-ref['capability']['q_min']
        droop_valid &= .02/span-1e-8<=d['slope']<=.08/span+1e-8
        droop_valid &= abs(d['schedule']['v_ref']-ref['schedule']['v_ref'])<=.02+1e-8
        droop_valid &= d['capability']==ref['capability'] and d['q_at_deadband']==0
        droop_valid &= all(abs(d['schedule'][k]-d['schedule']['v_ref'])<=1e-10 for k in ('v_db_low','v_db_high'))
    base={r['factor']:r for r in point['states'] if r['id']=='base'}
    if contract['fixed_base_reference']:
        for ref in contract['fixed_base_reference']:
            assert all(base[ref['factor']][k]==ref[k] for k in ('state','taps','banks')),'Preventive base changed'
    events={e['id']:e for e in study['contingencies']};rows=[]
    for row in point['states']:
        assert all(math.isfinite(v) for values in row['state'].values() for v in values)
        assert all(math.isfinite(v) for k in ('taps','banks','dr','shed') for v in row[k].values())
        c=copy.deepcopy(study['case']);f=row['factor'];sid=row['id'];post=sid!='base'
        for l in c['loads']:l['p']*=f;l['q']*=f
        if post:
            # Contract IDs originate from the connected catalogue.
            family,identifier=sid.rsplit('_',1);identifier=int(identifier)
            assert family in ('branch','generator')
            records=c['network']['branches'] if family=='branch' else c['generators']
            next(v for v in records if v['id']==identifier)['available']=False
        if post and contract['emergency']:
            for b in c['network']['buses']:b['v_min']-=.05;b['v_max']+=.05
            for b in c['network']['branches']:b['thermal_limit']*=contract['thermal_multiplier']
        relief=True;drtotal=shedtotal=0.
        for l in c['loads']:
            dr=row['dr'][str(l['id'])];shed=row['shed'][str(l['id'])];eligible=post and contract['relief'] and l['p']>0
            relief &= dr>=-1e-8 and shed>=-1e-8 and dr<=(.01*l['p'] if eligible else 0)+1e-8
            relief &= dr+shed<=(.1*l['p'] if eligible else 0)+1e-8
            if l['p']>0:
                fraction=(dr+shed)/l['p'];l['p']*=1-fraction;l['q']*=1-fraction
            drtotal+=dr;shedtotal+=shed
        relief &= shedtotal*c['base_power']<=10+1e-6
        if contract['zero_dr']:relief &= abs(drtotal)<=1e-8
        if contract['zero_shedding']:relief &= abs(shedtotal)<=1e-8
        ck=check_case(c,row['state'],row['taps'],row['banks'],contract['angles'])
        eq=equipment_valid(study,c,row['taps'],row['banks']);coupling=0.
        if post:
            total=sum(study['participation'].get(str(g['id']),0) for g in c['generators'] if g['available'])
            coupling=max(abs(row['state']['pg'][i]-base[f]['state']['pg'][i]-study['participation'].get(str(g['id']),0)/total*row['delta']) for i,g in enumerate(c['generators']) if g['available'])
        movement=all(abs(row['state']['pg'][i]-base[f]['state']['pg'][i])<=study['redispatch_limits'][str(g['id'])]+1e-6 for i,g in enumerate(c['generators']) if post and g['available'] and str(g['id']) in study['redispatch_limits'])
        valid=movement and ck['valid'] and eq and relief and droop_valid and coupling<=1e-6 and row['artificial_max_pu']<=1e-7
        rows.append(dict(factor=f,id=sid,valid=bool(valid),physical=ck['valid'],equipment=bool(eq),relief=bool(relief),droop_policy=bool(droop_valid),coupling=coupling,
                         balance=ck['power_balance_max_pu'],loss_mw=(sum(row['state']['pg'])-sum(l['p'] for l in c['loads']))*c['base_power'],dr_mw=drtotal*c['base_power']))
    expected={(f,sid) for f in contract['factors'] for sid in ['base']+contract['outages']}
    assert len(rows)==len(expected),'Duplicate or missing states'
    assert {(r['factor'],r['id']) for r in rows}==expected
    result=dict(accepted=bool(point['record']['native_success'] and all(r['valid'] for r in rows)),physical_valid=all(r['valid'] for r in rows),states=rows,
                auditor_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    (folder/'audit-solve.json').write_text(json.dumps(result,indent=2)+'\n')
    return result
if __name__=='__main__':
    r=audit(sys.argv[1]);print(json.dumps({'accepted':r['accepted'],'states':len(r['states'])}))
