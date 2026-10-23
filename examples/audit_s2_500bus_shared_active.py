"""Exact source/row/ray replay of the coupled preventive-dispatch relaxation."""
import copy
import cmath
from fractions import Fraction as Q
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'artifacts/s2_scopf/ieee500_native'
OUT=BASE/'emergency_loadability/shared_active_bound'
F=lambda x:Q(x.replace('//','/') if isinstance(x,str) else x)
load=lambda p:json.loads(Path(p).read_text())


def verify(folder):
    folder=Path(folder);p=folder/'result.json';r=load(p)
    source=BASE/'pilot_study.json';study=load(source)['data']
    assert hashlib.sha256(source.read_bytes()).hexdigest()==r['source_sha256']
    assert r['participation']==study['participation'] and r['tap_controls']==study['tap_controls']
    tol,small,rtol=map(F,(r['power_tolerance'],r['relief_tolerance'],r['response_tolerance']))
    assert tol>=F('0.000001') and small>=F('0.00000001') and rtol>=tol+F('0.000000001')
    normal_targeted=r.get('normal_targeted',False)
    assert [e['id'] for e in r['events']]==(['generator_14','generator_60','branch_36','branch_562'] if r.get('include_b562',normal_targeted) else ['generator_14','generator_60','branch_36'])
    bounds=[];rows=[];next_index=1
    taps={t['branch_id']:t for t in study['tap_controls']}

    def variables(indices,expected):
        nonlocal next_index
        assert indices==list(range(next_index,next_index+len(expected)))
        next_index+=len(expected);bounds.extend(expected)

    def le(coeff,rhs,meta):
        rows.append(({i:a for i,a in coeff.items() if a},F(rhs),meta))

    def eq(coeff,rhs,meta,tolerance=Q(0)):
        le(coeff,F(rhs)+tolerance,dict(meta,sign=1))
        le({i:-a for i,a in coeff.items()},-F(rhs)+tolerance,dict(meta,sign=-1))

    branches_by_state=[]
    for k,b in enumerate(r['blocks'],1):
        c=copy.deepcopy(study['case'])
        for l in c['loads']:
            l['p']*=r['factor'];l['q']*=r['factor']
        if k>1:
            event=r['events'][k-2];c['id']+='/'+event['id']
            for g in c['generators']:
                if g['id'] in event['generator_ids']:g['available']=False
            for br in c['network']['branches']:
                if br['id'] in event['branch_ids']:br['available']=False
                br['thermal_limit']*=1. if normal_targeted else 1.1
            for bus in c['network']['buses']:
                bus['v_min']-=0. if normal_targeted else .05;bus['v_max']+=0. if normal_targeted else .05
        assert b['case']==c
        assert all(s['conductance']==0 for s in c['network']['shunts'])
        assert all(all(v==0 for v in s['step_conductances']) for s in c['network']['banks'])
        bs=[v for v in c['network']['branches'] if v['available']];branches_by_state.append(bs)
        assert b['branch_ids']==[v['id'] for v in bs]
        variables(b['pg'],[(F(g['p_min'])-tol,F(g['p_max'])+tol) if g['available'] else(-small,small) for g in c['generators']])
        for key in ('pf','pt'):
            variables(b[key],[(-F(br['thermal_limit'])-tol,F(br['thermal_limit'])+tol) for br in bs])
        loss_bounds=[];busmap={v['id']:v for v in c['network']['buses']}
        for br in bs:
            rate=F(br['thermal_limit'])+tol
            if r.get('terminal_current_loss_upper_bounds'):
                vf,vt=busmap[br['from_bus']],busmap[br['to_bus']]
                tmin=F(taps[br['id']]['lower'])-tol if br['id'] in taps else F(br['tap_ratio'])
                tmax=F(taps[br['id']]['upper'])+tol if br['id'] in taps else F(br['tap_ratio'])
                charge=abs(F(br['charging']))/2
                from_bound=F(br['resistance'])*(tmax*rate/(F(vf['v_min'])-tol)+charge*(F(vf['v_max'])+tol)/tmin)**2
                to_bound=F(br['resistance'])*(rate/(F(vt['v_min'])-tol)+charge*(F(vt['v_max'])+tol))**2
                upper=min(2*rate,from_bound,to_bound)+tol
            else:upper=2*rate+tol
            loss_bounds.append((Q(0),upper))
        variables(b['loss'],loss_bounds)
        if k>1 and not normal_targeted:
            variables(b['dr'],[(-small,F('.01')*F(l['p'])+small) for l in c['loads']])
            variables(b['shed'],[(-small,F('.1')*F(l['p'])+small) for l in c['loads']])
            for i,l in enumerate(c['loads']):
                le({b['dr'][i]:Q(1),b['shed'][i]:Q(1)},F('.1')*F(l['p'])+small,dict(family='combined_relief',state=k,load=l['id']))
            le({i:Q(1) for i in b['shed']},Q(10)/F(c['base_power'])+small,dict(family='shedding_budget',state=k))
        else:
            assert b['dr']==[] and b['shed']==[]
            if k==1: assert b['delta'] is None
        for i,br in enumerate(bs):
            eq({b['loss'][i]:Q(1),b['pf'][i]:Q(-1),b['pt'][i]:Q(-1)},0,dict(family='loss_identity',state=k,branch=br['id']),tol)
        for bus in c['network']['buses']:
            coeff={b['pg'][i]:Q(1) for i,g in enumerate(c['generators']) if g['bus_id']==bus['id']}
            coeff.update({b['pf'][i]:Q(-1) for i,br in enumerate(bs) if br['from_bus']==bus['id']})
            coeff.update({b['pt'][i]:Q(-1) for i,br in enumerate(bs) if br['to_bus']==bus['id']})
            if k>1 and not normal_targeted:
                for key in ('dr','shed'):
                    coeff.update({b[key][i]:Q(1) for i,l in enumerate(c['loads']) if l['bus_id']==bus['id']})
            demand=sum((F(l['p']) for l in c['loads'] if l['bus_id']==bus['id']),Q(0))
            eq(coeff,demand,dict(family='nodal_balance',state=k,bus=bus['id']),tol)
        cap=sum((F(g['p_max']) for g in c['generators'] if g['available']),Q(0))
        assert all(g['p_min']==0 for g in c['generators'])
        assert all(study['participation'][str(g['id'])]==g['p_max'] for g in c['generators'] if g['available'])
        alpha=[F(study['participation'][str(g['id'])])/cap if g['available'] else Q(0) for g in c['generators']]
        assert list(map(F,b['alpha']))==alpha
        if k>1:
            delta_bound=2*cap+1;variables([b['delta']],[(-delta_bound,delta_bound)])
            # A worst-order IEEE summation/division bound includes the native
            # Float64 normalization inside the larger response tolerance.
            u=Q(1,2**53);n=len(c['generators']);gamma=n*u/(1-n*u)
            relative_error=(1+u)/(1-gamma)-1
            assert max(alpha)*relative_error*delta_bound<Q(1,10**9)
            largest=max((g for g in c['generators'] if g['available']),key=lambda g:g['p_max'])
            al=F(largest['p_max'])/cap*(1-u)/(1+gamma)
            assert (F(largest['p_max'])+3*tol)/al<delta_bound
            for i,g in enumerate(c['generators']):
                if g['available']:
                    eq({b['pg'][i]:Q(1),r['blocks'][0]['pg'][i]:Q(-1),b['delta']:-alpha[i]},0,
                       dict(family='preventive_response',state=k,generator=g['id']),rtol)
        buses={v['id']:v for v in c['network']['buses']}
        coefficients=[]
        for br in bs:
            assert br['resistance']>=0
            tau=F(taps[br['id']]['lower'])-tol if br['id'] in taps else F(br['tap_ratio'])
            coefficients.append((F(br['resistance'])*tau*tau/(F(buses[br['from_bus']]['v_max'])+tol)**2,
                                 F(br['resistance'])/(F(buses[br['to_bus']]['v_max'])+tol)**2))
        assert coefficients==[tuple(map(F,a)) for a in b['coefficients']]
    z=r['total_loss'];upper=sum(bounds[i-1][1] for b in r['blocks'] for i in b['loss'])+1
    variables([z],[(Q(0),upper)])
    eq({z:Q(1)}|{i:Q(-1) for b in r['blocks'] for i in b['loss']},0,dict(family='total_loss_identity'))
    for stored in r['rows'][len(rows):]:
        meta=stored['meta'];assert meta['family']=='loss_tangent'
        b=r['blocks'][meta['state']-1];j=b['branch_ids'].index(meta['branch']);side=meta['side'];assert side in (1,2)
        a=F(b['coefficients'][j][side-1]);p0=F(meta['point']);pvar=b['pf' if side==1 else 'pt'][j]
        le({pvar:2*a*p0,b['loss'][j]:Q(-1)},a*p0*p0,meta)
    actual=[({int(i):F(a) for i,a in row['coefficients'].items() if F(a)},F(row['rhs']),row['meta']) for row in r['rows']]
    assert actual==rows
    assert bounds==[tuple(map(F,pair)) for pair in r['variable_bounds']]
    residual=[Q(0)]*len(bounds);rhs=Q(0);families={}
    for index,value in r['multipliers']:
        multiplier=F(value);assert multiplier>=0
        coeff,bound,meta=rows[index-1];rhs+=multiplier*bound
        families[meta['family']]=families.get(meta['family'],0)+1
        for i,a in coeff.items():residual[i-1]+=multiplier*a
    gap=sum(min(a*l,a*u) for a,(l,u) in zip(residual,bounds))-rhs
    if r['strict_gap_exact'] is not None:assert gap==F(r['strict_gap_exact'])
    certified=r['strict_gap_exact'] is not None and gap>0
    assert certified==r['certified_infeasible']
    result=dict(verified=True,certified_infeasible=certified,acceptance_tolerance_robust=certified,
                expanded_acceptance_tolerance_model=True,
                exact_gap=str(gap) if r['strict_gap_exact'] is not None else None,variables=len(bounds),rows=len(rows),
                ray_participating_constraint_families=families,
                result_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),
                limitation='A nonpositive or absent ray is inconclusive. The gap is not an MW deficit.')
    (folder/'independent_audit.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
    return result


def historical_witness_check():
    folder=OUT/'factor-1.0';r=load(folder/'result.json');assert r['factor']==1.
    nominal=load(BASE/'qualification/summary-expanded-madnlp-reserve.json')
    directory=BASE/nominal['selected'];master=load(directory/'result-1.0.json')['data']
    point=[Q(0)]*len(r['variable_bounds']);sources=[]
    for k,b in enumerate(r['blocks']):
        sid='base' if k==0 else r['events'][k-1]['id']
        if sid=='base':result=master
        else:
            p=BASE/f'qualification/expanded-madnlp-reserve/round-1/demand-1.0/{sid}/result.json'
            result=load(p)['data'];sources.append(str(p.relative_to(ROOT)))
        state=result['states'][sid];taps=result['tap_settings'][sid]
        c=b['case'];indices={v['id']:i for i,v in enumerate(c['network']['buses'])}
        voltage=[cmath.rect(v,a) for v,a in zip(state['vm'],state['va'])]
        for i,value in zip(b['pg'],state['pg']):point[i-1]=F(value)
        bs=[br for br in c['network']['branches'] if br['available']]
        for j,br in enumerate(bs):
            vi,vj=voltage[indices[br['from_bus']]],voltage[indices[br['to_bus']]]
            tap=cmath.rect(taps.get(str(br['id']),br['tap_ratio']),br['phase_shift'])
            y=1/complex(br['resistance'],br['reactance']);charge=complex(0,br['charging']/2)
            sf=vi*(((y+charge)/abs(tap)**2*vi-y/tap.conjugate()*vj).conjugate())
            st=vj*(((y+charge)*vj-y/tap*vi).conjugate())
            loss=br['resistance']*abs((vi/tap-vj)*y)**2
            for key,value in (('pf',sf.real),('pt',st.real),('loss',loss)):point[b[key][j]-1]=F(value)
        if k:point[b['delta']-1]=F(result['balancing_power'][sid])
    point[r['total_loss']-1]=sum((point[i-1] for b in r['blocks'] for i in b['loss']),Q(0))
    bound_violation=max([Q(0)]+[max(F(lo)-v,v-F(hi)) for v,(lo,hi) in zip(point,r['variable_bounds'])])
    row_violation=max([Q(0)]+[sum((F(a)*point[int(i)-1] for i,a in row['coefficients'].items()),Q(0))-F(row['rhs']) for row in r['rows']])
    assert bound_violation<=0 and row_violation<=0
    record=dict(verified=True,historical_ac_states=4,variable_bounds=len(point),linear_rows=len(r['rows']),
                terminal_current_loss_ceilings_verified_on_actual_ac_states=True,
                maximum_positive_bound_violation=str(bound_violation),maximum_positive_row_violation=str(row_violation),
                source_result_files=sources,
                scope='Known qualified nominal AC witnesses embed in the new necessary-condition model; no new optimizer call')
    (OUT/'historical_ac_witness_check.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record));return record


if __name__=='__main__':
    import sys
    if sys.argv[1]=='--historical-witness':historical_witness_check()
    else:verify(OUT/f'factor-{sys.argv[1]}')
