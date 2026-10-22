"""Independent scalar AC/control replay for the staged P2 configuration study."""
import cmath, copy, hashlib, json, math, sys
from fractions import Fraction as F
from pathlib import Path

TOL = 1e-6

def load(p):
    return json.loads(Path(p).read_text())

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
                violation('preventive equipment movement',abs(val-result[family]['base'][did]))
        checks.append({'id':sid,'valid':not violations,'violations':sorted(set(violations)),'balance':residual})
    return {'physical_valid':all(x['valid'] for x in checks),
            'physical_without_angles':all('reason' not in x and not (set(x.get('violations',[]))-{'angle'}) for x in checks),'states':checks,
            'max_ac_balance':max_balance,'max_exact_droop_error':max_droop,'max_response_error':max_response}


def cut_certificate(case,event,factor):
    from collections import deque
    buses=[b['id'] for b in case['network']['buses']]; src=-1;snk=-2
    residual={i:{} for i in buses+[src,snk]}
    def add(i,j,c):
        residual[i][j]=residual[i].get(j,F(0))+c
        residual[j].setdefault(i,F(0))
    for g in case['generators']:
        if g['available'] and g['id'] not in event['generator_ids']:
            add(src,g['bus_id'],F(str(g['p_max'])))
    for load in case['loads']:
        if load['p']<0: return None # outside this certificate implementation
        add(load['bus_id'],snk,F(str(load['p']))*F(str(factor)))
    branches=[b for b in case['network']['branches'] if b['available'] and b['id'] not in event['branch_ids']]
    for b in branches:
        cap=F(str(b['thermal_limit']));add(b['from_bus'],b['to_bus'],cap);add(b['to_bus'],b['from_bus'],cap)
    while True:
        parent={src:None};queue=deque([src])
        while queue and snk not in parent:
            i=queue.popleft()
            for j,c in residual[i].items():
                if c>0 and j not in parent:parent[j]=i;queue.append(j)
        if snk not in parent:break
        path=[];j=snk
        while parent[j] is not None:path.append((parent[j],j));j=parent[j]
        flow=min(residual[i][j] for i,j in path)
        for i,j in path:residual[i][j]-=flow;residual[j][i]+=flow
    inside=set(buses)-set(parent)
    D=sum((F(str(l['p']))*F(str(factor)) for l in case['loads'] if l['bus_id'] in inside),F(0))
    generators=[g for g in case['generators'] if g['bus_id'] in inside]
    G=sum((F(str(g['p_max'])) for g in generators if g['available'] and g['id'] not in event['generator_ids']),F(0))
    crossing=[b for b in branches if (b['from_bus'] in inside)!=(b['to_bus'] in inside)]
    capacity=sum((F(str(b['thermal_limit'])) for b in crossing),F(0))
    allowance=F(1,10**6)*(len(inside)+len(generators)+len(crossing))
    gap=D-G-capacity-allowance
    return {'inside_buses':sorted(inside),'demand_pu':float(D),'generation_capacity_pu':float(G),
        'boundary_capacity_pu':float(capacity),'crossing_branches':[b['id'] for b in crossing],
        'exact_gap':str(gap),'gap_pu':float(gap),'certified_obstruction':gap>0}

def verify_saved_cut(case,event,row):
    """Verify a saved cut without relying on max-flow discovery or solver status."""
    inside=set(row['inside_buses'])
    if not inside<=set(b['id'] for b in case['network']['buses']):return False
    factor=F(str(row['factor']))
    demand=sum((factor*F(str(l['p'])) for l in case['loads'] if l['bus_id'] in inside),F(0))
    generators=[g for g in case['generators'] if g['bus_id'] in inside]
    generation=sum((F(str(g['p_max'])) for g in generators if g['available'] and g['id'] not in event['generator_ids']),F(0))
    boundary=[b for b in case['network']['branches'] if b['available'] and b['id'] not in event['branch_ids'] and ((b['from_bus'] in inside)!=(b['to_bus'] in inside))]
    if set(row['crossing_branches'])!=set(b['id'] for b in boundary):return False
    capacity=sum((F(str(b['thermal_limit'])) for b in boundary),F(0))
    allowance=F(1,1000000)*(len(inside)+len(generators)+len(boundary))
    gap=demand-generation-capacity-allowance
    passive=all(b['resistance']>=0 and b['tap_ratio']>0 for b in case['network']['branches']) and all(s['conductance']>=0 for s in case['network'].get('shunts',[])) and all(all(g>=0 for g in b['step_conductances']) for b in case['network'].get('banks',[]))
    return str(gap)==row['exact_gap'] and row['certified_obstruction']==(gap>0 and passive)

def main(root):
    root=Path(root); records=[]; negative=[]; certificates=[]; discrepancies=[]
    protocol=load(root/'protocol.json')
    source_changes=[];workspace_source_changes=[]
    for name,expected in protocol['source_hashes'].items():
        frozen=root/'source_snapshot'/name
        path=frozen if frozen.exists() else Path(name)
        if hashlib.sha256(path.read_bytes()).hexdigest()!=expected:source_changes.append(name)
        if Path(name).exists() and hashlib.sha256(Path(name).read_bytes()).hexdigest()!=expected:workspace_source_changes.append(name)
    input_manifest=load(root/'input_snapshot_manifest.json') if (root/'input_snapshot_manifest.json').exists() else {}
    for meta_path in root.glob('*/inputs.json'):
        for original,expected in load(meta_path)['source_hashes'].items():
            path=root/input_manifest[original]['path'] if original in input_manifest else Path(original)
            if hashlib.sha256(path.read_bytes()).hexdigest()!=expected:source_changes.append('input:'+original)
    selections={(r['name'],r['lane']):r['selected_attempt'] for r in load(root/'summary.json')}
    cut_verification=[];cut_negative=[]
    for inp in sorted(root.glob('*/inputs.json')):
        d=inp.parent; meta=load(inp); angles=meta['angles']; source=load(d/'source.json')['data']['case']
        passive=all(b['resistance']>=0 and b['tap_ratio']>0 for b in source['network']['branches']) and all(s['conductance']>=0 for s in source['network'].get('shunts',[])) and all(all(g>=0 for g in b['step_conductances']) for b in source['network'].get('banks',[]))
        entries=load(d/'catalog.json')['data']['entries']
        cuts=[]
        for factor in protocol['training']:
            for entry in entries:
                if entry['disposition']!='eligible':continue
                cut=cut_certificate(source,entry['contingency'],factor)
                if cut is not None:
                    cut.update(factor=factor,outage=entry['contingency']['id'],device_kind=entry['device_kind'],passive_network=passive)
                    cut['certified_obstruction']=cut['certified_obstruction'] and passive
                    cuts.append(cut)
                    cut_verification.append(verify_saved_cut(source,entry['contingency'],cut))
                    if cut['certified_obstruction'] and len(cut_negative)<3:
                        corrupted=copy.deepcopy(cut);corrupted['exact_gap']='0'
                        cut_negative.append(not verify_saved_cut(source,entry['contingency'],corrupted))
        (d/'cut_certificates.json').write_text(json.dumps(cuts,indent=2)+'\n')
        for row in load(d/'supply_check.json'):
            event=next(e for e in load(d/'catalog.json')['data']['entries'] if e['contingency']['id']==row['outage'])['contingency']
            surviving=[g for g in source['generators'] if g['available'] and g['id'] not in event['generator_ids']]
            demand=F(str(row['factor']))*sum((F(str(l['p'])) for l in source['loads']),F(0))
            capacity=sum((F(str(g['p_max'])) for g in surviving),F(0))
            allowance=F(1,10**6)*(len(source['network']['buses'])+len(surviving))+F(1,10**8)*(len(source['generators'])-len(surviving))
            gap=demand-capacity-allowance
            certificates.append({'case':d.name,'factor':row['factor'],'outage':row['outage'],
                'certified_supply_obstruction':passive and gap>0,'gap_pu':float(gap),
                'exact_gap':str(gap),'passive_network':passive})
        for sp in sorted(d.glob('**/study*.json')):
            if sp.name=='study.json':rp=sp.with_name('result.json')
            else:rp=sp.with_name(sp.name.replace('study-','result-'))
            if not rp.exists():continue
            study=load(sp)['data'];result=load(rp)['data'];audit=replay(study,result,angles)
            parts=sp.relative_to(d).parts; lane=parts[0]; policy_errors=[]
            for ref,actual in zip(source['controls'],study['case']['controls']):
                multiplier=(1.,1.) if lane=='fixed' else (.5,2.)
                if not multiplier[0]*ref['slope']-1e-8<=actual['slope']<=multiplier[1]*ref['slope']+1e-8:policy_errors.append('slope bounds')
                allowed=0 if lane=='fixed' else .02
                if abs(actual['schedule']['v_ref']-ref['schedule']['v_ref'])>allowed+1e-8:policy_errors.append('reference bounds')
                for side in ('v_db_low','v_db_high'):
                    rw=abs(ref['schedule'][side]-ref['schedule']['v_ref'])
                    aw=abs(actual['schedule'][side]-actual['schedule']['v_ref'])
                    if abs(rw-aw)>1e-8:policy_errors.append('changed deadband')
                if actual['q_at_deadband']!=ref['q_at_deadband'] or actual['capability']!=ref['capability']:policy_errors.append('changed capability/Q reference')
            if 'heldout' in parts:
                selected=selections[(d.name,lane)];master=load(d/lane/selected/'study-1.0.json')['data']
                witness=load(d/lane/selected/'result-1.0.json')['data']
                if study['case']['controls']!=master['case']['controls']:policy_errors.append('heldout controller retuning')
                for branch in study['case']['network']['branches']:
                    expected=witness['tap_settings']['base'].get(str(branch['id']),next(x for x in source['network']['branches'] if x['id']==branch['id'])['tap_ratio'])
                    if abs(branch['tap_ratio']-expected)>1e-8:policy_errors.append('heldout tap retuning')
            if lane=='rounded_candidate':
                master=load(d/'preventive'/'primary'/'study-1.0.json')['data']
                witness=load(d/'preventive'/'primary'/'result-1.0.json')['data']
                rule=load(d/lane/'protocol.json')
                if study['case']['controls']!=master['case']['controls']:policy_errors.append('rounded controller retuning')
                for branch in study['case']['network']['branches']:
                    original=next(x for x in source['network']['branches'] if x['id']==branch['id'])
                    if branch['tap_ratio']!=original['tap_ratio']:policy_errors.append('rounded tap not supplied')
                for bank in source['network']['banks']:
                    selected_state=rule['bank_states'][str(bank['id'])]
                    legal=bank['legal_states']
                    if selected_state not in legal:policy_errors.append('illegal discrete bank state')
                    values=[sum(n*b for n,b in zip(state,bank['step_susceptances'])) for state in legal]
                    nearest=min(range(len(values)),key=lambda i:abs(values[i]-witness['shunt_settings']['base'][str(bank['id'])]))
                    if selected_state!=legal[nearest]:policy_errors.append('bank selection differs from frozen rule')
                    B=sum(n*b for n,b in zip(selected_state,bank['step_susceptances']))
                    G=sum(n*g for n,g in zip(selected_state,bank['step_conductances']))
                    sh=next(x for x in study['case']['network']['shunts'] if x['id']==bank['id'])
                    if abs(sh['susceptance']-B)>1e-12 or abs(sh['conductance']-G)>1e-12:policy_errors.append('rounded bank mismatch')
            base=result['states'].get('base')
            cost=None if base is None else sum((base['pg'][i]-g['initial_p'])**2+1e-3*(base['qg'][i]-g['initial_q'])**2 for i,g in enumerate(study['case']['generators']))
            objective_error=None if cost is None or result['objective'] is None else abs(cost-result['objective'])
            if objective_error is not None and objective_error>1e-7:policy_errors.append('objective mismatch')
            audit.update(policy_errors=policy_errors,objective_error=objective_error)
            native=result['termination_status'] in ('LOCALLY_SOLVED','ALMOST_LOCALLY_SOLVED','OPTIMAL')
            audit.update(path=str(sp.relative_to(root)),native_success=native,accepted=native and audit['physical_valid'] and not policy_errors)
            records.append(audit)
            vp=sp.with_name('validation.json') if sp.name=='study.json' else sp.with_name(sp.name.replace('study-','validation-'))
            if vp.exists():
                v=load(vp); library_valid=v.get('valid',False)
                if audit['accepted']!=library_valid:discrepancies.append(str(sp))
                libreport=v.get('report',v)
                if 'physical_valid' in libreport and audit.get('physical_without_angles',False)!=libreport['physical_valid']:
                    discrepancies.append(str(sp)+':physical')
            if audit['physical_valid'] and len(negative)<3:
                bad=copy.deepcopy(result);bad['states']['base']['pg'][0]+=.001
                altered=copy.deepcopy(result)
                first_outage=next(iter(altered['balancing_power']))
                altered['balancing_power'][first_outage]+=.01
                response=replay(study,altered,angles)
                negative.append({'path':audit['path'],
                    'corrupted_dispatch_rejected':not replay(study,bad,angles)['physical_valid'],
                    'corrupted_response_rejected':not response['physical_valid'],
                    'response_control_preserves_AC_balance':response['max_ac_balance']<=TOL})
    # Check sharing across demands from saved quantities, not optimization flags.
    sharing=[]
    for path in root.glob('*/*/*/summary.json'):
        s=load(path)
        if not isinstance(s,dict) or 'equipment' not in s:continue
        e=s['equipment'];first=e[0];spread=max([0.]+[abs(x[k][i]-first[k][i]) for x in e for k in ('taps','shunts') for i in x[k]])
        studies=[load(p)['data']['case']['controls'] for p in sorted(path.parent.glob('study-*.json'))]
        curves_equal=all(x==studies[0] for x in studies)
        sharing.append({'path':str(path.relative_to(root)),'equipment_spread':spread,'valid':spread<=TOL and curves_equal,'shared_curves':curves_equal,
            'claimed_accepted':s['accepted'],'reported_spread_matches':abs(spread-s['equipment_cross_demand_error'])<=1e-8})
    output={'records':records,'record_count':len(records),'state_count':sum(len(x.get('states',[])) for x in records),
        'classification_discrepancies':discrepancies,'source_changes':source_changes,'workspace_source_changes':workspace_source_changes,'negative_controls':negative,
        'supply_certificates':certificates,'sharing':sharing,
        'cut_verification':{'count':len(cut_verification),'all_verified':all(cut_verification),'corrupted_proofs_rejected':cut_negative},
        'pass':not discrepancies and not source_changes and all(cut_verification) and all(cut_negative) and all(x['corrupted_dispatch_rejected'] and x['corrupted_response_rejected'] and x['response_control_preserves_AC_balance'] for x in negative) and all(x['reported_spread_matches'] and (not x['claimed_accepted'] or x['valid']) for x in sharing),
        'audit_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (root/'independent_audit.json').write_text(json.dumps(output,indent=2)+'\n')
    print(json.dumps({k:output[k] for k in ('record_count','state_count','classification_discrepancies','pass')}))
    if not output['pass']:raise SystemExit(1)
if __name__=='__main__':main(sys.argv[1])
