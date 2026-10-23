"""Independent audit of new free MadNLP/CCOpt multi-demand designs and held-out checks."""
from pathlib import Path
import json,copy,hashlib
from s2_followup_physics import check_case,equipment_valid
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'artifacts/s2_scopf/ieee14_native';MULTI=BASE/'multidemand';OUT=MULTI/'solver_design_comparison'
load=lambda p:json.loads(p.read_text());data=lambda p:load(p)['data']
original=data(BASE/'full-frozen-ipopt/input.json');angles=load(BASE/'protocol.json')['angles']
protocol=load(OUT/'protocol.json')
for path,digest in protocol['run_source_hashes'].items():assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest,path
records=[];islands=[]
native=lambda r:r['termination_status'] in ['LOCALLY_SOLVED','ALMOST_LOCALLY_SOLVED','OPTIMAL']
def structure(study,factor,curves):
    assert study['case']['controls']==curves
    assert study['contingencies']==original['contingencies'] and len(study['contingencies'])==24
    for key in ['tap_controls','shunt_controls','control_policy','mode','participation','redispatch_limits']:
        assert study[key]==original[key],key
    assert study['control_policy']['taps']==study['control_policy']['shunts']=='corrective'
    assert study['control_policy']['tap_movement_limits'] is None and study['control_policy']['shunt_movement_limits'] is None
    expected=copy.deepcopy(original['case'])
    expected['controls']=curves
    for l in expected['loads']:
        l['p']*=factor;l['q']*=factor
    assert study['case']==expected,'only loads and shared curves may change'

def curves_valid(curves):
    assert len(curves)==5
    for new,old in zip(curves,original['case']['controls']):
        for key in new:
            if key not in ['slope','schedule']:assert new[key]==old[key],key
        schedule=new['schedule'];ref=schedule['v_ref'];cap=old['capability']
        assert schedule['unit']==old['schedule']['unit']
        assert schedule['v_db_low']==schedule['v_db_high']==ref
        assert new['q_at_deadband']==0
        if not .02-1e-8<=new['slope']*(cap['q_max']-cap['q_min'])<=.08+1e-8:return False
        if not old['schedule']['v_ref']-.02-1e-8<=ref<=old['schedule']['v_ref']+.02+1e-8:return False
    return True

def connected(study,result,label):
    cases={'base':dict(generator_ids=[],branch_ids=[])}|{x['id']:x for x in study['contingencies']}
    assert set(result['states'])==set(cases)
    assert result['control_policy']==study['control_policy']
    checks=[];valid=True
    for sid,event in cases.items():
        state=result['states'][sid]
        if state is None:
            valid=False;checks.append(dict(id=sid,valid=False,missing=True));continue
        c=copy.deepcopy(study['case'])
        for b in c['network']['branches']:
            if b['id'] in event['branch_ids']:b['available']=False
        for g in c['generators']:
            if g['id'] in event['generator_ids']:g['available']=False
        ck=check_case(c,state,result['tap_settings'][sid],result['shunt_settings'][sid],angles)
        eq=equipment_valid(study,c,result['tap_settings'][sid],result['shunt_settings'][sid]);coupling=0.
        if sid!='base' and result['states']['base'] is not None:
            total=sum(study['participation'][str(g['id'])] for g in c['generators'] if g['available'])
            coupling=max(abs(state['pg'][i]-result['states']['base']['pg'][i]-study['participation'][str(g['id'])]/total*result['balancing_power'][sid]) for i,g in enumerate(c['generators']) if g['available'])
        ck.update(id=sid,equipment_valid=eq,response_coupling_max_pu=coupling)
        ck['valid'] &= eq and coupling<=1e-6;valid &= ck['valid'];checks.append(ck)
    objective_error=float('inf')
    if result['states']['base']:
        objective_error=abs(sum(result['states']['base']['pg'])-sum(l['p'] for l in study['case']['loads'])-result['objective'])
    entry=dict(name=label,physical_valid=valid,objective_replay_error=objective_error,native_success=native(result),checks=checks)
    records.append(entry)
    return valid and native(result) and objective_error<1e-8

def island(path,study,result):
    if not path.exists():return False
    d=load(path);c=d['case'];source=study['case'];witness=result['states']['generator_5']
    assert d['selection']['discarded_bus_ids']==[8] and d['selection']['discarded_load_p']==0
    assert [g['id'] for g in c['generators']]==[1,2,3,4]
    assert c['controls']==source['controls'] and c['loads']==source['loads']
    assert not any(x['bus_id']==8 for x in source['loads']+source['network']['shunts']+source['network']['banks'])
    for field in ['buses','branches','shunts','banks']:
        expected=[x for x in source['network'][field] if (x['id']!=8 if field=='buses' else 8 not in [x['from_bus'],x['to_bus']] if field=='branches' else x['bus_id']!=8)]
        assert c['network'][field]==expected
    assert c['attachments']==[a for a in source['attachments'] if a['generator_id'] in [1,2,3,4]]
    for g in c['generators']:
        old=next(x for x in source['generators'] if x['id']==g['id'])
        assert {k:v for k,v in g.items() if k not in ['initial_p','initial_q']}=={k:v for k,v in old.items() if k not in ['initial_p','initial_q']}
    bi={b['id']:i for i,b in enumerate(source['network']['buses'])};gi={g['id']:i for i,g in enumerate(source['generators'])}
    for field in ['vm','va']:assert d['state'][field]==[witness[field][bi[b['id']]] for b in c['network']['buses']]
    for field in ['pg','qg']:assert d['state'][field]==[witness[field][gi[g['id']]] for g in c['generators']]
    assert d['taps']==result['tap_settings']['generator_5'] and d['susceptances']==result['shunt_settings']['generator_5']
    boundary=[b for b in source['network']['branches'] if b['available'] and 8 in [b['from_bus'],b['to_bus']]]
    assert len(boundary)==1 and boundary[0]['id']==11 and boundary[0]['charging']==0 and boundary[0]['tap_ratio']==1 and boundary[0]['phase_shift']==0
    full=copy.deepcopy(source)
    for g in full['generators']:
        if g['id']==5:g['available']=False
    zero=check_case(full,witness,d['taps'],d['susceptances'],angles)['branch_max_terminal_s_pu']['11'];assert zero<=1e-8
    ck=check_case(c,d['state'],d['taps'],d['susceptances'],angles)
    eq=equipment_valid(study,c,d['taps'],d['susceptances']);total=sum(study['participation'][str(g['id'])] for g in c['generators'])
    coupling=max(abs(d['state']['pg'][i]-result['states']['base']['pg'][gi[g['id']]]-study['participation'][str(g['id'])]/total*result['balancing_power']['generator_5']) for i,g in enumerate(c['generators']))
    ck['valid'] &= eq and coupling<=1e-6
    assert ck['valid']==d['valid'],path
    ck.update(name=str(path.relative_to(OUT)),response_coupling_max_pu=coupling,source_boundary_flow_pu=zero,equipment_valid=eq)
    islands.append(ck)
    return ck['valid']

summary=load(OUT/'summary.json')
for row in summary['attempts']:
    directory=OUT/row['name'];controller=directory/'controller.json'
    if not controller.exists():assert not row['accepted'];continue
    curves=data(controller)['case']['controls'];policy=curves_valid(curves);valid=True
    if row['solver']=='ccopt':
        diag=row['ccopt_diagnostics'];assert diag['backend']=='CCOpt' and diag['algorithm']=='complementarity relaxation'
        assert diag['complementarity_pairs']==1200,diag
    for f in protocol['training_factors']:
        study=data(directory/f'optimized-{f}.json');result=data(directory/f'result-{f}.json')
        assert result['encoding']==('complementarity' if row['solver']=='ccopt' else 'smooth')
        structure(study,f,curves);passed=connected(study,result,f"{row['name']}/demand-{f}")
        projected=island(directory/f'island-{f}.json',study,result);valid &= passed and projected
        if f==1.:assert abs(result['objective']-row['master_objective_pu'])<1e-8
    assert bool(valid and policy)==row['accepted'],row['name']
seen=set()
for lane in summary['heldout']:
    chosen=summary['selected'][lane['solver']];curves=data(OUT/chosen/'controller.json')['case']['controls'];assert curves_valid(curves)
    for row in [lane['primary'],lane['final']]:
        if row['name'] in seen:continue
        seen.add(row['name']);directory=BASE/row['name'];study=data(directory/'optimized_input.json');result=data(directory/'result.json')
        structure(study,lane['factor'],curves);passed=connected(study,result,row['name']);assert bool(passed)==row['accepted'],row['name']
    directory=BASE/lane['final']['name'];study=data(directory/'optimized_input.json');result=data(directory/'result.json')
    projected=island(OUT/f"island-heldout-{lane['solver']}-{lane['factor']}.json",study,result)
    assert bool(lane['final']['accepted'] and projected)==lane['accepted']
report=dict(source_hashes_verified=True,shared_curve_and_equipment_policies_verified=True,free_design_and_encoding_verified=True,
    connected_blocks=len(records),connected_states=sum(len(r['checks']) for r in records),island_projections=len(islands),
    classification_discrepancies=0,connected=records,islands=islands)
(OUT/'independent_audit.json').write_text(json.dumps(report,indent=2)+'\n')
print(report['connected_states'],'connected states and',len(islands),'island projections; zero discrepancies')
