"""Report native free-droop trials, exact-policy audits and accepted curves."""
import csv
import copy
import hashlib
import json
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from s2_followup_physics import check_case

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'artifacts/s2_scopf/ieee500_native'
OUT=BASE/'free_droop_continuation'
FIG=ROOT/'docs/src/assets/s2_500bus/free_droop_continuation'
HEADING='## Free-droop continuation with exact active response'
load=lambda p:json.loads(Path(p).read_text())
save=lambda p,d:Path(p).write_text(json.dumps(d,indent=2)+'\n')


def engineering_figures(study,point,figures):
    source=study['case'];scale=source['base_power'];control_rows=[];generation_rows=[];voltage_rows=[];branch_rows=[]
    limits={g['id']:{k:g[k] for k in ('p_min','p_max','q_min','q_max')} for g in source['generators']}
    for a in source['attachments']:
        c=source['controls'][a['control_id']-1]['capability'];v=limits[a['generator_id']]
        for k in ('p_min','q_min'):v[k]=max(v[k],c[k])
        for k in ('p_max','q_max'):v[k]=min(v[k],c[k])
    angles=load(ROOT/'artifacts/s1_free_droop/500/angle_limits.json')
    for factor in sorted({s['factor'] for s in point['states']}):
        states=[s for s in point['states'] if s['factor']==factor]
        fig,axs=plt.subplots(2,2,figsize=(14,9),layout='constrained')
        gens=source['generators'];gids=[g['id'] for g in gens]
        axs[0,0].plot(gids,[limits[g['id']]['p_max']*scale if g['available'] else 0 for g in gens],':',color='gray',label='Equipment/control P bounds')
        axs[0,0].plot(gids,[limits[g['id']]['p_min']*scale if g['available'] else 0 for g in gens],':',color='gray')
        for key in ('q_min','q_max'):axs[0,1].plot(gids,[limits[g['id']][key]*scale if g['available'] else 0 for g in gens],':',color='gray',label='Equipment/control Q bounds' if key=='q_min' else None)
        branches=[b for b in source['network']['branches'] if b['available']]
        for row in states:
            case=copy.deepcopy(source);post=row['id']!='base'
            for l in case['loads']:
                l['p']*=factor;l['q']*=factor
                fraction=(row['dr'][str(l['id'])]+row['shed'][str(l['id'])])/l['p'] if l['p']>0 else 0.
                l['p']*=1-fraction;l['q']*=1-fraction
            if post:
                kind,number=row['id'].split('_');number=int(number)
                family=case['generators'] if kind=='generator' else case['network']['branches']
                next(v for v in family if v['id']==number)['available']=False
                for b in case['network']['buses']:b['v_min']-=.05;b['v_max']+=.05
                for b in case['network']['branches']:b['thermal_limit']*=1.1
            ck=check_case(case,row['state'],row['taps'],row['banks'],angles)
            assert ck['valid']
            line=axs[0,0].plot(gids,np.array(row['state']['pg'])*scale,'.-',ms=2,lw=.7,label=row['id'])[0]
            color=line.get_color()
            axs[0,1].plot(gids,np.array(row['state']['qg'])*scale,'.-',ms=2,lw=.7,color=color)
            axs[1,0].plot([b['id'] for b in case['network']['buses']],row['state']['vm'],lw=.7,color=color)
            flow=ck['branch_max_terminal_s_pu']
            axs[1,1].plot([b['id'] for b in branches],[flow.get(str(b['id']),np.nan)/b['thermal_limit'] for b in branches],lw=.7,color=color)
            for i,g in enumerate(case['generators']):
                bounds={f"{k}_{'mw' if k.startswith('p') else 'mvar'}":(limits[g['id']][k]*scale if g['available'] else 0.) for k in ('p_min','p_max','q_min','q_max')}
                generation_rows.append(dict(factor=factor,outage=row['id'],generator=g['id'],available=g['available'],
                    p_mw=row['state']['pg'][i]*scale,q_mvar=row['state']['qg'][i]*scale,**bounds))
            for i,b in enumerate(case['network']['buses']):
                voltage_rows.append(dict(factor=factor,outage=row['id'],bus=b['id'],vm_pu=row['state']['vm'][i],lower=b['v_min'],upper=b['v_max']))
            for b in branches:
                available=str(b['id']) in flow
                branch_rows.append(dict(factor=factor,outage=row['id'],branch=b['id'],available=available,
                    max_terminal_mva=flow[str(b['id'])]*scale if available else None,
                    rate_a_mva=b['thermal_limit']*scale,applicable_cap_mva=b['thermal_limit']*scale*(1.1 if post else 1.) if available else None))
            for kind,key,id_key,controls in [('tap','taps','branch_id',study['tap_controls']),('shunt','banks','bank_id',study['shunt_controls'])]:
                for c in controls:
                    control_rows.append(dict(factor=factor,outage=row['id'],kind=kind,id=c[id_key],
                        available=str(c[id_key]) in row[key],value=row[key].get(str(c[id_key])),lower=c['lower'],upper=c['upper']))
        axs[0,0].set(xlabel='Generator ID',ylabel='Active generation (MW)');axs[0,0].legend(fontsize=7,ncol=2)
        axs[0,1].set(xlabel='Generator ID',ylabel='Reactive generation (MVAr)');axs[0,1].legend(fontsize=7)
        for v in (.9,1.1):axs[1,0].axhline(v,color='gray',ls=':')
        for v in (.85,1.15):axs[1,0].axhline(v,color='black',ls=':')
        axs[1,0].set(xlabel='Original bus ID',ylabel='Voltage (pu)',title='Base bounds 0.9–1.1; outage caps 0.85–1.15')
        axs[1,1].axhline(1,color='gray',ls=':',label='Normal cap')
        axs[1,1].axhline(1.1,color='black',ls=':',label='Outage study cap')
        axs[1,1].set(xlabel='Original branch/transformer ID',ylabel='Largest terminal S / original Rate A')
        axs[1,1].legend(fontsize=8)
        for ax in axs.flat:ax.grid(alpha=.15)
        fig.suptitle(f'{100*factor:g}% accepted master: original 500-bus values; outaged equipment fixed unavailable')
        name=f'operating-point-{100*factor:g}'.replace('.','-');figures.append(name)
        for ext in ('png','pdf'):fig.savefig(FIG/f'{name}.{ext}',dpi=180)
        plt.close(fig)

        fig,axes=plt.subplots(2,1,figsize=(15,8),layout='constrained')
        taps=sorted(study['tap_controls'],key=lambda c:c['branch_id']);banks=sorted(study['shunt_controls'],key=lambda c:c['bank_id'])
        tv=np.array([[s['taps'].get(str(c['branch_id']),np.nan) for c in taps] for s in states])
        cmap=plt.get_cmap('coolwarm').copy();cmap.set_bad('lightgray')
        im=axes[0].imshow(tv,aspect='auto',vmin=.95,vmax=1.05,cmap=cmap)
        fig.colorbar(im,ax=axes[0],label='Transformer tap ratio')
        stride=max(1,len(taps)//18);indices=list(range(0,len(taps),stride))
        axes[0].set_xticks(indices,[taps[i]['branch_id'] for i in indices]);axes[0].set_xlabel('Original transformer ID (all 131 columns retained; gray = unavailable)')
        bv=np.array([[s['banks'].get(str(c['bank_id']),np.nan) for c in banks] for s in states])
        util=np.array([[(v-c['lower'])/(c['upper']-c['lower']) for v,c in zip(row,banks)] for row in bv])
        im=axes[1].imshow(util,aspect='auto',vmin=0,vmax=1,cmap='viridis')
        fig.colorbar(im,ax=axes[1],label='Fraction of permitted shunt interval')
        axes[1].set_xticks(range(len(banks)),[f"B{c['bank_id']}\n[{c['lower']:g}, {c['upper']:g}]" for c in banks])
        for i in range(len(states)):
            for j in range(len(banks)):axes[1].text(j,i,f'{bv[i,j]:.3f}',ha='center',va='center',fontsize=7,color='white' if util[i,j]<.5 else 'black')
        for ax in axes:ax.set_yticks(range(len(states)),[s['id'] for s in states])
        axes[1].set_xlabel('Continuous susceptance (pu); individual bounds shown below bank ID')
        fig.suptitle(f'{100*factor:g}% accepted master: corrective taps and continuous shunts; no movement budget')
        name=f'equipment-{100*factor:g}'.replace('.','-');figures.append(name)
        for ext in ('png','pdf'):fig.savefig(FIG/f'{name}.{ext}',dpi=180)
        plt.close(fig)
    for name,rows in [('equipment',control_rows),('generation',generation_rows),('voltage',voltage_rows),('branch',branch_rows)]:
        with (OUT/f'selected-{name}-values.csv').open('w',newline='') as f:
            w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)


def balancing_margins(study,point):
    case=study['case'];gens=case['generators'];bounds={g['id']:[g['p_min'],g['p_max']] for g in gens}
    for a in case['attachments']:
        d=case['controls'][a['control_id']-1]['capability'];v=bounds[a['generator_id']]
        v[0]=max(v[0],d['p_min']);v[1]=min(v[1],d['p_max'])
    bases={s['factor']:s for s in point['states'] if s['id']=='base'}
    rows=[]
    for s in point['states']:
        if s['id']=='base':continue
        lost=int(s['id'].split('_')[1]) if s['id'].startswith('generator_') else None
        available=[(i,g) for i,g in enumerate(gens) if g['available'] and g['id']!=lost]
        total=sum(study['participation'][str(g['id'])] for _,g in available)
        b=bases[s['factor']]['state']['pg'];candidates=[]
        for i,g in available:
            alpha=study['participation'][str(g['id'])]/total
            if alpha>0:candidates.append(((bounds[g['id']][1]-b[i])/alpha,g['id']))
        upper,gid=min(candidates);scale=case['base_power']
        rows.append(dict(factor=s['factor'],outage=s['id'],delta_mw=s['delta']*scale,
            delta_upper_mw=upper*scale,remaining_delta_upper_allowance_mw=(upper-s['delta'])*scale,
            limiting_generator=gid))
    return rows


def report():
    summary=load(OUT/'summary.json');protocol=load(OUT/'protocol.json');rows=[]
    for run in summary['rows']:
        folder=OUT/run['name'];contract=load(folder/'contract.json')
        assert not contract['fixed_controller'] and contract['response_relaxation_cap']==0
        for stage in run['stages']:
            sid=stage['stage'];a=load(folder/f'audit-{sid}.json')
            n=load(folder/f'network-audit-{sid}.json')
            assert not n['diagnostic_accepted']
            assert n['accepted']==bool(stage['native_success'] and a['physical_valid'] and n['reduction_valid'])
            rows.append(dict(name=run['name'],factors=run['factors'],solver=run['solver'],
                droop_normalization=contract.get('droop_normalization',contract['normalization']),
                stage=sid,native_status=stage['status'],elapsed_seconds=stage['elapsed_seconds'],
                objective=stage['objective'],native_details=stage.get('native_details'),
                accepted=n['accepted'],physical_valid=a['physical_valid'],reduction_valid=n['reduction_valid'],
                max_balance_pu=max(s['power_balance_max_pu'] for s in a['states']),
                max_response_mw=max(s['response_coupling_max_pu'] for s in a['states'])*100,
                max_dr_mw=max(s['dr_mw'] for s in a['states']),
                max_shedding_mw=max(s['shedding_mw'] for s in a['states']),
                replaceable_shedding_by_dr_max_mw=max(s['shedding_replaceable_by_DR_without_physics_changes_mw'] for s in a['states']),
                replaceable_shedding_by_dr_sum_mw=sum(s['shedding_replaceable_by_DR_without_physics_changes_mw'] for s in a['states']),
                max_loading_ratio=max(s['max_normal_loading_ratio'] for s in a['states']),
                max_voltage_pu=max(s['vm_max_pu'] for s in a['states']),
                minimum_voltage_pu=min(s['vm_min_pu'] for s in a['states'])))
    assert len(rows)==summary['native_master_solves']
    result=dict(**summary,stages=rows,protocol=protocol,minimum_relief_established=False,
        free_curves_alone_do_not_prove_full_security=True,global_optimality_proven=False)
    save(OUT/'RESULTS.json',result)
    save(OUT/'STATUS.json',dict(closed=False,bounded_campaign_complete=True,
        last_single_demand_factor=summary['last_single_demand_factor'],
        target_110_recovered=summary['target_110_recovered'],
        shared_five_demand_accepted=summary['shared_five_demand_accepted'],
        exhaustive_connected_qualified=summary['exhaustive_connected_qualified'],full_n1_accepted=False))
    FIG.mkdir(parents=True,exist_ok=True)
    fig,axs=plt.subplots(2,2,figsize=(12,8),layout='constrained')
    for i,r in enumerate(rows,1):
        color,marker=('#16834a','o') if r['accepted'] else ('#ba3535','x')
        for ax,y in [(axs[0,0],100*max(r['factors'])),(axs[0,1],max(1e-16,r['max_balance_pu'])),
                     (axs[1,0],r['max_dr_mw']),(axs[1,1],r['max_shedding_mw'])]:
            ax.scatter(i,y,color=color,marker=marker,s=55)
    for color,marker,label in [('#16834a','o','Accepted exact policy'),('#ba3535','x','Rejected stage')]:
        axs[0,0].scatter([],[],color=color,marker=marker,label=label)
    axs[0,0].axhline(110,color='gray',ls=':',label='110% target');axs[0,0].legend(fontsize=8)
    axs[0,0].set_ylabel('Highest master demand (% nominal)')
    axs[0,1].set_yscale('log');axs[0,1].set_ylabel('Original 500-bus max P/Q residual (pu)')
    axs[1,0].set_ylabel('Maximum per-outage DR (MW)')
    axs[1,1].set_ylabel('Maximum per-outage shedding (MW)')
    axs[1,1].axhline(10,color='gray',ls=':')
    for ax in axs.flat:ax.set_xlabel('Native stage number (report order)');ax.grid(alpha=.2)
    fig.suptitle('Free shared droop, exact active response — rejected points are diagnostic only')
    for ext in ('png','pdf'):fig.savefig(FIG/f'continuation.{ext}',dpi=180)
    plt.close(fig)

    figures=['continuation'];selected=None
    for file in ('selected-joint.json','selected-single-demand.json'):
        if (OUT/file).exists():selected=load(OUT/file);break
    curve_rows=[];margins=[]
    if selected:
        folder=OUT/selected['name'];stage=selected['stage']
        assert load(folder/f'network-audit-{stage}.json')['accepted']
        optimized=load(folder/f'controller-{stage}.json')['data']['case']
        engineering_figures(load(folder/f'controller-{stage}.json')['data'],load(folder/f'point-{stage}.json'),figures)
        margins=balancing_margins(load(folder/f'controller-{stage}.json')['data'],load(folder/f'point-{stage}.json'))
        save(OUT/'selected-response-margins.json',dict(selected=selected,rows=margins))
        before=load(BASE/'response_continuation/demand-10625-a06/controller-feasibility.json')['data']['case']
        pilot=load(BASE/'pilot_study.json')['data']['case']
        attach={a['control_id']:a for a in optimized['attachments']}
        for i,(a,b) in enumerate(zip(before['controls'],optimized['controls']),1):
            curve_rows.append(dict(control=i,generator=attach[i]['generator_id'],
                retained_slope=a['slope'],selected_slope=b['slope'],
                retained_vref=a['schedule']['v_ref'],selected_vref=b['schedule']['v_ref']))
        with (OUT/'droop-comparison.csv').open('w',newline='') as f:
            w=csv.DictWriter(f,fieldnames=list(curve_rows[0]));w.writeheader();w.writerows(curve_rows)
        volt=np.linspace(.85,1.15,501)
        def q(d):
            s=d['schedule'];raw=d['q_at_deadband']+(np.maximum(s['v_db_low']-volt,0)-np.maximum(volt-s['v_db_high'],0))/d['slope']
            return np.clip(raw,d['capability']['q_min'],d['capability']['q_max'])*optimized['base_power']
        for start in range(0,len(curve_rows),15):
            height=(min(15,len(curve_rows)-start)+2)//3
            fig,axes=plt.subplots(height,3,figsize=(13,3.2*height),layout='constrained',squeeze=False)
            for index,ax in enumerate(axes.flat,start):
                if index>=len(curve_rows):ax.set_visible(False);continue
                for case,label,style in [(pilot,'Pilot input',':'),(before,'Retained 106.25%','--'),(optimized,'Accepted free design','-')]:
                    ax.plot(volt,q(case['controls'][index]),style,label=label)
                ax.set_title(f"Control {index+1}, G{attach[index+1]['generator_id']}",fontsize=9)
                ax.set_xlabel('Voltage (pu)',fontsize=8);ax.set_ylabel('Q (MVAr)',fontsize=8);ax.grid(alpha=.2)
            axes.flat[0].legend(fontsize=7)
            fig.suptitle(f'Accepted droop design comparison: controls {start+1}–{min(start+15,len(curve_rows))}')
            name=f'droop-curves-{start//15+1}';figures.append(name)
            for ext in ('png','pdf'):fig.savefig(FIG/f'{name}.{ext}',dpi=160)
            plt.close(fig)
    save(OUT/'selected-controller-comparison.json',dict(selected=selected,controls=curve_rows))
    witness=None
    if selected and (OUT/'relief_priority_witness.json').exists():
        witness=load(OUT/'relief_priority_witness.json');assert witness['selected']==selected
        assert witness['original_full_network_valid'] and not witness['native_solver_acceptance']
        ss=[s for s in witness['rows'] if s['outage']!='base']
        xx=np.arange(len(ss));fig,axes=plt.subplots(2,1,figsize=(13,8),layout='constrained')
        for ax,field,label in [(axes[0],'dr','Demand response (MW)'),(axes[1],'shedding','Shedding (MW)')]:
            ax.bar(xx-.2,[s[f'original_{field}_mw'] for s in ss],width=.4,label='Native allocation')
            ax.bar(xx+.2,[s[f'derived_{field}_mw'] for s in ss],width=.4,label='DR-first witness (no new solve)')
            ax.set_ylabel(label);ax.grid(axis='y',alpha=.2);ax.legend(fontsize=8)
            ax.set_xticks(xx,[f"{100*s['factor']:g}% / {s['outage']}" for s in ss],rotation=30,ha='right',fontsize=8)
        axes[1].axhline(10,color='black',ls=':',label='Shedding cap')
        fig.suptitle('Same accepted controller, generation, voltages and equipment; only DR/shedding split changes')
        figures.append('relief-priority-witness')
        for ext in ('png','pdf'):fig.savefig(FIG/f'relief-priority-witness.{ext}',dpi=180)
        plt.close(fig)
        result['relief_priority_witness']=witness;save(OUT/'RESULTS.json',result)
    pct=100*summary['last_single_demand_factor']
    lines=['# 500-bus free-droop continuation with exact active response','',
        f'Last accepted single-demand expanded-master factor: **{pct:g}%**. 110% recovered: **{summary["target_110_recovered"]}**. Joint five-demand accepted: **{summary["shared_five_demand_accepted"]}**. Exhaustive connected qualification: **{summary["exhaustive_connected_qualified"]}**. Overall 500-bus S2 remains open.','',
        'The user explicitly confirmed this campaign and its bounded retries. All 131 taps (469–599) are corrective at 0.95–1.05. All 11 continuous shunt banks are corrective within the confirmed individual bounds, with no added movement budget. The 51 droop slopes and 51 reference voltages are free and shared across all demand/outage states in each master. The protocol retains actual selected controls and bounds.','',
        'The original active-response rule remains exact in every trial. Base normal voltage/Rate A limits and full demand remain enforced. Outages retain the confirmed voltage extension of 0.05 pu, 110% Rate A at both terminals, DR ≤1% of each positive load, shedding ≤10 MW in total and combined per-load relief ≤10%, with proportional Q relief. Artificial balance injections and physical remedies are absent.','',
        'The start is the accepted 106.25% six-state point. Continuation tries 106.5%, then 0.25-percentage-point steps toward 110%. Each single-demand master contains base, B36/B219/B562/G14/G60. Curves may change between single-demand solves; only the joint five-demand master establishes a common design across 90/95/100/105/110%. Single-demand feasibility is not a multi-demand optimum or exhaustive qualification.','',
        'Sparse exact reduction retains 430 voltage buses and every original branch terminal rating, bus-voltage bound and branch-angle constraint. Each saved stage is independently replayed on the original 500-bus network. Native success, exact response, original physical/equipment/relief/droop acceptance and reconstruction verification are all required. Failed local solves do not prove global infeasibility.','',
        '## Native stages','',
        '| # | Attempt / stage | Demand | Solver | Droop scaling | Native status | Elapsed s | Full physics | Reconstruction | Accepted | Max DR MW | Max shed MW |',
        '| ---: | --- | --- | --- | --- | --- | ---: | --- | --- | --- | ---: | ---: |']
    for i,r in enumerate(rows,1):
        demand=', '.join(f'{100*f:g}%' for f in r['factors'])
        lines.append(f"| {i} | {r['name']} / {r['stage']} | {demand} | {r['solver']} | {r['droop_normalization']} | {r['native_status']} | {r['elapsed_seconds']:.3f} | {r['physical_valid']} | {r['reduction_valid']} | {r['accepted']} | {r['max_dr_mw']:.6f} | {r['max_shedding_mw']:.6f} |")
    if not any(len(r['factors'])>1 for r in rows):
        lines += ['', 'The joint five-demand solve and exhaustive connected-outage checks were not triggered: continuation stopped below the required 110% point. The earlier nominal connected-outage qualification retains its original scope.']
    lines+=['','Elapsed times wrap optimization and may include compilation/backend setup. Native time allowances can be exceeded while a sparse factorization completes.','',
        'Equivalent droop-only scaling maps the same physical slope/reference intervals onto unit-interval coordinates; taps/shunts remain in physical coordinates. Optimizer-free bounds, equation-value and finite-difference Jacobian checks are recorded in `scaling_checks.json`. Any anchor recovery first frees the controller at the accepted lower demand and attempts staged polishing before stepping upward. This changes the numerical start/parameterization, not physical limits or the exact response policy.','',
        'A previously physically valid but response-relaxed 106.5% diagnostic may also be used as a start. It cannot count as a recovery: the new free-controller model has zero response relaxation and must freshly converge and pass every original-network gate.','',
        'Constant-objective feasibility stages do not establish minimum relief. Separate staged polishing attempts shedding, then DR, then emergency departures, then base losses; previously achieved objective budgets are constrained within the staged solve. Any accepted earlier stage is retained if a later stage fails. Native convergence alone is not an independent optimality proof.','']
    dominated=[r for r in rows if r['accepted'] and r['replaceable_shedding_by_dr_max_mw']>1e-6]
    if dominated:
        lines += ['## Relief-priority audit','',
            'For each load, replacing `max(0, min(shedding, 0.01*original_demand - DR))` of shedding by DR preserves total P/Q relief, electrical states, generation, equipment and all confirmed physical budgets. A positive amount is a constructive feasible improvement to shedding priority. It is a relabelling opportunity, not extra network loadability or a new native solve.','',
            '| Attempt / stage | Largest replaceable shedding in one outage MW | Sum across distinct outage states MW |',
            '| --- | ---: | ---: |']
        for r in dominated:
            lines.append(f"| {r['name']} / {r['stage']} | {r['replaceable_shedding_by_dr_max_mw']:.6f} | {r['replaceable_shedding_by_dr_sum_mw']:.6f} |")
        lines += ['', 'These amounts demonstrate avoidable shedding in the saved allocations, including any native-converged shedding stage listed above. Neither local nor global minimum shedding is established for such a point. Native-converged original points remain valid feasibility evidence; no derived allocation is substituted for their recorded solver output.','']
    if margins:
        lines += ['## Active-response allowance at the selected point','',
            'With this preventive Pg held fixed and the original participation factors alpha, generator bounds imply `delta <= min_g((Pmax_g - Pg_base_g)/alpha_g)`. The table compares that bound with each saved outage delta. Effective Pmax includes nested control capability limits. This identifies tight generators at the selected dispatch; it is not an MW loadability estimate or proof that every alternative dispatch fails.','',
            '| Demand | Outage | Delta MW | Remaining upper delta allowance MW | Limiting generator |',
            '| ---: | --- | ---: | ---: | ---: |']
        for r in margins:
            lines.append(f"| {100*r['factor']:g}% | {r['outage']} | {r['delta_mw']:.6f} | {r['remaining_delta_upper_allowance_mw']:.6f} | G{r['limiting_generator']} |")
        lines.append('')
    if witness:
        lines += ['## Independently validated DR-first allocation witness','',
            'The derived allocation uses all available per-load DR room before retaining shedding at that load. Its original 500-bus physical/policy and reconstruction audits pass with exactly the same electrical states and controller. It runs no optimizer, has no native acceptance, and is retained separately from every original solver point. It is a constructive improvement, not a minimum-shedding proof or a larger-demand recovery.','',
            '| Demand | Outage | Native DR MW | Witness DR MW | Native shedding MW | Witness shedding MW |',
            '| ---: | --- | ---: | ---: | ---: | ---: |']
        for s in witness['rows']:
            lines.append(f"| {100*s['factor']:g}% | {s['outage']} | {s['original_dr_mw']:.6f} | {s['derived_dr_mw']:.6f} | {s['original_shedding_mw']:.6f} | {s['derived_shedding_mw']:.6f} |")
        lines.append('')
    for name in figures:lines += [f'![{name}](../../../../docs/src/assets/s2_500bus/free_droop_continuation/{name}.png)','']
    if not selected:lines += ['No newly accepted free-controller point is available; the earlier 106.25% fixed-controller point remains valid in its original scope. No rejected design is plotted as an optimal controller.','']
    lines+=['## Scope and reproduction','',
        'The original normal-policy infeasibility certificate and island supply obstructions retain their original scope. No all-islanding N−1 closure or release follows. Qualification, when triggered by an accepted joint master, fixes its shared controller and its base per demand, then checks connected outages individually; a scan stopped after four failures leaves all unchecked events unqualified.','',
        'Run `examples/s2_500bus_free_droop_continuation.jl` with `FDC_CONTROL_CONFIRMATION` containing the actual user confirmation, serially in a fresh output checkout. It refuses an empty confirmation or existing campaign protocol. Run `examples/check_s2_500bus_free_droop_scaling.jl` without optimization, then `examples/s2_500bus_free_droop_anchor_retry.jl` for bounded anchor/scaling recovery if the first continuation stalls. The inherited 40-native-master-stage limit includes these retries and polishing. Construct the separate optimizer-free allocation witness with `examples/check_s2_500bus_relief_priority.py`. Rebuild this report with `examples/report_s2_500bus_free_droop_continuation.py` after any older report generators. Per-run executed sources, contracts, native stages, full primal points and original-network/reconstruction audits are retained.','']
    (OUT/'REPORT.md').write_text('\n'.join(lines))
    doc=ROOT/'docs/src/s2_500bus.md';text=doc.read_text().split(HEADING)[0].rstrip()
    section=[HEADING,'',lines[2],'',lines[4],'',lines[6],'',lines[8],'',lines[10],'']
    if summary['last_single_demand_factor']<=1.0625+1e-9:
        section += ['Freeing the controller did not advance the previous 106.25% accepted frontier in this bounded campaign. The new free-controller anchor passes at 106.25%; 106.5% remains numerically unresolved after MadNLP and Ipopt retries. The joint five-demand solve and exhaustive connected-outage checks were not triggered.','']
    if margins:
        tight=sorted(margins,key=lambda r:r['remaining_delta_upper_allowance_mw'])[:2]
        section += ['The closest active-response upper bounds at the selected dispatch are '+', '.join(f"{r['outage']} limited by G{r['limiting_generator']}" for r in tight)+'. These are pointwise generator-bound allowances, not global loadability bounds; alternative preventive dispatches are not ruled out.','']
    if witness:section += ['The relief-priority audit detects shedding that can be replaced by permitted DR with the same electrical state. A separate derived allocation passes the original-network physical audit but is explicitly not a new native solve or a proof of minimum relief. Native stage convergence alone does not establish resource optimality.','']
    for name in figures:section += [f'![{name}](assets/s2_500bus/free_droop_continuation/{name}.png)','']
    section += ['All native stages, accepted curve values, polishing outcomes and original-network gates are retained in `artifacts/s2_scopf/ieee500_native/free_droop_continuation/REPORT.md` and `RESULTS.json`. No local failure is an infeasibility certificate. Existing normal-policy and islanding results retain their original scope; no release is published.','']
    doc.write_text(text+'\n\n'+'\n'.join(section))
    pointer=dict(report='free_droop_continuation/REPORT.md',results='free_droop_continuation/RESULTS.json',
        last_single_demand_factor=summary['last_single_demand_factor'],target_110_recovered=summary['target_110_recovered'],
        shared_five_demand_accepted=summary['shared_five_demand_accepted'],
        exhaustive_connected_qualified=summary['exhaustive_connected_qualified'],full_n1_accepted=False)
    for p in (BASE/'CURRENT_RESULTS.json',BASE/'STATUS.json'):
        data=load(p);data['free_droop_continuation_followup']=pointer;save(p,data)
    save(OUT/'VALIDATION.json',dict(native_master_stages=len(rows),
        all_reconstruction_maps_valid=all(r['reduction_valid'] for r in rows),
        accepted_native_stages=[dict(name=r['name'],stage=r['stage']) for r in rows if r['accepted']],
        original_network_audit_per_stage=True,response_relaxation=0,
        scaling_checks=load(OUT/'scaling_checks.json') if (OUT/'scaling_checks.json').exists() else None,
        derived_relief_witness=witness,
        full_n1_accepted=False,global_optimality_proven=False))
    paths=[p for p in OUT.rglob('*') if p.is_file() and p.name!='source_manifest.json']+list(FIG.glob('*'))
    paths += [ROOT/'examples'/n for n in ('s2_500bus_free_droop_continuation.jl','report_s2_500bus_free_droop_continuation.py',
        's2_500bus_free_droop_anchor_retry.jl','check_s2_500bus_free_droop_scaling.jl','s2_arpae500_loadability.jl',
        'check_s2_500bus_relief_priority.py',
        's2_500bus_network_reduction.jl','audit_s2_500bus_loadability.py','audit_s2_500bus_network_reduction.py',
        'analyse_s2_500bus_network_reduction.py','s2_followup_physics.py')]
    paths += [BASE/'pilot_study.json',ROOT/'artifacts/s1_free_droop/500/angle_limits.json',
        ROOT/'artifacts/s1_arpae500/calibrated-study.json']
    for name in ('demand-10625-a06','extended-response-cap-4-a25'):
        paths += [BASE/'response_continuation'/name/file for file in
            ('point-feasibility.json','controller-feasibility.json','audit-feasibility.json','network-audit-feasibility.json')]
    save(OUT/'source_manifest.json',{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})
    print(json.dumps(pointer))


if __name__=='__main__':report()
