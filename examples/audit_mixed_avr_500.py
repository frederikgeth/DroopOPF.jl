"""Independent complex-current replay of mixed-control security campaign outputs."""
import copy
import json
import math
from pathlib import Path
from s2_followup_physics import check_case, equipment_valid

SUCCESS={'LOCALLY_SOLVED','ALMOST_LOCALLY_SOLVED','OPTIMAL'}
def load(path):
    return json.loads(Path(path).read_text())

def audit(folder):
    folder=Path(folder);spec=load(folder/'contract.json');r=load(folder/'result.json')
    r=r.get('data',r)
    valid=r['termination_status'] in SUCCESS and all(s['status'] in SUCCESS for s in r['stages'])
    valid &= len(r['periods'])==len(spec['factors'])==len(spec['duration_hours'])
    valid &= r['duration_hours']==spec['duration_hours'] and r['ramp_limits']==spec['ramps']
    valid &= r['angle_limits']==spec['angles'] and r['response']==spec['response'] and r['emergency']==spec['s2_emergency']
    expected_stages=['feasibility'] if spec['fixed_base'] else ['shedding','dr','loss'] if spec['s2_emergency'] and spec['events'] else ['loss']
    if spec.get('objective_policy')=='feasibility':expected_stages=['feasibility']
    if not spec['fixed_base'] and spec.get('objective_policy','loss') in ('reserve','reserve_loss'):
        expected_stages.insert(-1,'reserve')
        if spec['objective_policy']=='reserve':expected_stages.pop()
    valid &= [s['name'] for s in r['stages']]==expected_stages
    if spec.get('objective_upper_bound') is not None:valid &= r['objective_mwh']<=spec['objective_upper_bound']+1e-6
    for stage in r['stages']:
        if stage['name']=='reserve':
            delivered=[]
            for t,period in enumerate(r['periods']):
                study=load(folder/f'period-{t+1}.json')['data'];case=study['case']
                modes={a['generator_id']:a['mode'] for a in study['reactive_assignments']}
                for i,g in enumerate(case['generators']):
                    if not g['available'] or study['participation'].get(str(g['id']),0)<=0:continue
                    lo,hi=g['p_min'],g['p_max'];mode=modes[g['id']]
                    if mode['type']=='VoltVarDroop':lo=max(lo,mode['capability']['p_min']);hi=min(hi,mode['capability']['p_max'])
                    if g.get('s_rated') is not None:lo=max(lo,-g['s_rated']);hi=min(hi,g['s_rated'])
                    if hi>lo:delivered.append((period['states']['base']['pg'][i]-hi)/(hi-lo))
            valid &= bool(delivered) and max(delivered)<=stage['objective']+1e-8+1e-6
        key={'shedding':'shed','dr':'dr'}.get(stage['name'])
        if key:
            final=sum(sum(x[key]) for period in r['relief'] for x in period.values())
            valid &= final<=stage['objective']+1e-8+1e-6
    valid &= r['avr_bounds']==spec['avr_bounds'] and r['avr_movement_per_hour']==spec['avr_movement_per_hour']
    policy={str(c['control_id']):c for c in spec['droop_controls']}
    valid &= set(r['droops'])==set(policy)
    energy=0.;ramps=0.;avrmove=0.;rows=[]
    for t,p in enumerate(r['periods']):
        study=load(folder/f'period-{t+1}.json')['data'];original=study['case']
        modes={a['generator_id']:a['mode'] for a in study['reactive_assignments']} if study['reactive_assignments'] is not None else {}
        for lost in spec.get('reserve_generator_outages',[]):
            gs=original['generators'];li=next(i for i,g in enumerate(gs) if g['id']==lost)
            base=p['states']['base']['pg'];weights={}
            for g in gs:
                if not g['available'] or g['id']==lost:continue
                lo,hi=g['p_min'],g['p_max'];m=modes.get(g['id'],{})
                if m.get('type')=='VoltVarDroop':lo=max(lo,m['capability']['p_min']);hi=min(hi,m['capability']['p_max'])
                if g.get('s_rated') is not None:lo=max(lo,-g['s_rated']);hi=min(hi,g['s_rated'])
                if hi>lo:weights[g['id']]=study['participation'].get(str(g['id']),0.)
            total=sum(weights.values());valid &= total>0
            for i,g in enumerate(gs):
                w=weights.get(g['id'],0.)
                if w<=0:continue
                hi=g['p_max'];m=modes.get(g['id'],{})
                if m.get('type')=='VoltVarDroop':hi=min(hi,m['capability']['p_max'])
                if g.get('s_rated') is not None:hi=min(hi,g['s_rated'])
                movement=w/total*(base[li]+spec.get('reserve_margin_pu',0.))
                valid &= base[i]+movement<=hi+1e-6
                valid &= movement<=study['redispatch_limits'].get(str(g['id']),math.inf)+1e-6
        gids={g['id']:i for i,g in enumerate(original['generators'])}
        attached={a['generator_id']:a for a in original['attachments']}
        expected_assignments=copy.deepcopy(study['reactive_assignments'])
        for a in expected_assignments:
            gid=a['generator_id'];mode=a['mode']
            if mode['type']=='AVR' and str(gid) in r['avr_targets'][t]:
                target=r['avr_targets'][t][str(gid)];lo,hi=spec['avr_bounds'][str(gid)]
                valid &= lo-1e-6<=target<=hi+1e-6;mode['voltage_setpoint']=target
                if t:
                    avrmove=max(avrmove,abs(target-r['avr_targets'][t-1][str(gid)])-spec['avr_movement_per_hour']*spec['duration_hours'][t-1])
            if mode['type']=='VoltVarDroop':
                key=str(attached[gid]['control_id'])
                if key in r['droops']:
                    setting=r['droops'][key];v=mode['schedule']['v_ref']
                    defaults=dict(slope=mode['slope'],v_ref=v,deadband_low=v-mode['schedule']['v_db_low'],deadband_high=mode['schedule']['v_db_high']-v)
                    for k,x in setting.items():
                        lo,hi=policy[key]['bounds'][k] or (defaults[k],defaults[k]);valid &= lo-1e-6<=x<=hi+1e-6
                    mode['slope']=setting['slope'];mode['schedule'].update(v_ref=setting['v_ref'],v_db_low=setting['v_ref']-setting['deadband_low'],v_db_high=setting['v_ref']+setting['deadband_high'])
        valid &= expected_assignments==p['reactive_assignments']
        if spec.get('fixed_base_reference') is not None:
            reference=spec['fixed_base_reference'][t]
            valid &= p['states']['base']==reference['state'] and p['tap_settings']['base']==reference['taps'] and p['shunt_settings']['base']==reference['shunts']
        expected={'base',*spec['events']}
        valid &= set(p['states'])==set(p['tap_settings'])==set(p['shunt_settings'])==expected
        valid &= set(r['relief'][t])==(expected-{'base'} if r['emergency'] else set())
        for event in expected:
            c=copy.deepcopy(original);s=p['states'][event]
            if s is None:
                return dict(valid=False,reason='missing state')
            if event!='base':
                e=next(e for e in study['contingencies'] if e['id']==event)
                for b in c['network']['branches']:
                    if b['id'] in e['branch_ids']:b['available']=False
                for g in c['generators']:
                    if g['id'] in e['generator_ids']:g['available']=False
                if r['emergency']:
                    for b in c['network']['buses']:b['v_min']-=.05;b['v_max']+=.05
                    for b in c['network']['branches']:b['thermal_limit']*=1.1
            relvalid=True;drmw=shedmw=0.
            if event!='base' and r['emergency']:
                rel=r['relief'][t][event]
                for l,d,h in zip(c['loads'],rel['dr'],rel['shed']):
                    relvalid &= d>=-1e-6 and h>=-1e-6 and d<=.01*max(l['p'],0)+1e-6 and d+h<=.1*max(l['p'],0)+1e-6
                    ratio=l['q']/l['p'] if l['p']>0 else 0.;l['p']-=d+h;l['q']-=(d+h)*ratio
                drmw=sum(rel['dr'])*c['base_power'];shedmw=sum(rel['shed'])*c['base_power'];relvalid &= shedmw<=10+1e-6*c['base_power']
            # Build only droop attachments, with independent P-dependent clipping.
            c['controls']=[];c['attachments']=[];avr={};circle=float('inf')
            for a in expected_assignments:
                i=gids[a['generator_id']];g=c['generators'][i]
                if not g['available']:continue
                rating=g.get('s_rated');head=math.sqrt(max(rating**2-s['pg'][i]**2,0.)) if rating is not None else math.inf
                circle=min(circle,rating-math.hypot(s['pg'][i],s['qg'][i])) if rating is not None else circle
                lo=max(g['q_min'],-head);hi=min(g['q_max'],head);m=a['mode']
                if m['type']=='VoltVarDroop':
                    d=copy.deepcopy(m);d.pop('type');d['capability']['q_min']=max(d['capability']['q_min'],lo);d['capability']['q_max']=min(d['capability']['q_max'],hi)
                    c['controls'].append(d);c['attachments'].append(dict(generator_id=g['id'],control_id=len(c['controls']),location=a['location']))
                elif m['type']=='AVR':
                    key=(a['location']['kind'],a['location']['bus_id'],a['location'].get('side'),a['location'].get('branch_id'))
                    avr.setdefault(key,[]).append((i,lo,hi,m['voltage_setpoint']))
            idx={b['id']:i for i,b in enumerate(c['network']['buses'])};avrvalid=True
            for key,group in avr.items():
                err=s['vm'][idx[key[1]]]-group[0][3];q=sum(s['qg'][i] for i,lo,hi,target in group)
                lo=sum(x[1] for x in group);hi=sum(x[2] for x in group)
                avrvalid &= abs(err)<=1e-5 or err>0 and abs(q-lo)<=1e-6 or err<0 and abs(q-hi)<=1e-6
                positions=[(s['qg'][i]-lo)/(hi-lo) for i,lo,hi,target in group if hi-lo>1e-6]
                avrvalid &= not positions or max(positions)-min(positions)<=1e-5
            angles={str(b['id']):spec['angles'].get(str(b['id']),[-math.inf,math.inf]) for b in c['network']['branches']}
            physics=check_case(c,s,p['tap_settings'][event],p['shunt_settings'][event],angles)
            equip=equipment_valid(study,c,p['tap_settings'][event],p['shunt_settings'][event]);response=0.
            if event!='base':
                cp=study['control_policy']
                for setting,kind,budgets in [('tap_settings','taps','tap_movement_limits'),('shunt_settings','shunts','shunt_movement_limits')]:
                    for key,value in p[setting][event].items():
                        cap=0. if cp[kind]=='preventive' else (cp.get(budgets) or {}).get(key,math.inf)
                        equip &= abs(value-p[setting]['base'][key])<=cap+1e-6
                total=sum(study['participation'].get(str(g['id']),0.) for g in c['generators'] if g['available'])
                delta=p['balancing_power'][event]
                for i,g in enumerate(c['generators']):
                    if not g['available']:continue
                    alpha=study['participation'].get(str(g['id']),0.)/total
                    request=p['states']['base']['pg'][i]+alpha*delta
                    if r['response']=='limit_aware':
                        lower,upper=g['p_min'],g['p_max'];cap=study['redispatch_limits'].get(str(g['id']),math.inf)
                        mode=modes.get(g['id'],{})
                        if mode.get('type')=='VoltVarDroop':
                            lower=max(lower,mode['capability']['p_min']);upper=min(upper,mode['capability']['p_max'])
                        if g.get('s_rated') is not None:lower=max(lower,-g['s_rated']);upper=min(upper,g['s_rated'])
                        base=p['states']['base']['pg'][i];request=max(lower,base-cap,min(upper,base+cap,request))
                    response=max(response,abs(s['pg'][i]-request))
            rowvalid=physics['valid'] and equip and relvalid and avrvalid and circle>=-1e-6 and response<=1e-6
            valid &= rowvalid
            rows.append(dict(period=t+1,scenario=event,valid=bool(rowvalid),balance_max_pu=physics['power_balance_max_pu'],droop_max_pu=physics['exact_droop_max_pu'],avr_valid=bool(avrvalid),circle_margin_pu=circle,response_violation=response,dr_mw=drmw,shed_mw=shedmw))
        base=p['states']['base'];energy+=spec['duration_hours'][t]*original['base_power']*(sum(base['pg'])-sum(l['p'] for l in original['loads']))
        if t:
            for i,g in enumerate(original['generators']):
                limits=spec['ramps'].get(str(g['id']))
                if limits is None:continue
                d=base['pg'][i]-r['periods'][t-1]['states']['base']['pg'][i];dt=spec['duration_hours'][t-1]
                ramps=max(ramps,d-limits[0]*dt,-d-limits[1]*dt)
    error=abs(energy-r['objective_mwh']);valid &= ramps<=1e-6 and avrmove<=1e-6 and error<=1e-6
    return dict(valid=bool(valid),rows=rows,ramp_violation=ramps,avr_movement_violation=avrmove,objective_error_mwh=error,objective_recomputed_mwh=energy)

if __name__=='__main__':
    import sys
    folder=Path(sys.argv[1]);result=audit(folder)
    (folder/'python-audit.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    print(json.dumps(dict(valid=result['valid'],states=len(result.get('rows',[])))))
