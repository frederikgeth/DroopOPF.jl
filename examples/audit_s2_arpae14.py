"""Independent standard-library AC, exact-droop and SCOPF-policy audit; no solves."""
from pathlib import Path
import cmath
import copy
import hashlib
import json
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/s2_scopf/ieee14_native'
load = lambda p: json.loads(p.read_text())
protocol = load(OUT/'protocol.json')
angles = protocol['angles']
for path, expected in protocol['source_hashes'].items():
    assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest() == expected, path
checks = []
for lane in load(OUT/'summary.json')['attempts']:
    directory = OUT/lane['name']
    if not (directory/'optimized_input.json').exists():
        assert not lane['accepted']
        continue
    study = load(directory/'optimized_input.json')['data']
    source = load(directory/'input.json')['data']
    result = load(directory/'result.json')['data']
    assert study['mode']==result['mode']=='preventive'
    assert result['control_policy']==study['control_policy']==source['control_policy']
    assert study['control_policy']['taps']==study['control_policy']['shunts']=='corrective'
    assert study['control_policy']['tap_movement_limits'] is None and study['control_policy']['shunt_movement_limits'] is None
    if lane['name']=='exact-designed-ccopt':
        assert source==load(OUT/'full-designed-ipopt/optimized_input.json')['data']
    if lane['name']=='exact-frozen-ccopt':
        assert source==load(OUT/'full-frozen-ipopt/input.json')['data']
    c = study['case']; net = c['network']; base = c['base_power']
    assert study['participation']=={str(g['id']):g['p_max'] for g in c['generators'] if g['available']}
    ids = {b['id']: i for i,b in enumerate(net['buses'])}
    gids = {g['id']: i for i,g in enumerate(c['generators'])}
    # Curve design must preserve all non-controller electrical data.
    assert {k:v for k,v in c.items() if k!='controls'} == {k:v for k,v in source['case'].items() if k!='controls'}
    selected = {d['control_id']: d for d in lane['controls']}
    design_valid = True
    for i,(old,new) in enumerate(zip(source['case']['controls'],c['controls']),1):
        if i not in selected:
            assert old == new
            continue
        values = dict(slope=new['slope'],v_ref=new['schedule']['v_ref'],
                      deadband_low=new['schedule']['v_ref']-new['schedule']['v_db_low'],
                      deadband_high=new['schedule']['v_db_high']-new['schedule']['v_ref'])
        assert old['capability']==new['capability'] and old['q_at_deadband']==new['q_at_deadband']
        for key,value in values.items():
            default = old[key] if key=='slope' else old['schedule']['v_ref'] if key=='v_ref' else 0.
            lo,hi = selected[i]['bounds'][key] or [default,default]
            design_valid &= lo-1e-8<=value<=hi+1e-8
    states = result['states']; base_state = states['base']; scenario_rows = []
    contingencies = {'base':dict(branch_ids=[],generator_ids=[])} | {x['id']:x for x in study['contingencies']}
    assert set(states)==set(contingencies)
    all_valid = design_valid
    for name,outage in contingencies.items():
        state = states[name]
        if state is None:
            all_valid=False
            continue
        branches = [b for b in net['branches'] if b['available'] and b['id'] not in outage['branch_ids']]
        generators = [dict(g, available=g['available'] and g['id'] not in outage['generator_ids']) for g in c['generators']]
        taps = result['tap_settings'][name]; banks = result['shunt_settings'][name]
        expected_taps = {str(t['branch_id']) for t in study['tap_controls'] if any(b['id']==t['branch_id'] for b in branches)}
        assert set(taps)==expected_taps
        assert set(banks)=={str(b['bank_id']) for b in study['shunt_controls']}
        valid=True;v=[cmath.rect(m,a) for m,a in zip(state['vm'],state['va'])];balance=[0j]*len(v)
        thermal=float('inf');angle_margin=float('inf');branch_rows=[]
        for b in branches:
            i,j=ids[b['from_bus']],ids[b['to_bus']]
            tap=cmath.rect(taps.get(str(b['id']),b['tap_ratio']),b['phase_shift'])
            y=1/complex(b['resistance'],b['reactance']);yc=complex(0,b['charging']/2)
            sf=v[i]*(((y+yc)/abs(tap)**2*v[i]-y/tap.conjugate()*v[j]).conjugate())
            st=v[j]*(((y+yc)*v[j]-y/tap*v[i]).conjugate())
            balance[i]-=sf;balance[j]-=st
            margin=b['thermal_limit']-max(abs(sf),abs(st));thermal=min(thermal,margin)
            lo,hi=angles[str(b['id'])];a=state['va'][i]-state['va'][j];angle_margin=min(angle_margin,a-lo,hi-a)
            branch_rows.append(dict(id=b['id'],loading_percent=100*max(abs(sf),abs(st))/b['thermal_limit'],margin_mva=margin*base))
        for b in net['shunts']:
            if b['available']:
                i=ids[b['bus_id']];balance[i]-=complex(b['conductance'],-b['susceptance'])*state['vm'][i]**2
        for b in net['banks']:
            if not b['available']:continue
            bs=sum(x*y for x,y in zip(b['step_susceptances'],b['state']))
            gs=sum(x*y for x,y in zip(b['step_conductances'],b['state']))
            if str(b['id']) in banks:
                bs=banks[str(b['id'])];gs=b['step_conductances'][0]/b['step_susceptances'][0]*bs
            balance[ids[b['bus_id']]]-=complex(gs,-bs)*state['vm'][ids[b['bus_id']]]**2
        for l in c['loads']:balance[ids[l['bus_id']]]-=complex(l['p'],l['q'])
        min_p=min_q=float('inf')
        for i,g in enumerate(generators):
            balance[ids[g['bus_id']]]+=complex(state['pg'][i],state['qg'][i])
            if not g['available']:
                valid &= max(abs(state['pg'][i]),abs(state['qg'][i]))<=1e-8
                continue
            pm=min(state['pg'][i]-g['p_min'],g['p_max']-state['pg'][i]);qm=min(state['qg'][i]-g['q_min'],g['q_max']-state['qg'][i])
            min_p=min(min_p,pm);min_q=min(min_q,qm);valid &= min(pm,qm)>=-1e-6
        droop=0.
        for a in c['attachments']:
            gi=gids[a['generator_id']]
            if not generators[gi]['available']:continue
            d=c['controls'][a['control_id']-1];sch=d['schedule'];cap=d['capability'];vg=state['vm'][ids[a['location']['bus_id']]]
            raw=d['q_at_deadband']+(max(sch['v_db_low']-vg,0)-max(vg-sch['v_db_high'],0))/d['slope']
            exact=max(cap['q_min'],min(cap['q_max'],raw));droop=max(droop,abs(state['qg'][gi]-exact))
            valid &= cap['p_min']-1e-6<=state['pg'][gi]<=cap['p_max']+1e-6
        voltage_margin=min(min(state['vm'][i]-b['v_min'],b['v_max']-state['vm'][i]) for i,b in enumerate(net['buses']))
        valid &= voltage_margin>=-1e-6
        for i,b in enumerate(net['buses']):
            if b['reference']:valid &= abs(state['va'][i])<=1e-6
        for key,settings,id_key in [('tap_controls',taps,'branch_id'),('shunt_controls',banks,'bank_id')]:
            for control in study[key]:
                if str(control[id_key]) not in settings:
                    assert key=='tap_controls' and control[id_key] in outage['branch_ids'];continue
                setting=settings[str(control[id_key])]
                if key=='shunt_controls' and control['lower'] is None:
                    bank=next(b for b in net['banks'] if b['id']==control[id_key])
                    values=[sum(x*y for x,y in zip(bank['step_susceptances'],st)) for st in bank['legal_states']]
                    lo,hi=min(values),max(values)
                else:lo,hi=control['lower'],control['upper']
                valid &= lo-1e-6<=setting<=hi+1e-6
        coupling=0.
        if name!='base':
            weights={g['id']:study['participation'].get(str(g['id']),0.) for g in generators if g['available']};total=sum(weights.values())
            delta=result['balancing_power'][name]
            coupling=max(abs(state['pg'][i]-base_state['pg'][i]-weights[g['id']]/total*delta) for i,g in enumerate(generators) if g['available'])
        residual=max(max(abs(z.real),abs(z.imag)) for z in balance)
        valid &= residual<=1e-6 and droop<=1e-5 and thermal>=-1e-6 and angle_margin>=-1e-6 and coupling<=1e-6
        all_valid &= valid
        scenario_rows.append(dict(id=name,valid=bool(valid),power_balance_max_pu=residual,exact_droop_max_pu=droop,
            thermal_min_margin_mva=thermal*base,voltage_min_margin_pu=voltage_margin,angle_min_margin_rad=angle_margin,
            generator_p_min_margin_mw=min_p*base,generator_q_min_margin_mvar=min_q*base,
            response_coupling_max_pu=coupling,branches=branch_rows))
    expected_loss=(sum(base_state['pg'])-sum(l['p'] for l in c['loads']))*base
    assert abs(expected_loss-lane['base_loss_mw'])<1e-9
    assert abs(result['objective']-expected_loss/base)<1e-8
    native=result['termination_status'] in ['LOCALLY_SOLVED','ALMOST_LOCALLY_SOLVED','OPTIMAL','ALMOST_OPTIMAL']
    assert bool(all_valid)==lane['physical_valid'],(lane['name'],all_valid,lane['physical_valid'])
    assert bool(all_valid and native)==lane['accepted'],lane['name']
    checks.append(dict(name=lane['name'],accepted=lane['accepted'],scenarios=scenario_rows))
result=dict(lanes_replayed=len(checks),states_replayed=sum(len(r['scenarios']) for r in checks),
            discrepancies=0,checks=checks,source_hashes_verified=True)
(OUT/'independent_audit.json').write_text(json.dumps(result,indent=2)+'\n')
print(result['lanes_replayed'],'lanes;',result['states_replayed'],'states; zero discrepancies')
