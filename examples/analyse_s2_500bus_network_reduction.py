"""Read-only exact zero-injection reduction and full-network reconstruction.

No optimizer is invoked. Original branch IDs, two-ended MVA limits, voltage
bounds and angle bounds are retained as functions of reconstructed voltages.
Requires NumPy; the independent AC check uses only the standard library.
"""
import collections
import copy
import hashlib
import json
from pathlib import Path
import numpy as np
from s2_followup_physics import check_case

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT/'artifacts/s2_scopf/ieee500_native'
OUT = BASE/'network_reduction'
load = lambda p: json.loads(Path(p).read_text())


def partition(study,mode='all'):
    c = study['case']; n = c['network']
    keep = {l['bus_id'] for l in c['loads'] if l['p'] or l['q']}
    keep |= {g['bus_id'] for g in c['generators']}
    keep |= {a['location']['bus_id'] for a in c['attachments']}
    keep |= {b['id'] for b in n['buses'] if b['reference']}
    keep |= {b['bus_id'] for family in ('shunts','banks') for b in n[family]}
    taps = {t['branch_id'] for t in study['tap_controls']}
    keep |= {b[k] for b in n['branches'] if b['id'] in taps for k in ('from_bus','to_bus')}
    ids = [b['id'] for b in n['buses']]
    if mode=='independent-degree3':
        adj={i:set() for i in ids}
        for b in n['branches']:
            if b['available']:adj[b['from_bus']].add(b['to_bus']);adj[b['to_bus']].add(b['from_bus'])
        score=lambda i:sum(k not in adj[j] for j in adj[i] for k in adj[i] if j<k)
        selected=set()
        for i in sorted((i for i in ids if i not in keep and len(adj[i])==3),key=lambda i:(score(i),i)):
            if not adj[i]&selected:selected.add(i)
        keep|=set(ids)-selected
    else:assert mode=='all'
    return [i for i,b in enumerate(ids) if b in keep], [i for i,b in enumerate(ids) if b not in keep]


def admittance(c, taps, banks):
    n=c['network']; ids={b['id']:i for i,b in enumerate(n['buses'])}
    y=np.zeros((len(ids),len(ids)),dtype=complex)
    for b in n['branches']:
        if not b['available']: continue
        i,j=ids[b['from_bus']],ids[b['to_bus']]
        t=taps.get(str(b['id']),b['tap_ratio'])*np.exp(1j*b['phase_shift'])
        z=1/complex(b['resistance'],b['reactance']); ch=.5j*b['charging']
        y[i,i]+=(z+ch)/abs(t)**2; y[i,j]-=z/t.conjugate()
        y[j,i]-=z/t; y[j,j]+=z+ch
    for b in n['shunts']:
        if b['available']:y[ids[b['bus_id']],ids[b['bus_id']]]+=complex(b['conductance'],b['susceptance'])
    for b in n['banks']:
        if not b['available']:continue
        bs=sum(x*s for x,s in zip(b['step_susceptances'],b['state']))
        gs=sum(x*s for x,s in zip(b['step_conductances'],b['state']))
        if str(b['id']) in banks:
            bs=banks[str(b['id'])];gs=b['step_conductances'][0]/b['step_susceptances'][0]*bs
        y[ids[b['bus_id']],ids[b['bus_id']]]+=complex(gs,bs)
    return y


def reconstruct(c,state,taps,banks,kept,eliminated,angles):
    y=admittance(c,taps,banks)
    yee=y[np.ix_(eliminated,eliminated)]
    h=-np.linalg.solve(yee,y[np.ix_(eliminated,kept)])
    reduced=y[np.ix_(kept,kept)]+y[np.ix_(kept,eliminated)]@h
    original=np.array(state['vm'])*np.exp(1j*np.array(state['va']))
    rebuilt=original.copy();rebuilt[eliminated]=h@original[kept]
    rebuilt_state=copy.deepcopy(state)
    rebuilt_state['vm']=np.abs(rebuilt).tolist();rebuilt_state['va']=np.angle(rebuilt).tolist()
    before=check_case(c,state,taps,banks,angles)
    after=check_case(c,rebuilt_state,taps,banks,angles)
    flow_error=max(abs(before['branch_max_terminal_s_pu'][b]-after['branch_max_terminal_s_pu'][b]) for b in before['branch_max_terminal_s_pu'])
    assert all(np.isfinite(h.flatten()))
    return dict(original_full_physics_valid=before['valid'],reconstructed_full_physics_valid=after['valid'],
        original_balance_max_pu=before['power_balance_max_pu'],reconstructed_balance_max_pu=after['power_balance_max_pu'],
        eliminated_voltage_change_max_pu=float(max(abs(rebuilt[eliminated]-original[eliminated]))),
        eliminated_current_residual_max_pu=float(max(abs((y@rebuilt)[eliminated]))),
        retained_current_identity_error_pu=float(max(abs((y@rebuilt)[kept]-reduced@rebuilt[kept]))),
        original_branch_max_terminal_mva_change=flow_error*c['base_power'],
        full_voltage_min_margin_pu=after['voltage_min_margin_pu'],
        full_thermal_min_margin_mva=after['thermal_min_margin_pu']*c['base_power'],
        full_angle_min_margin_rad=after['angle_min_margin_rad'],
        full_exact_droop_max_pu=after['exact_droop_max_pu'],
        eliminated_block_condition_number=float(np.linalg.cond(yee)),
        original_y_nonzeros=int(np.count_nonzero(abs(y)>1e-12)),
        reduced_y_nonzeros=int(np.count_nonzero(abs(reduced)>1e-12)))


def main():
    OUT.mkdir(exist_ok=True)
    study=load(BASE/'pilot_study.json')['data'];c=study['case'];kept,eliminated=partition(study)
    angles=load(ROOT/'artifacts/s1_free_droop/500/angle_limits.json')
    ids=[b['id'] for b in c['network']['buses']]
    degrees=collections.Counter(v for b in c['network']['branches'] if b['available'] for v in (b['from_bus'],b['to_bus']))
    rows=[]
    nominal=load(BASE/'qualification/summary-expanded-madnlp-reserve.json')['selected']
    design=load(BASE/nominal/'optimized-1.0.json')['data']
    for event in ('branch_21','branch_36','branch_562','generator_60'):
        result=load(BASE/f'qualification/expanded-madnlp-reserve/round-1/demand-1.0/{event}/result.json')['data']
        case=copy.deepcopy(design['case']);kind,num=event.split('_')
        family=case['network']['branches'] if kind=='branch' else case['generators']
        next(b for b in family if b['id']==int(num))['available']=False
        r=reconstruct(case,result['states'][event],result['tap_settings'][event],result['shunt_settings'][event],kept,eliminated,angles)
        assert r['original_full_physics_valid'] and r['reconstructed_full_physics_valid']
        rows.append(dict(source='qualified nominal',event=event,factor=1.,**r))
    for relative,stage in (('emergency/zero-shedding-1.1','dr'),
                           ('dispatch-recovery/demand-1.05/zero-shedding','feasibility'),
                           ('dispatch-recovery/demand-1.1/coordinated-last-resort','feasibility')):
        folder=BASE/'emergency_loadability'/relative
        controller=load(folder/f'controller-{stage}.json')['data'];contract=load(folder/'contract.json')
        point=load(folder/f'point-{stage}.json')
        for state in point['states']:
            case=copy.deepcopy(controller['case']);factor=state['factor'];event=state['id']
            post=event!='base'
            if post:
                kind,num=event.split('_');family=case['network']['branches'] if kind=='branch' else case['generators']
                next(b for b in family if b['id']==int(num))['available']=False
            for l in case['loads']:
                l['p']*=factor;l['q']*=factor
                if l['p']>0:
                    served=1-(state['dr'][str(l['id'])]+state['shed'][str(l['id'])])/l['p']
                    l['p']*=served;l['q']*=served
            if post and contract['emergency']:
                for b in case['network']['buses']:b['v_min']-=.05;b['v_max']+=.05
                for b in case['network']['branches']:b['thermal_limit']*=contract['thermal_multiplier']
            r=reconstruct(case,state['state'],state['taps'],state['banks'],kept,eliminated,angles)
            if point['record']['native_success']:
                assert r['original_full_physics_valid'] and r['reconstructed_full_physics_valid']
            rows.append(dict(source=relative,event=event,factor=factor,native_success=point['record']['native_success'],**r))
    summary=dict(scope='Optimizer-free saved-point reduction/reconstruction precheck; numerical runs reported separately',
        original_buses=len(ids),retained_buses=len(kept),eliminated_buses=len(eliminated),
        eliminated_bus_ids=[ids[i] for i in eliminated],eliminated_degree_histogram=dict(collections.Counter(degrees[ids[i]] for i in eliminated)),
        all_generators_loads_controls_tap_endpoints_shunts_and_reference_retained=True,
        reduction='V_E = -Y_EE^-1 Y_ER V_R; zero-injection buses only; recompute for each outage topology',
        constraint_policy='Retain every original in-service branch terminal MVA inequality, all original bus voltage and branch angle bounds on reconstructed full voltages. No generic equivalent-line rating substitution.',
        reconstructed_points=rows,solver_recovery_demonstrated=False,
        no_scopf_optimizer_calls=True,source_adapter_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    (OUT/'precheck.json').write_text(json.dumps(summary,indent=2)+'\n')
    valid=[r for r in rows if r['original_full_physics_valid']]
    lines=['# 500-bus electrical network-reduction precheck','',
        '**This precheck invokes no optimizer.** It is a read-only algebraic reduction/reconstruction test on saved accepted and rejected points. Subsequent numerical tests are reported separately in REPORT.md.','',
        'The previous reduced-Q formulation removes droop reactive variables. Retaining one component after an islanding outage is a separate operation. Neither is electrical reduction of the connected 500-bus SCOPF.','',
        '## Exact candidate reduction','',
        f'- Retained buses: {len(kept)} / {len(ids)}; eliminated zero-injection buses: {len(eliminated)}.',
        '- Retain every generator (including offline units), nonzero load, droop attachment, shunt/bank, reference bus and both endpoints of each selected tap.',
        '- Use V_E = −Y_EE⁻¹Y_ER V_R and Y_red = Y_RR − Y_RE Y_EE⁻¹Y_ER. Positive lower voltage bounds make zero complex power injection equivalent to zero current injection at these eliminated buses.',
        '- Tap and bank endpoints are retained, so the eliminated block and reconstruction map do not depend on the free taps or shunts. A different outage topology needs its own map; never discard an original outage because its bus or line is eliminated.',
        '- This eliminates 246 real voltage coordinates per state. It does not eliminate equipment-rating, voltage or angle inequalities.','',
        '## Rating and full-network acceptance contract','',
        'Keep **every original in-service branch ID and both terminal apparent-power limits** as constraints evaluated on reconstructed original voltages, with original resistance, charging, phase shift and tap. Keep all original bus-voltage bounds, branch-angle limits and losses, including at eliminated buses. Use Rate A in base states and the confirmed 110% Rate A cap in N−1 states. Do not assign a single generic MVA rating to an equivalent branch and drop the original constraints.','',
        'After any future reduced optimization, reconstruct all 500 voltages, replay the untouched original network, and independently check AC P/Q balance, exact droop, Pg/Qg, both-end ratings, voltage/angle limits, equipment bounds, preventive response coupling and DR/shedding budgets. Acceptance still requires native convergence and every original-network gate. An optional subsequent full-model solve is a separate polishing/recovery run.','',
        '## Saved-point reconstruction results','',
        f'{len(rows)} saved states were tested. All {len(valid)} previously AC-valid states remain AC-valid after reconstruction. All six rejected 110% expanded-master iterates remain invalid; reconstruction alone does not recover them. The three accepted nominal outage checks include line 36, transformer 562 and G60.',
        f'Maximum complex-voltage reconstruction change among valid states: {max(r["eliminated_voltage_change_max_pu"] for r in valid):.6g} pu. Maximum original-branch terminal-MVA change: {max(r["original_branch_max_terminal_mva_change"] for r in valid):.6g} MVA.',
        f'Maximum retained-current identity residual: {max(r["retained_current_identity_error_pu"] for r in rows):.6g} pu. Maximum eliminated-current residual: {max(r["eliminated_current_residual_max_pu"] for r in rows):.6g} pu.','',
        'The base admittance matrix has 1,660 nonzeros before elimination and 2,781 after it. This fill-in means fewer voltage variables do not guarantee faster factorization. The eliminated block has condition number about 3.20 in these scenarios; no solver speedup has been measured.','',
        '## Scope and next numerical test','',
        'Reduction may help the time-limited connected-outage and coupled multi-demand solves, but that is untested. An exact reduction retaining original constraints cannot remove the normal-limit infeasibility certificate or supply isolated loads without generation.',
        'The first optimization comparison should use matched starts, controls, physical policies and native budgets on the 110% expanded master containing line 36, transformer 562, line 219, G14 and G60. Compare reduced native convergence, full-network reconstruction, wall time and full-model polishing separately. Only after acceptance should the shared multi-demand target and exhaustive outage coverage be retried.',
        'The numerical campaign configuration is recorded separately in protocol.json; this read-only precheck does not start SCOPF runs.','',
        'Method background: [Line Limit Preserving Power System Equivalent](https://documents.pserc.wisc.edu/documents/publications/papers/2013_general_publications/Line-Limit-Preserving-Power-System-Equivalent_Feb-2013.pdf). Its equivalent-line rating approach is background; the proposed AC contract here retains the original constraints through voltage reconstruction.','']
    (OUT/'PRECHECK.md').write_text('\n'.join(lines))
    print(json.dumps({k:v for k,v in summary.items() if k not in ('reconstructed_points','eliminated_bus_ids')},indent=2))


if __name__=='__main__':main()
