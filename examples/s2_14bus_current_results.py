"""Canonical saved-result selection for the final accepted 14-bus S2 designs.

Importing this module performs no writes or optimisation.
"""
from pathlib import Path
import copy,hashlib,json
from s2_followup_physics import check_case,equipment_valid
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'artifacts/s2_scopf/ieee14_native';MULTI=BASE/'multidemand'
COMPARE=MULTI/'solver_design_comparison';RECOVER=COMPARE/'ccopt_recovery'
OUT=BASE/'current_results'
TRAIN=[.9,.95,1.,1.05,1.1];HOLD=[.925,.975,1.025,1.075]
load=lambda p:json.loads(Path(p).read_text())
data=lambda p:load(p)['data']

def selected_results():
    recovered=load(RECOVER/'summary.json')['selected']
    assert recovered and load(RECOVER/recovered/'summary.json')['accepted']
    controllers={'ipopt':MULTI/'design-ipopt','madnlp':COMPARE/'design-madnlp','ccopt':RECOVER/recovered}
    evals={'ipopt':load(MULTI/'evaluation_summary.json')['attempts'],
           'madnlp':load(COMPARE/'summary.json')['heldout'],
           'ccopt':load(RECOVER/'summary.json')['heldout']}
    entries=[]
    for solver,directory in controllers.items():
        assert load(directory/'summary.json')['accepted']
        for f in sorted(TRAIN+HOLD):
            if f in TRAIN:
                study=directory/f'optimized-{f}.json';result=directory/f'result-{f}.json';island=directory/f'island-{f}.json'
            else:
                lane=next(r for r in evals[solver] if r['solver']==solver and r['factor']==f)
                assert lane.get('accepted_with_trip_assumption',lane.get('accepted',False))
                folder=BASE/lane['final']['name'];study=folder/'optimized_input.json';result=folder/'result.json'
                island={'ipopt':MULTI/f'island-frozen-ipopt-demand-{f}.json',
                        'madnlp':COMPARE/f'island-heldout-madnlp-{f}.json',
                        'ccopt':RECOVER/f'island-heldout-ccopt-{f}.json'}[solver]
            entries.append(dict(solver=solver,factor=f,role='training master' if f in TRAIN else 'held out',
                study_path=study,result_path=result,island_path=island,
                study=data(study),result=data(result),island=load(island)))
    return controllers,entries

def audit_current(controllers,entries):
    original=data(BASE/'full-frozen-ipopt/input.json');angles=load(BASE/'protocol.json')['angles']
    expected_policy=original['control_policy'];checks=[];projections=[];hashes={}
    assert load(BASE/'14bus_review/STATUS.json')['status']=='closed_declared_14bus_scope'
    source=BASE/'full-frozen-ipopt/input.json'
    hashes[str(source.relative_to(ROOT))]=hashlib.sha256(source.read_bytes()).hexdigest()
    for solver,directory in controllers.items():
        for name in ['controller.json','summary.json']:
            source=directory/name;hashes[str(source.relative_to(ROOT))]=hashlib.sha256(source.read_bytes()).hexdigest()
        curves=data(directory/'controller.json')['case']['controls']
        for old,new in zip(original['case']['controls'],curves):
            assert {k:v for k,v in old.items() if k not in ['slope','schedule']}=={k:v for k,v in new.items() if k not in ['slope','schedule']}
            span=old['capability']['q_max']-old['capability']['q_min'];ref=new['schedule']['v_ref']
            assert .02-1e-8<=new['slope']*span<=.08+1e-8
            assert old['schedule']['v_ref']-.02-1e-8<=ref<=old['schedule']['v_ref']+.02+1e-8
            assert new['schedule']['v_db_low']==new['schedule']['v_db_high']==ref
            assert new['q_at_deadband']==0 and new['schedule']['unit']==old['schedule']['unit']
    for entry in entries:
        solver,f,study,result=entry['solver'],entry['factor'],entry['study'],entry['result']
        curves=data(controllers[solver]/'controller.json')['case']['controls']
        expected=copy.deepcopy(original['case']);expected['controls']=curves
        for l in expected['loads']:l['p']*=f;l['q']*=f
        assert study['case']==expected
        for key in ['control_policy','tap_controls','shunt_controls','mode','participation','redispatch_limits','contingencies']:
            assert study[key]==original[key],key
        assert study['control_policy']==result['control_policy']==expected_policy
        assert expected_policy['taps']==expected_policy['shunts']=='corrective'
        assert expected_policy['tap_movement_limits'] is None and expected_policy['shunt_movement_limits'] is None
        assert result['termination_status'] in ['LOCALLY_SOLVED','ALMOST_LOCALLY_SOLVED','OPTIMAL']
        assert result['encoding']==('complementarity' if solver=='ccopt' else 'smooth')
        cases={'base':dict(generator_ids=[],branch_ids=[])}|{c['id']:c for c in study['contingencies']}
        assert len(cases)==25 and set(result['states'])==set(cases)
        for sid,event in cases.items():
            state=result['states'][sid];assert state is not None
            case=copy.deepcopy(study['case'])
            for g in case['generators']:
                if g['id'] in event['generator_ids']:g['available']=False
            for b in case['network']['branches']:
                if b['id'] in event['branch_ids']:b['available']=False
            ck=check_case(case,state,result['tap_settings'][sid],result['shunt_settings'][sid],angles)
            eq=equipment_valid(study,case,result['tap_settings'][sid],result['shunt_settings'][sid]);coupling=0.
            if sid!='base':
                total=sum(study['participation'][str(g['id'])] for g in case['generators'] if g['available'])
                coupling=max(abs(state['pg'][i]-result['states']['base']['pg'][i]-study['participation'][str(g['id'])]/total*result['balancing_power'][sid]) for i,g in enumerate(case['generators']) if g['available'])
            ck.update(solver=solver,factor=f,id=sid,equipment_valid=eq,response_coupling_max_pu=coupling)
            assert ck['valid'] and eq and coupling<=1e-6,(solver,f,sid)
            checks.append(ck)
        loss=sum(result['states']['base']['pg'])-sum(l['p'] for l in study['case']['loads'])
        assert abs(loss-result['objective'])<1e-8
        projected=entry['island'];case=projected['case'];source=study['case'];witness=result['states']['generator_5']
        assert projected['valid'] and projected['selection']['discarded_bus_ids']==[8]
        assert not any(x['bus_id']==8 for x in source['loads']+source['network']['banks']+source['network']['shunts'])
        assert case['controls']==source['controls'] and case['loads']==source['loads']
        assert [g['id'] for g in case['generators']]==[1,2,3,4]
        for field in ['buses','branches','banks','shunts']:
            expected=[x for x in source['network'][field] if (x['id']!=8 if field=='buses' else 8 not in [x['from_bus'],x['to_bus']] if field=='branches' else x['bus_id']!=8)]
            assert case['network'][field]==expected
        assert case['attachments']==[a for a in source['attachments'] if a['generator_id'] in [1,2,3,4]]
        for g in case['generators']:
            old=next(x for x in source['generators'] if x['id']==g['id'])
            assert {k:v for k,v in g.items() if k not in ['initial_p','initial_q']}=={k:v for k,v in old.items() if k not in ['initial_p','initial_q']}
        bi={b['id']:i for i,b in enumerate(source['network']['buses'])};gi={g['id']:i for i,g in enumerate(source['generators'])}
        for key in ['vm','va']:assert projected['state'][key]==[witness[key][bi[b['id']]] for b in case['network']['buses']]
        for key in ['pg','qg']:assert projected['state'][key]==[witness[key][gi[g['id']]] for g in case['generators']]
        assert projected['taps']==result['tap_settings']['generator_5'] and projected['susceptances']==result['shunt_settings']['generator_5']
        boundary=[b for b in source['network']['branches'] if b['available'] and 8 in [b['from_bus'],b['to_bus']]]
        assert len(boundary)==1 and boundary[0]['id']==11 and boundary[0]['charging']==0 and boundary[0]['tap_ratio']==1 and boundary[0]['phase_shift']==0
        full=copy.deepcopy(source)
        for g in full['generators']:
            if g['id']==5:g['available']=False
        zero=check_case(full,witness,projected['taps'],projected['susceptances'],angles)['branch_max_terminal_s_pu']['11'];assert zero<=1e-8
        ck=check_case(case,projected['state'],projected['taps'],projected['susceptances'],angles)
        total=sum(study['participation'][str(g['id'])] for g in case['generators'])
        coupling=max(abs(projected['state']['pg'][i]-result['states']['base']['pg'][gi[g['id']]]-study['participation'][str(g['id'])]/total*result['balancing_power']['generator_5']) for i,g in enumerate(case['generators']))
        assert ck['valid'] and equipment_valid(study,case,projected['taps'],projected['susceptances']) and coupling<=1e-6
        ck.update(solver=solver,factor=f,response_coupling_max_pu=coupling,source_boundary_flow_pu=zero);projections.append(ck)
        for key in ['study_path','result_path','island_path']:
            path=entry[key];hashes[str(path.relative_to(ROOT))]=hashlib.sha256(path.read_bytes()).hexdigest()
    assert len(checks)==675 and len(projections)==27
    return dict(connected_states=675,conditional_island_projections=27,classification_discrepancies=0,
        all_selected_states_valid=True,source_hashes=hashes,checks=checks,projections=projections)
