"""Independent standard-library AC and exact-droop evaluator for S2 follow-up."""
import cmath

def check_case(c,state,taps,banks,angles):
    ids={b['id']:i for i,b in enumerate(c['network']['buses'])}
    gids={g['id']:i for i,g in enumerate(c['generators'])}
    n=c['network'];v=[cmath.rect(m,a) for m,a in zip(state['vm'],state['va'])]
    residual=[0j]*len(v);thermal=angle=float('inf');flows={}
    for b in n['branches']:
        if not b['available']:continue
        i,j=ids[b['from_bus']],ids[b['to_bus']]
        t=cmath.rect(taps.get(str(b['id']),b['tap_ratio']),b['phase_shift'])
        y=1/complex(b['resistance'],b['reactance']);yc=complex(0,b['charging']/2)
        sf=v[i]*(((y+yc)/abs(t)**2*v[i]-y/t.conjugate()*v[j]).conjugate())
        st=v[j]*(((y+yc)*v[j]-y/t*v[i]).conjugate())
        residual[i]-=sf;residual[j]-=st
        flows[str(b['id'])]=max(abs(sf),abs(st))
        thermal=min(thermal,b['thermal_limit']-max(abs(sf),abs(st)))
        lo,hi=angles[str(b['id'])];a=state['va'][i]-state['va'][j];angle=min(angle,a-lo,hi-a)
    for b in n['shunts']:
        if b['available']:
            i=ids[b['bus_id']];residual[i]-=complex(b['conductance'],-b['susceptance'])*state['vm'][i]**2
    for b in n['banks']:
        if not b['available']:continue
        bs=sum(x*y for x,y in zip(b['step_susceptances'],b['state']))
        gs=sum(x*y for x,y in zip(b['step_conductances'],b['state']))
        if str(b['id']) in banks:
            bs=banks[str(b['id'])];gs=b['step_conductances'][0]/b['step_susceptances'][0]*bs
        residual[ids[b['bus_id']]]-=complex(gs,-bs)*state['vm'][ids[b['bus_id']]]**2
    for l in c['loads']:residual[ids[l['bus_id']]]-=complex(l['p'],l['q'])
    p=q=float('inf');unavailable=0.
    for i,g in enumerate(c['generators']):
        residual[ids[g['bus_id']]]+=complex(state['pg'][i],state['qg'][i])
        if not g['available']:
            unavailable=max(unavailable,abs(state['pg'][i]),abs(state['qg'][i]));continue
        p=min(p,state['pg'][i]-g['p_min'],g['p_max']-state['pg'][i])
        q=min(q,state['qg'][i]-g['q_min'],g['q_max']-state['qg'][i])
    droop=0.;cap_p=0.;droop_rows=[]
    for a in c['attachments']:
        i=gids[a['generator_id']]
        if not c['generators'][i]['available']:continue
        d=c['controls'][a['control_id']-1];s=d['schedule'];cap=d['capability'];vm=state['vm'][ids[a['location']['bus_id']]]
        raw=d['q_at_deadband']+(max(s['v_db_low']-vm,0)-max(vm-s['v_db_high'],0))/d['slope']
        exact=max(cap['q_min'],min(cap['q_max'],raw));droop=max(droop,abs(state['qg'][i]-exact))
        droop_rows.append(dict(generator=a['generator_id'],bus=a['location']['bus_id'],actual_q_pu=state['qg'][i],exact_q_pu=exact,residual_pu=abs(state['qg'][i]-exact)))
        cap_p=max(cap_p,cap['p_min']-state['pg'][i],state['pg'][i]-cap['p_max'])
    voltage=min(min(state['vm'][i]-b['v_min'],b['v_max']-state['vm'][i]) for i,b in enumerate(n['buses']))
    reference=max(abs(state['va'][i]) for i,b in enumerate(n['buses']) if b['reference'])
    power=max(max(abs(z.real),abs(z.imag)) for z in residual)
    valid=power<=1e-6 and droop<=1e-5 and min(thermal,angle,p,q,voltage)>=-1e-6 and unavailable<=1e-8 and reference<=1e-6 and cap_p<=1e-6
    return dict(valid=bool(valid),power_balance_max_pu=power,exact_droop_max_pu=droop,
                thermal_min_margin_pu=thermal,angle_min_margin_rad=angle,generator_p_min_margin_pu=p,
                generator_q_min_margin_pu=q,voltage_min_margin_pu=voltage,unavailable_generation_max_pu=unavailable,
                reference_angle_error_rad=reference,control_p_violation_max_pu=cap_p,branch_max_terminal_s_pu=flows,
                bus_balance=[dict(bus=b['id'],p_pu=residual[i].real,q_pu=residual[i].imag) for i,b in enumerate(n['buses'])],
                droop_by_generator=droop_rows)

def equipment_valid(study,c,taps,banks):
    expected={str(x['branch_id']) for x in study['tap_controls'] if any(b['id']==x['branch_id'] and b['available'] for b in c['network']['branches'])}
    valid=set(taps)==expected and set(banks)=={str(x['bank_id']) for x in study['shunt_controls']}
    for key,settings,id_key in [('tap_controls',taps,'branch_id'),('shunt_controls',banks,'bank_id')]:
        for item in study[key]:
            if str(item[id_key]) not in settings:continue
            lo,hi=item['lower'],item['upper']
            if lo is None or hi is None:
                b=next(b for b in c['network']['banks'] if b['id']==item[id_key])
                legal=[sum(x*y for x,y in zip(b['step_susceptances'],st)) for st in b['legal_states']]
                lo,hi=min(legal),max(legal)
            valid &= lo-1e-6<=settings[str(item[id_key])]<=hi+1e-6
    return bool(valid)
