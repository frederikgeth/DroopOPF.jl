"""Independently replay M10.2 saved/fresh base-case states and report comparisons.
Run with Python + Matplotlib: report_m10_2_matched.py OUTPUT_DIRECTORY
"""
import csv
import hashlib
import json
import math
from pathlib import Path
import sys
from collections import defaultdict

ROOT=Path(__file__).resolve().parents[1]

def scalar_flows(br,vm,va,idx):
    if not br['available']: return 0j,0j
    i,j=idx[br['from_bus']],idx[br['to_bus']]
    y=1/complex(br['resistance'],br['reactance']);g,b=y.real,y.imag
    v,w,t=vm[i],vm[j],br['tap_ratio'];d=va[i]-va[j]-br['phase_shift'];bc=br['charging']/2
    return (complex(g*v*v/t**2-v*w/t*(g*math.cos(d)+b*math.sin(d)),
                    -(b+bc)*v*v/t**2+v*w/t*(b*math.cos(d)-g*math.sin(d))),
            complex(g*w*w-v*w/t*(g*math.cos(-d)+b*math.sin(-d)),
                    -(b+bc)*w*w+v*w/t*(b*math.cos(-d)-g*math.sin(-d))))

def replay(case,result,assignments=None):
    s=result.get('state')
    if s is None: return dict(valid=False,reason='missing state')
    net=case['network']; buses=net['buses'];gens=case['generators'];idx={b['id']:i for i,b in enumerate(buses)}
    assert len(s['vm'])==len(s['va'])==len(buses) and len(s['pg'])==len(s['qg'])==len(gens)
    if not all(math.isfinite(x) for key in ('vm','va','pg','qg') for x in s[key]):
        return dict(valid=False,reason='nonfinite state')
    vm,va=s['vm'],s['va'];inj=[0j]*len(buses); margins=[];loss=0
    for br in net['branches']:
        f,t=scalar_flows(br,vm,va,idx);inj[idx[br['from_bus']]]+=f;inj[idx[br['to_bus']]]+=t
        loss+=(f+t).real
        if br['available']: margins.append(br['thermal_limit']-max(abs(f),abs(t)))
    shunt_power=0j
    for sh in net['shunts']:
        if sh['available']:
            q=complex(sh['conductance'],-sh['susceptance'])*vm[idx[sh['bus_id']]]**2
            inj[idx[sh['bus_id']]]+=q;shunt_power+=q
    for bank in net['banks']:
        if bank['available']:
            q=sum(n*complex(g,-b) for n,g,b in zip(bank['state'],bank['step_conductances'],bank['step_susceptances']))*vm[idx[bank['bus_id']]]**2
            inj[idx[bank['bus_id']]]+=q;shunt_power+=q
    supplied=[0j]*len(buses)
    for g,p,q in zip(gens,s['pg'],s['qg']): supplied[idx[g['bus_id']]]+=complex(p,q)
    for load in case['loads']: supplied[idx[load['bus_id']]]-=complex(load['p'],load['q'])
    power=max(max(abs((x-y).real),abs((x-y).imag)) for x,y in zip(inj,supplied))
    voltage=min(min(v-b['v_min'],b['v_max']-v) for v,b in zip(vm,buses))
    p_margin=min(min(p-g['p_min'],g['p_max']-p) for p,g in zip(s['pg'],gens))
    q_margin=min(min(q-g['q_min'],g['q_max']-q) for q,g in zip(s['qg'],gens))
    control_error=0;avr_error=0;regimes=[]
    if assignments is None:
        assignments=[dict(generator_id=a['generator_id'],location=a['location'],mode=dict(type='VoltVarDroop',**case['controls'][a['control_id']-1])) for a in case['attachments']]
    for a in assignments:
        gi=next(i for i,g in enumerate(gens) if g['id']==a['generator_id']);g=gens[gi];m=a['mode'];q=s['qg'][gi]
        if m['type']=='FreeQ': continue
        if m['type']=='FixedQ': control_error=max(control_error,abs(q-m['q_schedule'])); continue
        v=vm[idx[a['location']['bus_id']]]
        if m['type']=='VoltVarDroop':
            schedule=m['schedule'];q0=m['q_at_deadband']
            expected=q0+(schedule['v_db_low']-v)/m['slope'] if v<schedule['v_db_low'] else q0-(v-schedule['v_db_high'])/m['slope'] if v>schedule['v_db_high'] else q0
            expected=min(m['capability']['q_max'],max(m['capability']['q_min'],expected))
            control_error=max(control_error,abs(q-expected))
        elif m['type']=='AVR':
            error=v-m['voltage_setpoint'];avr_error=max(avr_error,abs(error))
            if abs(error)<=1e-5: regimes.append('regulating')
            elif error>0 and abs(q-g['q_min'])<=1e-6: regimes.append('q_min')
            elif error<0 and abs(q-g['q_max'])<=1e-6: regimes.append('q_max')
            else: regimes.append('invalid');control_error=max(control_error,abs(error))
        else: raise AssertionError(m['type'])
    objective=sum((p-g['initial_p'])**2+0.001*(q-g['initial_q'])**2 for p,q,g in zip(s['pg'],s['qg'],gens))
    objective_error=abs(objective-result['objective']) if result.get('objective') is not None else math.inf
    valid=power<=1e-6 and control_error<=1e-5 and min(voltage,p_margin,q_margin,min(margins))>=-1e-6 and objective_error<=1e-8
    # FixedQ is subject to the stricter AC-power tolerance in library validation.
    for a in assignments:
        if a['mode']['type']=='FixedQ':
            gi=next(i for i,g in enumerate(gens) if g['id']==a['generator_id'])
            valid &= abs(s['qg'][gi]-a['mode']['q_schedule'])<=1e-6
    return dict(valid=bool(valid),power_residual_pu=power,control_residual_pu=control_error,
        voltage_margin_pu=voltage,p_margin_pu=p_margin,q_reserve_pu=q_margin,thermal_margin_pu=min(margins),
        objective=objective,objective_error=objective_error,branch_loss_pu=loss,shunt_consumption_pu=shunt_power.real,
        q_effort_pu=sum(abs(q) for q in s['qg']),avr_target_error_pu=avr_error,avr_regimes=regimes,
        q_limit_exposure=sum(min(q-g['q_min'],g['q_max']-q)<=1e-6 for q,g in zip(s['qg'],gens)))

def report(out):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    protocol=json.loads((out/'protocol.json').read_text())
    for family in ('source_hashes','code_environment_hashes'):
        for path,expected in protocol[family].items():
            assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==expected,('changed input',path)
    sources=json.loads((out/'nominal_replay.json').read_text());assert len(sources)==16
    selected={};nominal=[]
    for r in sources:
        independent=replay(r['physical_case'],r['result'])
        assert independent['valid']==r['validation']['physical']['valid']==r['valid'],('source disagreement',r['tag'],r['run'])
        r['independent']=independent;nominal.append(r)
    for tag in protocol['tags']:
        rs=[r for r in nominal if r['tag']==tag and r['valid']]
        assert len(rs)==2
        selected[tag]=min(rs,key=lambda r:r['result']['objective'])
        c=selected[tag]['physical_case']
        br=next(b for b in c['network']['branches'] if b['id']==11)
        assert 0.95-1e-6<=br['tap_ratio']<=1.05+1e-6
        assert tag[0]=='1' or abs(br['tap_ratio']-1.02)<1e-10
        assert tag[2]=='1' or abs(c['controls'][1]['slope']-0.075)<1e-10
    attempts=json.loads((out/'attempts.json').read_text());assert len(attempts)==110
    groups=defaultdict(list);audits=[]
    for r in attempts:
        assert json.loads((out/r['attempt_file']).read_text())==r
        study=json.loads((out/r['case_file']).read_text())['data'];c=study['case'];assign=study['reactive_assignments']
        baseline=selected[r['tag']]['physical_case']
        assert c['network']==baseline['network'] and c['controls']==baseline['controls'] and c['generators']==baseline['generators'],('settings drift',r['group'])
        assert not study['contingencies'] and not study['tap_controls'] and not study['shunt_controls']
        assert len(c['loads'])==len(baseline['loads'])
        for load,old in zip(c['loads'],baseline['loads']):
            assert abs(load['p']-old['p']*r['factor'])<1e-12 and abs(load['q']-old['q']*r['factor'])<1e-12
        if r['mode']=='droop': assert assign is None
        else:
            seed=selected['111']['result']['state'];idx={b['id']:i for i,b in enumerate(c['network']['buses'])}
            for i,a in enumerate(assign):
                assert a['generator_id']==c['generators'][i]['id']
                if r['mode']=='fixed_q': assert a['mode']==dict(type='FixedQ',q_schedule=seed['qg'][i])
                if r['mode']=='free_q': assert a['mode']==dict(type='FreeQ')
                if r['mode']=='avr':
                    bus=c['generators'][i]['bus_id'];assert a['mode']==dict(type='AVR',voltage_setpoint=seed['vm'][idx[bus]])
                    assert a['location']['bus_id']==bus
        a=replay(c,r.get('result',{}),assign)
        native=r.get('result',{}).get('termination_status') in ('LOCALLY_SOLVED','ALMOST_LOCALLY_SOLVED','OPTIMAL')
        accepted=native and a['valid']
        assert accepted==r['valid'],('acceptance disagreement',r['group'],r['start'],a,r.get('validation'))
        if 'power_residual_pu' in a:
            v=r['validation']
            for k,field in [('power_residual_pu','power_balance_max'),('thermal_margin_pu','branch_thermal_min_margin'),('q_reserve_pu','generator_q_min_margin')]:
                if k=='q_reserve_pu': value=min(v['generator_q_min_margin'],v['generator_q_max_margin'])
                else: value=v[field]
                assert abs(a[k]-value)<1e-9,(k,a[k],value)
        r['independent']=a;r['accepted']=accepted;groups[r['group']].append(r)
        audits.append(dict(group=r['group'],start=r['start'],accepted=accepted,**a))
    expected={(tag,'droop',f) for tag in protocol['tags'] for f in protocol['factors']}
    expected.update({('111',mode,f) for mode in ('fixed_q','free_q','avr') for f in protocol['factors']})
    assert {(rs[0]['tag'],rs[0]['mode'],rs[0]['factor']) for rs in groups.values()}==expected and len(groups)==55
    summaries=[]
    for key,rs in sorted(groups.items()):
        assert {r['start'] for r in rs}=={1,2}
        good=[r for r in rs if r['accepted']]
        best=min(good,key=lambda r:r['independent']['objective']) if good else None
        summaries.append(dict(group=key,tag=rs[0]['tag'],mode=rs[0]['mode'],factor=rs[0]['factor'],
            attempts=len(rs),accepted=len(good),selected_start=best['start'] if best else None,
            metrics=best['independent'] if best else None,
            objective_spread=max(r['independent']['objective'] for r in good)-min(r['independent']['objective'] for r in good) if good else None))
    benefits=[]
    for t in (0,1):
        for s in (0,1):
            fixed=selected[f'{t}{s}0']['independent']['objective'];free=selected[f'{t}{s}1']['independent']['objective']
            assert free<=fixed+1e-8
            benefits.append(dict(equipment=f'{t}{s}',fixed_objective=fixed,free_objective=free,improvement=fixed-free))
    failures=[dict(group=r['group'],start=r['start'],status=r.get('result',{}).get('termination_status'),
                   error=r.get('error'),validation=r.get('validation'),independent=r['independent']) for r in attempts if not r['accepted']]
    status='PASS' if all(s['accepted'] for s in summaries) else 'INCOMPLETE'
    results=dict(status=status,groups=len(groups),groups_accepted=sum(s['accepted']>0 for s in summaries),
        attempts=len(attempts),accepted_attempts=sum(r['accepted'] for r in attempts),nominal_saved_replays=len(nominal),
        independent_replay_discrepancies=0,heldout_groups=sum(s['factor']!=1 for s in summaries),
        matched_droop_benefits=benefits,failures=failures,summaries=summaries,
        scope='synthetic base-case; installed equipment frozen for operating-point evaluations; no SCOPF')
    (out/'RESULTS.json').write_text(json.dumps(results,indent=2)+'\n')
    (out/'independent_replay.json').write_text(json.dumps(dict(nominal=[dict(tag=r['tag'],run=r['run'],**r['independent']) for r in nominal],attempts=audits),indent=2)+'\n')
    fields=['group','tag','mode','factor','accepted','selected_start','objective_spread','objective','voltage_margin_pu','thermal_margin_pu','q_reserve_pu','q_effort_pu','branch_loss_pu','shunt_consumption_pu','control_residual_pu','avr_target_error_pu','q_limit_exposure']
    with (out/'comparison.csv').open('w') as f:
        w=csv.DictWriter(f,fields,extrasaction='ignore');w.writeheader()
        for s in summaries:w.writerow({**s,**(s['metrics'] or {})})
    fig,axes=plt.subplots(1,2,figsize=(10.5,4))
    xs=range(4);axes[0].bar([x-.18 for x in xs],[b['fixed_objective'] for b in benefits],.36,label='fixed droop')
    axes[0].bar([x+.18 for x in xs],[b['free_objective'] for b in benefits],.36,label='free droop')
    axes[0].set_xticks(list(xs),[b['equipment'] for b in benefits]);axes[0].set(xlabel='Tap / shunt freedom at nominal design',ylabel='Dispatch-deviation objective',title='Matched nominal design comparison');axes[0].legend()
    for mode in ('droop','fixed_q','free_q','avr'):
        ss=sorted([s for s in summaries if s['tag']=='111' and s['mode']==mode and s['metrics']],key=lambda s:s['factor'])
        axes[1].plot([s['factor'] for s in ss],[s['metrics']['objective'] for s in ss],marker='o',label=mode)
    axes[1].set(xlabel='Demand factor',ylabel='Dispatch-deviation objective',title='Control modes with identical frozen equipment');axes[1].legend()
    fig.tight_layout();fig.savefig(out/'objectives.png',dpi=160);plt.close(fig)
    fig,axes=plt.subplots(1,3,figsize=(12,3.8))
    for tag in protocol['tags']:
        ss=sorted([s for s in summaries if s['tag']==tag and s['mode']=='droop' and s['metrics']],key=lambda s:s['factor'])
        for ax,metric in zip(axes,('voltage_margin_pu','thermal_margin_pu','q_reserve_pu')):
            ax.plot([s['factor'] for s in ss],[s['metrics'][metric] for s in ss],marker='.',label=tag)
    for ax,title in zip(axes,('Minimum voltage margin (pu)','Minimum thermal margin (pu)','Minimum Q reserve (pu)')):
        ax.set(xlabel='Demand factor',ylabel=title);ax.grid(alpha=.2)
    axes[2].legend(ncol=2,fontsize=7);fig.suptitle('Frozen nominal designs: held-out demand margins');fig.tight_layout();fig.savefig(out/'margins.png',dpi=160);plt.close(fig)
    lines=['# M10.2 matched equipment and control comparisons','',f'Acceptance: **{status}**. {results["groups_accepted"]}/55 groups accepted, {results["accepted_attempts"]}/110 fresh base-case OPF attempts accepted. All 16 historical nominal states passed independent replay; zero acceptance discrepancies. No SCOPF solve was run.','',
        '## Protocol and interpretation','',
        'The source is the synthetic three-bus M7.3 fixture. Its nominal design factorial uses tag digits tap/shunt/droop, 1 free and 0 fixed. All eight combinations use the same dispatch-deviation objective with zero design penalty. Loss is a separately reported metric, not the objective. Both historical starts are retained; the lowest-objective replay-valid nominal design is selected per tag.','',
        'Fresh demand factors 0.95, 0.975, 1.025 and 1.05 were declared in protocol.json before solving, alongside nominal re-evaluation at 1.0. Both P and Q loads scale. Every nominal tap, bank and droop setting stays frozen. Each group uses the two historical nominal AC states as starts, with no held-out target tuning or continuation. The original fixture was designed at nominal demand only; these are finite small-fixture held-out points, not continuous-range qualification.','',
        'For tag 111, generator-local droop, FixedQ, FreeQ and AVR use identical frozen equipment, objective, loads, limits and starts. FixedQ schedules and AVR voltage targets are calibrated once from the selected nominal droop state. FreeQ is unrestricted reactive dispatch within the same generator bounds; its extra freedom is part of that explicitly different policy. It is not evidence that an installed automatic controller can realize the optimized FreeQ response. Transformer AVR and dynamic response remain excluded.','',
        'The frozen design grid is not a nested optimization comparison at held-out demands: separately selected nominal designs can exchange their operating-objective ranking. Only the original matched nominal design comparison isolates droop-design freedom at fixed equipment freedom.','',
        '## Matched nominal droop benefit','',
        '| Tap/shunt freedom | Fixed droop objective | Free droop objective | Improvement |','|---|---:|---:|---:|']
    for b in benefits:lines.append(f'| {b["equipment"]} | {b["fixed_objective"]:.10g} | {b["free_objective"]:.10g} | {b["improvement"]:.8g} |')
    lines+=['','![Objectives](objectives.png)','','## Held-out margins and attempts','','| Tag | Accepted droop groups | Worst voltage margin pu | Worst thermal margin pu | Worst Q reserve pu |','|---|---:|---:|---:|---:|']
    for tag in protocol['tags']:
        ss=[s for s in summaries if s['tag']==tag and s['mode']=='droop'];good=[s['metrics'] for s in ss if s['metrics']]
        vals=[min(m[k] for m in good) if good else math.nan for k in ('voltage_margin_pu','thermal_margin_pu','q_reserve_pu')]
        lines.append(f'| {tag} | {sum(s["accepted"]>0 for s in ss)}/5 | {vals[0]:.6g} | {vals[1]:.6g} | {vals[2]:.6g} |')
    lines+=['','![Margins](margins.png)','','## Control mode outcomes','','| Mode | Accepted groups | Maximum control residual pu | Maximum AVR target error pu | Q-limit exposures in selected states |','|---|---:|---:|---:|---:|']
    for mode in ('droop','fixed_q','free_q','avr'):
        ss=[s for s in summaries if s['tag']=='111' and s['mode']==mode];ms=[s['metrics'] for s in ss if s['metrics']]
        lines.append(f'| {mode} | {sum(s["accepted"]>0 for s in ss)}/5 | {max(m["control_residual_pu"] for m in ms):.3g} | '+(f'{max(m["avr_target_error_pu"] for m in ms):.3g}' if mode=='avr' else 'N/A')+f' | {sum(m["q_limit_exposure"] for m in ms)} |')
    lines+=['','## Failures and validation','','All attempts are retained, including native failures and physically rejected states. '+f'This run contains {len(failures)} rejected attempts; their statuses and residuals are in RESULTS.json and per-attempt JSON. No failed run is an infeasibility certificate.','',
        'Independent Python replay uses scalar terminal equations and explicit shunt/bank summation, recomputes AC balance, exact droop or assigned reactive policy, voltage/thermal/P/Q margins, the objective and AVR saturation regimes. It also checks complete group/start coverage, installed-setting equality, frozen mode targets and source/code/environment hashes. Acceptance requires native success and independent physical validity, with AC 1e-6 pu, control 1e-5 pu (FixedQ 1e-6), limits 1e-6 pu and objective agreement 1e-8. No tolerances were loosened.','',
        'protocol.json predates solving; cases/ and attempts/ retain complete numerical inputs and outputs. comparison.csv contains objective spread, loss, shunt consumption, reactive effort/reserve, exact-control residual, settings provenance and operating margins. Nominal parameter spreads remain in the source M7.3 evidence. No legal-position recovery was attempted; all selected fractional equipment values remain continuous relaxations. Timing is not presented as a performance benchmark.','',
        '## Reproduction','','Use a fresh output directory because the runner refuses to overwrite a protocol:','','```sh','julia --project=. examples/m10_2_matched.jl artifacts/m10_2_matched','python3 examples/report_m10_2_matched.py artifacts/m10_2_matched','```','','The report requires Matplotlib. This completes M10.2 only for the declared synthetic base-case comparison scope when status is PASS. Public-system, contingency and broader AVR comparisons remain separate qualification work. S2 is unchanged; M10.3 overall reproducibility/regression closeout remains open.']
    (out/'REPORT.md').write_text('\n'.join(lines)+'\n')
    print(json.dumps({k:v for k,v in results.items() if k not in ('summaries','failures','matched_droop_benefits')}))
    if status!='PASS':raise SystemExit('Incomplete M10.2; inspect retained failures')

if __name__=='__main__':report(Path(sys.argv[1]).resolve())
