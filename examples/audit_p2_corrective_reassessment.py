"""Independent scalar AC, exact response, discrete bank and corrective-budget audit."""
import cmath, copy, hashlib, json, math, sys
from pathlib import Path
from audit_p2_preventive_controls import load, verify_saved_cut
TOL=1e-6

def replay(study, result, angles):
    c=study['case']; net=c['network']; buses=net['buses']; gens=c['generators']
    idx={b['id']:i for i,b in enumerate(buses)}; gi={g['id']:i for i,g in enumerate(gens)}
    controls={a['generator_id']:(c['controls'][a['control_id']-1],a) for a in c['attachments']}
    events={'base':{'branch_ids':[],'generator_ids':[]}}
    events.update({e['id']:e for e in study['contingencies']})
    base=result['states'].get('base'); checks=[]; max_balance=max_droop=max_response=0.
    if base is None:
        return {'physical_valid':False,'reason':'missing base'}
    weights=study['participation']; limits=study['redispatch_limits']
    for sid,event in events.items():
        s=result['states'].get(sid)
        if s is None:
            checks.append({'id':sid,'valid':False,'reason':'missing state'}); continue
        V=[vm*cmath.exp(1j*va) for vm,va in zip(s['vm'],s['va'])]
        injection=[0j for _ in buses]; violations=[]
        def violation(name,value,tol=TOL):
            if value>tol: violations.append(name)
        violation('reference',max(abs(s['va'][i]) for i,b in enumerate(buses) if b['reference']))
        for i,b in enumerate(buses):
            violation('voltage',max(b['v_min']-s['vm'][i],s['vm'][i]-b['v_max']))
        for b in net['branches']:
            if not b['available'] or b['id'] in event['branch_ids']: continue
            i,j=idx[b['from_bus']],idx[b['to_bus']]
            ratio=result['tap_settings'].get(sid,{}).get(str(b['id']),b['tap_ratio'])
            t=ratio*cmath.exp(1j*b['phase_shift']); y=1/complex(b['resistance'],b['reactance'])
            charge=1j*b['charging']/2
            sf=V[i]*(((y+charge)/ratio**2*V[i]-y/t.conjugate()*V[j]).conjugate())
            st=V[j]*(((y+charge)*V[j]-y/t*V[i]).conjugate())
            injection[i]+=sf; injection[j]+=st
            violation('thermal',max(abs(sf),abs(st))-b['thermal_limit'])
            if str(b['id']) in angles:
                lo,hi=angles[str(b['id'])]; a=s['va'][i]-s['va'][j]
                violation('angle',max(lo-a,a-hi))
        for sh in net.get('shunts',[]):
            if sh['available']:
                i=idx[sh['bus_id']]; injection[i]+=complex(sh['conductance'],-sh['susceptance'])*abs(V[i])**2
        for bank in net.get('banks',[]):
            if not bank['available']:continue
            B=result['shunt_settings'].get(sid,{}).get(str(bank['id']))
            if B is None:
                G=sum(n*g for n,g in zip(bank['state'],bank['step_conductances']))
                B=sum(n*b for n,b in zip(bank['state'],bank['step_susceptances']))
            else:
                G=B/bank['step_susceptances'][0]*bank['step_conductances'][0]
            i=idx[bank['bus_id']];injection[i]+=complex(G,-B)*abs(V[i])**2
        for l in c['loads']:
            injection[idx[l['bus_id']]]+=complex(l['p'],l['q'])
        active=[]
        for i,g in enumerate(gens):
            available=g['available'] and g['id'] not in event['generator_ids']
            if not available:
                violation('outaged generation',max(abs(s['pg'][i]),abs(s['qg'][i])),1e-8)
                continue
            injection[idx[g['bus_id']]]-=complex(s['pg'][i],s['qg'][i])
            plo,phi=g['p_min'],g['p_max']
            violation('P capability',max(plo-s['pg'][i],s['pg'][i]-phi))
            violation('Q capability',max(g['q_min']-s['qg'][i],s['qg'][i]-g['q_max']))
            if g['id'] in controls:
                d,a=controls[g['id']]; cap=d['capability']; sch=d['schedule'];v=s['vm'][idx[a['location']['bus_id']]]
                raw=d['q_at_deadband']+max(sch['v_db_low']-v,0)/d['slope']-max(v-sch['v_db_high'],0)/d['slope']
                expected=min(cap['q_max'],max(cap['q_min'],raw))
                err=abs(s['qg'][i]-expected);max_droop=max(max_droop,err);violation('droop',err,1e-5)
                plo,phi=max(plo,cap['p_min']),min(phi,cap['p_max'])
                violation('controller P capability',max(plo-s['pg'][i],s['pg'][i]-phi))
            w=weights.get(str(g['id']),0.) if phi>plo else 0.
            active.append((i,g,plo,phi,w))
        residual=max([0.]+[max(abs(x.real),abs(x.imag)) for x in injection])
        max_balance=max(max_balance,residual);violation('AC balance',residual)
        if sid!='base':
            total=sum(x[4] for x in active)
            if total<=0:violations.append('no participant')
            signal=result['balancing_power'].get(sid)
            if signal is None:violations.append('missing signal')
            else:
                for i,g,lo,hi,w in active:
                    if str(g['id']) in limits:
                        r=limits[str(g['id'])];lo,hi=max(lo,base['pg'][i]-r),min(hi,base['pg'][i]+r)
                    expected=base['pg'][i] if w==0 else min(hi,max(lo,base['pg'][i]+w/total*signal))
                    err=abs(s['pg'][i]-expected);max_response=max(max_response,err);violation('active response',err)
        for family,selected,key in [('tap_settings',study['tap_controls'],'branch_id'),('shunt_settings',study['shunt_controls'],'bank_id')]:
            for ctl in selected:
                did=str(ctl[key]); val=result[family].get(sid,{}).get(did)
                if family=='tap_settings' and ctl[key] in event['branch_ids']:continue
                if val is None:violations.append('missing equipment');continue
                lo,hi=ctl.get('lower'),ctl.get('upper')
                if family=='shunt_settings':
                    bank=next(x for x in net['banks'] if x['id']==ctl[key])
                    legal=[x[0]*bank['step_susceptances'][0] for x in bank['legal_states']]
                    lo=min(legal) if lo is None else lo; hi=max(legal) if hi is None else hi
                if lo is not None:violation('equipment lower',lo-val)
                if hi is not None:violation('equipment upper',val-hi)
                timing_key='taps' if family=='tap_settings' else 'shunts'
                policy=study['control_policy']
                budget=0. if policy[timing_key]=='preventive' else (policy[timing_key[:-1]+'_movement_limits'] or {}).get(did,math.inf)
                violation('equipment movement budget',abs(val-result[family]['base'][did])-budget)
        checks.append({'id':sid,'valid':not violations,'violations':sorted(set(violations)),'balance':residual})
    return {'physical_valid':all(x['valid'] for x in checks),
            'physical_without_angles':all('reason' not in x and not (set(x.get('violations',[]))-{'angle'}) for x in checks),'states':checks,
            'max_ac_balance':max_balance,'max_exact_droop_error':max_droop,'max_response_error':max_response}


def main(root):
    root=Path(root);previous=root.parent/'p2_preventive_controls_20261021'
    repo=root.resolve().parent.parent
    input_changes=[p for p,h in load(root/'input_hashes.json').items() if hashlib.sha256((repo/p).read_bytes()).hexdigest()!=h]
    source_changes=[str(p.relative_to(root/'source_snapshot')) for p in (root/'source_snapshot').rglob('*') if p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest()!=hashlib.sha256((repo/p.relative_to(root/'source_snapshot')).read_bytes()).hexdigest()]
    reference=load(previous/'bank_fixture/preventive/primary/study-1.0.json')['data']['case']['controls']
    records=[];negative=[];states=0
    for sp in sorted(root.glob('bank_fixture/**/study.json')):
        study=load(sp)['data'];result=load(sp.with_name('result.json'))['data']
        audit=replay(study,result,{})
        errors=[]
        if study['case']['controls']!=reference:errors.append('curve retuned')
        parent=sp.parent;islegal=parent.name in ('legal','preventive_legal')
        if islegal:
            for sid,settings in result['shunt_settings'].items():
                for v in settings.values():
                    if min(abs(v-x) for x in (0.,.02,.04,.06))>TOL:errors.append('illegal bank section')
        if parent.name in ('legal','continuous'):
            stage=parent.parent.name;policy=study['control_policy']
            expected={'immediate':(0.,0.),'settled60':(.0125,.02),'settled120':(.025,.04)}[stage]
            for family,key,budget in (('taps','tap_movement_limits',expected[0]),('shunts','shunt_movement_limits',expected[1])):
                did='11' if family=='taps' else '201'
                actual=0. if policy[family]=='preventive' else (policy[key] or {}).get(did,math.inf)
                if abs(actual-budget)>1e-12:errors.append('wrong stage budget')
            base=load(parent.parent.parent/'preventive_legal/result.json')['data']
            if result['states']['base']!=base['states']['base']:errors.append('base state changed')
            for family in ('tap_settings','shunt_settings'):
                if result[family]['base']!=base[family]['base']:errors.append('base equipment changed')
        native=result['termination_status'] in ('LOCALLY_SOLVED','ALMOST_LOCALLY_SOLVED','OPTIMAL')
        accepted=native and audit['physical_valid'] and not errors
        records.append(dict(path=str(sp.relative_to(root)),accepted=accepted,policy_errors=errors,**audit))
        states+=len(audit.get('states',[]))
        if islegal and audit['physical_valid'] and len(negative)<6:
            bad=copy.deepcopy(result);sid=next(k for k in bad['states'] if k!='base')
            bad['shunt_settings'][sid]['201']+=.04
            corrupted_equipment=not replay(study,bad,{})['physical_valid']
            # Preserve AC values but reduce the policy budget below observed movement.
            restrictive=copy.deepcopy(study)
            restrictive['control_policy']['taps']='preventive';restrictive['control_policy']['shunts']='preventive'
            signal=copy.deepcopy(result);signal['balancing_power'][sid]+=1.
            negative.append(dict(path=str(sp.relative_to(root)),corrupt_equipment_rejected=corrupted_equipment,
                corrupt_response_rejected=not replay(study,signal,{})['physical_valid']))
    certificates=[]
    for name in ('pglib_opf_case14_ieee','pglib_opf_case39_epri'):
        d=previous/name;c=load(d/'source.json')['data']['case']
        events={e['contingency']['id']:e['contingency'] for e in load(d/'catalog.json')['data']['entries']}
        cuts=load(d/'cut_certificates.json');verified=all(verify_saved_cut(c,events[x['outage']],x) for x in cuts)
        certificates.append(dict(case=name,verified=verified,count=len(cuts),positive=sum(x['certified_obstruction'] for x in cuts),
            corrective_invariant='proof uses unchanged Pmax, thermal limits, demand and passivity; independent of tap/shunt/droop settings'))
    budget_negatives=[]
    for sp in sorted(root.glob('bank_fixture/*/settled*/legal/study.json')):
        study=load(sp)['data'];result=load(sp.with_name('result.json'))['data']
        changed=copy.deepcopy(study)
        changed['control_policy']['taps']='preventive';changed['control_policy']['shunts']='preventive'
        moved=any(abs(v['201']-result['shunt_settings']['base']['201'])>TOL for sid,v in result['shunt_settings'].items() if sid!='base') or any(abs(v.get('11',result['tap_settings']['base']['11'])-result['tap_settings']['base']['11'])>TOL for sid,v in result['tap_settings'].items() if sid!='base')
        if moved:budget_negatives.append(not replay(changed,result,{})['physical_valid'])
    hashes={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file() and p.name not in ('independent_audit.json','manifest.json')}
    output=dict(input_changes=input_changes,source_changes=source_changes,records=records,record_count=len(records),state_count=states,certificates=certificates,negative_controls=negative,budget_only_corruptions=budget_negatives,
        passed=not input_changes and not source_changes and len(records)==72 and all(x['accepted'] for x in records) and all(x['verified'] for x in certificates) and
        bool(budget_negatives) and all(budget_negatives) and all(x['corrupt_equipment_rejected'] and x['corrupt_response_rejected'] for x in negative))
    (root/'independent_audit.json').write_text(json.dumps(output,indent=2)+'\n')
    (root/'manifest.json').write_text(json.dumps(hashes,indent=2)+'\n')
    print(json.dumps({k:output[k] for k in ('record_count','state_count','certificates','passed')},indent=2))
    if not output['passed']:raise SystemExit(1)
if __name__=='__main__':main(sys.argv[1])
