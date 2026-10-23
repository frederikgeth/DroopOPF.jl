"""Necessary active-only outer-relaxation checks for frozen mixed-control bases.

Drops all reactive controls, apparent circles and attached-control P bounds in a
COPY, enlarging feasibility. A rational active-balance exclusion in that outer
problem therefore also excludes this fixed-dispatch/full mixed problem. This is
not a network-wide infeasibility claim and never predicts a safe outage.
"""
import copy,json,sys
from pathlib import Path
from p2_s2_capacity_filter import capacity_certificate

def active_only_projection(source):
    outer=copy.deepcopy(source);case=outer['case']
    assignments=source.get('reactive_assignments')
    caps=({a['generator_id']:a['mode']['capability'] for a in assignments if a['mode']['type']=='VoltVarDroop'}
          if assignments is not None else
          {a['generator_id']:source['case']['controls'][a['control_id']-1]['capability'] for a in source['case']['attachments']})
    # Preserve the actual response support before dropping its P-cap restrictions.
    for g in case['generators']:
        lo,hi=g['p_min'],g['p_max'];S=g.get('s_rated')
        if S is not None:lo,hi=max(lo,-S),min(hi,S)
        cap=caps.get(g['id'])
        if cap:lo,hi=max(lo,cap['p_min']),min(hi,cap['p_max'])
        if hi<=lo:outer['participation'][str(g['id'])]=0.
        g['s_rated']=None
    for control in source['shunt_controls']:
        bank=next(b for b in source['case']['network']['banks'] if b['id']==control['bank_id'])
        if any(bank['step_conductances']):
            if len(bank['step_susceptances'])!=1 or bank['step_susceptances'][0]==0:
                raise ValueError('unsupported selected bank for passive outer bound')
            ratio=bank['step_conductances'][0]/bank['step_susceptances'][0]
            legal=[sum(b*n for b,n in zip(bank['step_susceptances'],state)) for state in bank['legal_states']]
            lo=control['lower'] if control['lower'] is not None else min(legal)
            hi=control['upper'] if control['upper'] is not None else max(legal)
            if min(ratio*lo,ratio*hi)<0:raise ValueError('selected bank could inject active power')
    outer['reactive_assignments']=None;case['controls']=[];case['attachments']=[]
    return outer

def screen(root,lane):
    root=Path(root);folder=root/lane;r=json.loads((folder/'result.json').read_text());r=r.get('data',r)
    if r['response']!='s2_proportional':raise ValueError('necessary filter requires the explicit S2 proportional response; route to exact AC')
    catalog=json.loads((root/'catalogue.json').read_text());events=[e['contingency'] for e in catalog['entries'] if e['disposition']=='eligible']
    rows=[]
    for t,p in enumerate(r['periods']):
        source=json.loads((folder/f'period-{t+1}.json').read_text())['data'];outer=active_only_projection(source)
        base={'state':p['states']['base']}
        for e in events:
            cert=capacity_certificate(outer,base,e,active_response='s2_proportional_v1')
            rows.append(dict(period=t+1,event=e['id'],**cert))
    return dict(scope='fixed preventive dispatch and S2 proportional response only; reactive/circle constraints dropped as outer relaxation',
        input_lane=lane,full_catalogue_pairs=len(rows),certified_excluded_pairs=sum(x['certified_infeasible'] for x in rows),
        requires_exact_ac_pairs=sum(not x['certified_infeasible'] for x in rows),safe_predictions=0,
        physical_network_infeasibility_proven=False,rows=rows)
if __name__=='__main__':
    root=Path(sys.argv[1]);lane=sys.argv[2];result=screen(root,lane)
    (root/(lane+'-capacity-screen.json')).write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='rows'}))
