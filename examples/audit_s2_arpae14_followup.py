"""Independent audit of frozen-controller demand sweep and G5-trip projections."""
from pathlib import Path
import copy,json,hashlib
from s2_followup_physics import check_case,equipment_valid
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'artifacts/s2_scopf/ieee14_native';OUT=BASE/'followup'
load=lambda p:json.loads(p.read_text())
summary=load(OUT/'summary.json');protocol=load(BASE/'protocol.json');angles=protocol['angles']
selected=load(BASE/'full-designed-ipopt/optimized_input.json')['data']
provenance=load(OUT/'provenance.json')
for path,expected in provenance['run_source_hashes'].items():assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==expected,path
connected=[];islands=[];seen=set()

def audit_connected(row):
    directory=BASE/row['name'];study=load(directory/'input.json')['data'];result=load(directory/'result.json')['data']
    assert study['case']['controls']==selected['case']['controls']
    assert study['control_policy']==selected['control_policy']==result['control_policy']
    assert study['control_policy']['taps']==study['control_policy']['shunts']=='corrective'
    assert study['control_policy']['tap_movement_limits'] is None and study['control_policy']['shunt_movement_limits'] is None
    factor=float(row['name'].split('demand-')[-1])
    for old,new in zip(selected['case']['loads'],study['case']['loads']):
        assert old['id']==new['id'] and abs(new['p']-factor*old['p'])<1e-12 and abs(new['q']-factor*old['q'])<1e-12
    cases={'base':dict(generator_ids=[],branch_ids=[])}|{x['id']:x for x in study['contingencies']}
    assert set(result['states'])==set(cases) and len(cases)==25
    checks=[];valid=True
    for sid,event in cases.items():
        state=result['states'][sid]
        if state is None:valid=False;continue
        c=copy.deepcopy(study['case'])
        for b in c['network']['branches']:
            if b['id'] in event['branch_ids']:b['available']=False
        for g in c['generators']:
            if g['id'] in event['generator_ids']:g['available']=False
        check=check_case(c,state,result['tap_settings'][sid],result['shunt_settings'][sid],angles)
        policy=equipment_valid(study,c,result['tap_settings'][sid],result['shunt_settings'][sid]);coupling=0.
        if sid!='base' and result['states']['base'] is not None:
            total=sum(study['participation'][str(g['id'])] for g in c['generators'] if g['available'])
            delta=result['balancing_power'][sid]
            coupling=max(abs(state['pg'][i]-result['states']['base']['pg'][i]-study['participation'][str(g['id'])]/total*delta) for i,g in enumerate(c['generators']) if g['available'])
        check.update(id=sid,equipment_valid=policy,response_coupling_max_pu=coupling)
        check['valid'] &= policy and coupling<=1e-6;valid &= check['valid'];checks.append(check)
    native=result['termination_status'] in ['LOCALLY_SOLVED','ALMOST_LOCALLY_SOLVED','OPTIMAL','ALMOST_OPTIMAL']
    objective_ok=False
    if result['states']['base'] is not None:
        loss=sum(result['states']['base']['pg'])-sum(l['p'] for l in study['case']['loads'])
        objective_ok=abs(loss-result['objective'])<1e-8
    assert bool(valid)==row['physical_valid'],(row['name'],valid,row['physical_valid'])
    assert bool(valid and native and objective_ok)==row['accepted'],row['name']
    connected.append(dict(name=row['name'],accepted=row['accepted'],checks=checks))
    return study,result

def audit_island(path,study,result):
    d=load(path);c=d['case'];state=d['state'];source=study['case'];witness=result['states']['generator_5']
    assert d['selection']['discarded_bus_ids']==[8] and d['selection']['retained_bus_ids']==[b['id'] for b in source['network']['buses'] if b['id']!=8]
    assert not any(x['bus_id']==8 for x in source['loads']+source['network']['shunts']+source['network']['banks'])
    boundary=[b for b in source['network']['branches'] if b['available'] and 8 in [b['from_bus'],b['to_bus']]]
    assert len(boundary)==1 and boundary[0]['id']==11 and boundary[0]['charging']==0 and boundary[0]['tap_ratio']==1 and boundary[0]['phase_shift']==0
    assert [g['id'] for g in c['generators']]==[1,2,3,4]
    for field in ['buses','branches','shunts','banks']:
        expected=[x for x in source['network'][field] if (x['id']!=8 if field=='buses' else x['from_bus']!=8 and x['to_bus']!=8 if field=='branches' else x['bus_id']!=8)]
        assert c['network'][field]==expected,field
    assert c['controls']==source['controls'] and c['loads']==source['loads']
    assert c['attachments']==[a for a in source['attachments'] if a['generator_id'] in [1,2,3,4]]
    for g in c['generators']:
        old=next(x for x in source['generators'] if x['id']==g['id'])
        assert {k:v for k,v in g.items() if k not in ['initial_p','initial_q']}=={k:v for k,v in old.items() if k not in ['initial_p','initial_q']}
    bi={b['id']:i for i,b in enumerate(source['network']['buses'])};gi={g['id']:i for i,g in enumerate(source['generators'])}
    for field in ['vm','va']:assert state[field]==[witness[field][bi[b['id']]] for b in c['network']['buses']]
    for field in ['pg','qg']:assert state[field]==[witness[field][gi[g['id']]] for g in c['generators']]
    assert d['taps']==result['tap_settings']['generator_5'] and d['susceptances']==result['shunt_settings']['generator_5']
    full=copy.deepcopy(source)
    for g in full['generators']:
        if g['id']==5:g['available']=False
    source_check=check_case(full,witness,d['taps'],d['susceptances'],angles)
    zero_flow=source_check['branch_max_terminal_s_pu']['11'];assert zero_flow<=1e-8
    check=check_case(c,state,d['taps'],d['susceptances'],angles);policy=equipment_valid(study,c,d['taps'],d['susceptances'])
    total=sum(study['participation'][str(g['id'])] for g in c['generators']);delta=result['balancing_power']['generator_5']
    coupling=max(abs(state['pg'][i]-result['states']['base']['pg'][gi[g['id']]]-study['participation'][str(g['id'])]/total*delta) for i,g in enumerate(c['generators']))
    check['valid'] &= policy and coupling<=1e-6
    assert bool(check['valid'])==d['valid'],path
    check.update(file=path.name,equipment_valid=policy,response_coupling_max_pu=coupling,source_boundary_flow_pu=zero_flow,discarded_load_p=0.,discarded_load_q=0.)
    islands.append(check)

for row in summary['nominal_island_projections']:
    directory=BASE/row['name']
    audit_island(OUT/('island-'+row['name']+'.json'),load(directory/'optimized_input.json')['data'],load(directory/'result.json')['data'])
for lane in summary['attempts']:
    for row in [lane['primary'],lane['final']]:
        if row['name'] in seen:continue
        seen.add(row['name']);audit_connected(row)
    row=lane['final'];directory=BASE/row['name'];path=OUT/f"island-{lane['solver']}-demand-{lane['factor']}.json"
    if path.exists():audit_island(path,load(directory/'input.json')['data'],load(directory/'result.json')['data'])
report=dict(connected_attempts=len(connected),connected_states=sum(len(x['checks']) for x in connected),
    island_projections=len(islands),accepted_island_projections=sum(x['valid'] for x in islands),
    discrepancies=0,selected_curves_unchanged=True,source_hashes_verified=True,connected=connected,islands=islands)
(OUT/'independent_audit.json').write_text(json.dumps(report,indent=2)+'\n')
print(report['connected_states'],'connected-state checks;',len(islands),'conditional island projections; zero discrepancies')
