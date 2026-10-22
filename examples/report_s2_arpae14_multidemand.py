"""Publish the independently audited multi-demand S2 campaign and scientific figures."""
from pathlib import Path
import json,hashlib,shutil,zipfile
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from control_figure_reporting import attach

ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'artifacts/s2_scopf/ieee14_native';OUT=BASE/'multidemand'
load=lambda p:json.loads(p.read_text());data=lambda p:load(p)['data']
status=load(OUT/'STATUS.json');audit=load(OUT/'independent_audit.json')
assert audit['classification_discrepancies']==0
designs=load(OUT/'design_summary.json')['attempts']
protocol=load(OUT/'protocol.json');evaluation=load(OUT/'evaluation_summary.json')['attempts'] if (OUT/'evaluation_summary.json').exists() else []
figdir=OUT/'plots';figdir.mkdir(exist_ok=True)
assets=ROOT/'docs/src/assets/s2_14bus_multidemand';assets.mkdir(parents=True,exist_ok=True)
plt.rcParams.update({'font.size':10,'axes.grid':True,'grid.alpha':.22,'figure.constrained_layout.use':True})
figures=[]
def save(fig,name,caption):
    for ext in ['png','svg']:
        target=figdir/f'{name}.{ext}';fig.savefig(target,dpi=170);shutil.copy2(target,assets/target.name)
    plt.close(fig);figures.append((name,caption))

if evaluation:
    factors=sorted({r['factor'] for r in evaluation});solvers=['ipopt','madnlp','ccopt']
    fig,ax=plt.subplots(figsize=(11,3.2));matrix=np.array([[next(r['accepted_with_trip_assumption'] for r in evaluation if r['solver']==s and r['factor']==f) for f in factors] for s in solvers])
    ax.imshow(matrix,cmap=matplotlib.colors.ListedColormap(['#f6c4bb','#bce3cd']),vmin=0,vmax=1,aspect='auto')
    for j,s in enumerate(solvers):
        for i,f in enumerate(factors):ax.text(i,j,'PASS' if matrix[j,i] else 'NOT\nQUALIFIED',ha='center',va='center',fontsize=9)
    ax.set(xticks=range(len(factors)),xticklabels=[f'{f*100:g}%'+('\nheld out' if f in protocol['held_out_factors'] else '\ntraining') for f in factors],yticks=range(3),yticklabels=solvers,title='Frozen shared controller: all 24 connected outages + conditional G5-trip projection')
    ax.grid(False);save(fig,'qualification','Qualification at each sampled demand; held-out points never enter the design master.')
    fig,ax=plt.subplots(figsize=(10,4))
    for s in solvers:
        rs=sorted([r for r in evaluation if r['solver']==s],key=lambda r:r['factor'])
        ax.plot([r['factor']*100 for r in rs],[r['final']['base_loss_mw'] if r['accepted_with_trip_assumption'] else np.nan for r in rs],'o-',label=s)
    ax.set(xlabel='Demand (% of nominal)',ylabel='Base active loss (MW)',title='Accepted frozen-controller operating points');ax.legend()
    save(fig,'losses','Base losses for accepted points only; overlapping solver curves indicate close numerical agreement.')
    for s in solvers:
        fig,axes=plt.subplots(2,2,figsize=(12,8));points=[[],[],[],[]]
        for r in sorted([r for r in evaluation if r['solver']==s],key=lambda r:r['factor']):
            directory=BASE/r['final']['name'];study=data(directory/'optimized_input.json');result=data(directory/'result.json')
            entry=next(e for e in audit['connected'] if e['name']==r['final']['name'])
            for ck in entry['checks']:
                if ck.get('missing'):continue
                sid=ck['id'];st=result['states'][sid];event=next((e for e in study['contingencies'] if e['id']==sid),{'generator_ids':[]})
                for i,g in enumerate(study['case']['generators']):
                    if not g['available'] or g['id'] in event['generator_ids']:continue
                    points[0].append((r['factor']*100,(st['pg'][i]-g['p_min'])/(g['p_max']-g['p_min'])))
                    points[1].append((r['factor']*100,(st['qg'][i]-g['q_min'])/(g['q_max']-g['q_min'])))
                for i,b in enumerate(study['case']['network']['buses']):
                    points[2].append((r['factor']*100,(st['vm'][i]-b['v_min'])/(b['v_max']-b['v_min'])))
                for bid,flow in ck['branch_max_terminal_s_pu'].items():
                    rating=next(b['thermal_limit'] for b in study['case']['network']['branches'] if str(b['id'])==bid)
                    points[3].append((r['factor']*100,flow/rating))
        for ax,pts,color in zip(axes.flat,points,['#2878a5','#ad6c28','#497c45','#7959a5']):
            xx,yy=zip(*pts);ax.scatter(xx,yy,s=8,color=color,alpha=.35)
        for ax,title in zip(axes.flat,['Generator P: fraction of capability interval','Generator Q: fraction of capability interval','Voltage: fraction of allowed interval','Branch: maximum terminal MVA / Rate A']):
            ax.axhline(1,color='crimson',ls='--',lw=1,label='Upper bound')
            ax.axhline(0,color='black',ls=':',lw=1);ax.set(title=title,xlabel='Demand (%)',ylabel='Normalized value');ax.set_ylim(-.04,1.06)
        fig.suptitle(f'{s}: all buses, online generators and available branches in all 25 states per demand')
        save(fig,f'limits-{s}',f'{s} full-state limit check. Each dot is one device in one base/contingency state. Capability and voltage intervals map to [0,1]; thermal loading is bounded above by 1.')
    fig,axes=plt.subplots(2,2,figsize=(12,8));equipment=[('tap_settings','19','Tap 19: 4–7',.9291,1.0269),('tap_settings','20','Tap 20: 4–9',.92055,1.01745),('tap_settings','21','Tap 21: 5–6',.8854,.9786),('shunt_settings','3','Bank 3 at bus 11 (B pu)',0,.4)]
    colors=['#2878a5','#d48022','#4e9c65']
    for ax,(field,key,title,lo,hi) in zip(axes.flat,equipment):
        for offset,s,color in zip([-.13,0,.13],solvers,colors):
            for r in [r for r in evaluation if r['solver']==s]:
                result=data(BASE/r['final']['name']/'result.json');values=[v[key] for v in result[field].values() if key in v]
                ax.scatter([r['factor']*100+offset]*len(values),values,s=12,alpha=.55,color=color,label=s if r['factor']==factors[0] else None)
        ax.axhline(lo,color='crimson',ls='--',lw=1);ax.axhline(hi,color='crimson',ls='--',lw=1);ax.set(title=title,xlabel='Demand (%)');ax.legend(fontsize=8)
    fig.suptitle('Corrective equipment settings: all base and contingency states; small horizontal solver offsets')
    save(fig,'equipment','All corrective tap and continuous-bank values, with confirmed absolute bounds. A tripped transformer has no tap variable.')

original=data(BASE/'full-frozen-ipopt/input.json')['case']['controls']
nominal=data(BASE/'full-designed-ipopt/optimized_input.json')['case']['controls']
accepted=[r for r in designs if r['accepted']]
for i in range(5):
    fig,ax=plt.subplots(figsize=(8,5));vm=np.linspace(.9,1.12,700)
    curves=[('S1 calibrated base',original[i],'#777777','--'),('Nominal S2 design',nominal[i],'#a95d25',':')]
    for row in accepted:
        curves.append((f"Multi-demand {row['solver']}",data(OUT/row['name']/'controller.json')['case']['controls'][i],{'ipopt':'#2878a5','madnlp':'#3d9959'}[row['solver']],'-'))
    for label,d,color,ls in curves:
        q=np.clip((d['schedule']['v_ref']-vm)/d['slope']+d['q_at_deadband'],d['capability']['q_min'],d['capability']['q_max'])*100
        ax.plot(vm,q,label=label,color=color,ls=ls,lw=1.7)
    cap=original[i]['capability'];ax.axhline(cap['q_min']*100,color='crimson',ls=':',lw=.8);ax.axhline(cap['q_max']*100,color='crimson',ls=':',lw=.8)
    ax.set(title=f'Generator {i+1}: shared zero-deadband droop designs',xlabel='Measured voltage (pu)',ylabel='Reactive response (MVAr)');ax.legend(fontsize=8)
    save(fig,f'droop-{i+1}',f'Generator {i+1}: base, nominal S2 and accepted multi-demand designs. CCOpt evaluates the selected shared curve frozen; it does not design a separate curve in this campaign.')

design_table='\n'.join(f"| {r['name']} | {r['solver_status']} | {'Pass' if r['accepted'] else 'Unqualified'} | {format(r['nominal_loss_mw'],'.9f') if r['accepted'] else '—'} |" for r in designs)
eval_table='\n'.join(f"| {r['solver']} | {100*r['factor']:g}% | {'Held out' if r['held_out'] else 'Training'} | {'Pass' if r['accepted_with_trip_assumption'] else 'Unqualified'} | {format(r['final']['base_loss_mw'],'.9f') if r['accepted_with_trip_assumption'] else '—'} |" for r in sorted(evaluation,key=lambda r:(r['factor'],r['solver'])))
qualified=sum(r['accepted_with_trip_assumption'] for r in evaluation)
selection=load(OUT/'selection.json') if (OUT/'selection.json').exists() else None
parameter_table=''
penalty_text=''
if selection:
    shared=data(OUT/'selected_controller.json')['case']['controls']
    parameter_table='| Generator | Nominal-only slope % | Shared slope % | Nominal-only Vref pu | Shared Vref pu |\n|---|---:|---:|---:|---:|\n'
    for i,(old,new) in enumerate(zip(nominal,shared),1):
        span=old['capability']['q_max']-old['capability']['q_min']
        parameter_table+=f"| G{i} | {old['slope']*span*100:.6f} | {new['slope']*span*100:.6f} | {old['schedule']['v_ref']:.9f} | {new['schedule']['v_ref']:.9f} |\n"
    chosen=next(r for r in designs if r['name']==selection['name'])
    old_loss=load(BASE/'full-designed-ipopt/summary.json')['base_loss_mw']
    penalty=(chosen['nominal_loss_mw']-old_loss)*1e6
    penalty_text=f'The selected shared design adds {penalty:.3f} W of nominal base loss relative to the earlier nominal-only Ipopt controller. These are local solutions under different feasibility contracts, not a global optimality comparison.'
intro=f"**{len(accepted)} accepted shared design; {qualified}/{len(evaluation)} frozen solver–demand combinations accepted.**" if evaluation else '**No accepted shared design after the declared primary/retry budgets.**'
frozen_records=[r for r in audit['connected'] if r['name'].startswith('multidemand/')]
margin_table=''
if frozen_records:
    margin_table='| Check across all frozen evaluation states | Worst value |\n|---|---:|\n'
    for key,label,kind in [('power_balance_max_pu','AC balance residual pu',max),('exact_droop_max_pu','Exact droop residual pu',max),('response_coupling_max_pu','Active response residual pu',max),('thermal_min_margin_pu','Thermal margin pu',min),('voltage_min_margin_pu','Voltage margin pu',min),('generator_p_min_margin_pu','Generator P margin pu',min),('generator_q_min_margin_pu','Generator Q margin pu',min)]:
        worst=kind(c[key] for r in frozen_records for c in r['checks'] if not c.get('missing'))
        margin_table+=f'| {label} | {worst:.6g} |\n'
body=f'''# S2 14-bus shared multi-demand droop design

{intro} This is qualification at sampled operating conditions, with conditional retained-network treatment of the 7–8 outage. It does not establish a continuous demand envelope or general islanding security.

## Confirmed model and objective

The user confirmed corrective transformer taps and shunts within the existing bounds on 2026-10-15. Taps 19/20/21 retain source-ratio ±5% bounds; bus 11 bank 3 is continuous B in [0,0.4] pu. Each demand and contingency can use its own settings, with no additional movement budget. The case retains S1’s Pmin=0 and symmetric-Q capability convention, together with source voltage, Rate-A and angle bounds. Original-limit requalification remains outside this campaign. Continuous shunt feasibility does not establish discrete switching feasibility.

Five slopes and five reference voltages are shared across **90/95/100/105/110% demand and all 24 connected outages**: 125 AC states in one master. Slopes retain the 2–8% full-Q-span bounds, references retain calibration ±0.02 pu, and deadband and Q reference remain zero. Only the 100% base-state active loss enters the objective. Each demand has its own preventive dispatch; surviving units follow Pmax-weighted response within that demand.

Ipopt and MadNLP design the shared curves. Primary budgets are 600 iterations/20 native solver seconds, with one 3,000-iteration/120-second retry per backend. The selected accepted controller is frozen for all three backends, including exact-complementarity CCOpt, at the five training demands and held-out **92.5/97.5/102.5/107.5%**. Held-out conditions do not enter controller design. Selection uses the lowest nominal loss among accepted multi-demand designs, not held-out performance.

The line 7–8 outage is checked by projecting the G5-outage witness to the retained 13-bus network under G5 trip and unloaded bus 8 disconnection. The boundary branch has zero flow and charging in that witness. Retained AC physics, bounds and response coupling are independently replayed. Protection and dynamic response are outside this steady-state assumption.

## Design outcomes

| Attempt | Native status | Qualification | Nominal base loss MW |
|---|---|---|---:|
{design_table}

MadNLP's shared 125-state design reaches `TIME_LIMIT` in both its primary and retry; it is not counted as an accepted design. Its smaller fixed-controller evaluation masters pass at every sampled demand. CCOpt performs exact-complementarity verification with the selected curves frozen and does not optimize an independent shared design here.

Selected design: **{selection['name'] if selection else 'none'}**. Failed iterates are retained as diagnostic evidence and are not feasible loss benchmarks. Local solver failure is not a global infeasibility certificate.

{penalty_text}

{parameter_table}

## Frozen-controller outcomes

| Backend | Demand | Role | Qualification | Base loss MW |
|---|---:|---|---|---:|
{eval_table}

## Independent verification

Independent standard-library complex AC calculations check **{audit['connected_states']} connected-state records** and **{audit['island_projections']} conditional island projections**, with **zero classification discrepancies**. The audit verifies run source hashes, exact shared-curve identity, design bounds, load scaling, outage catalogue, equipment bounds, preventive response coupling, nominal objective replay and all exact physical limits. Tolerances remain AC/limits/response 1e-6 pu, exact droop 1e-5 pu and unavailable generation 1e-8 pu.

The audited total includes the rejected design attempts. The accepted frozen evaluation contributes 675 connected states and 27 conditional projections; all of those pass. Several limits are active to numerical tolerance, so this is not a positive-margin robustness certificate.

{margin_table}

The campaign adapter builds the existing native AC scenario models into one shared JuMP model. No library equations or defaults changed. Historical S1 and nominal/frozen-demand S2 results remain separate; S1 remains closed. No 500-bus runs or release publication are included.

## Reproduction and evidence

Inputs, starts, contracts, raw states, controller settings, master objective and conditional projections are retained under `artifacts/s2_scopf/ieee14_native/multidemand`. `protocol.json` records confirmation, bounds and run source hashes. `independent_audit.json` retains per-state residuals and margins.

```sh
julia --project=. examples/s2_arpae14_multidemand.jl "Explicit confirmation of this campaign configuration"
python3 examples/audit_s2_arpae14_multidemand.py
python examples/report_s2_arpae14_multidemand.py
```
'''
def gallery(prefix):return '\n\n'.join(f'### {caption.split(":")[0]}\n\n![{name}]({prefix}/{name}.png)\n\n{caption}' for name,caption in figures)
(OUT/'REPORT.md').write_text(body+'\n## Figures\n\n'+gallery('plots')+'\n')
(ROOT/'docs/src/s2_14bus_multidemand.md').write_text(body+'\n## Figures\n\n'+gallery('assets/s2_14bus_multidemand')+'\n')
note=f'''## Shared multi-demand design follow-up

{intro} The new campaign shares one controller across five demand training points and 24 connected outages, with four additional held-out demands and corrective equipment within the confirmed bounds. See the [multi-demand report](s2_14bus_multidemand.md). Historical scores and S1 closure are unchanged.'''
for name in ['s2_14bus.md','s2_14bus_followup.md','milestones.md','future_work.md']:
    attach(ROOT/'docs/src'/name,'S2_MULTIDEMAND',note)
attach(BASE/'REPORT.md','S2_MULTIDEMAND',note.replace('(s2_14bus_multidemand.md)','(multidemand/REPORT.md)'))
release_note=f'''## S2 14-bus shared multi-demand follow-up

{intro} Shared slopes/references are trained on five demands and all 24 connected outages; the selected accepted controller is frozen at five training and four held-out demands for Ipopt, MadNLP and CCOpt. Independent replay: {audit['connected_states']} connected-state records and {audit['island_projections']} conditional G5-trip projections, zero discrepancies. Corrective tap/continuous-bank bounds remain unchanged. This sampled steady-state result makes no continuous-envelope or general islanding claim. S1 remains closed; no release has been published.'''
for name in ['RELEASE_NOTES_UNRELEASED.md','CHANGELOG.md']:
    attach(ROOT/name,'S2_MULTIDEMAND',release_note)
attach(ROOT/'README.md','S2_MULTIDEMAND',note.replace('(s2_14bus_multidemand.md)','(docs/src/s2_14bus_multidemand.md)'))
main_status=load(BASE/'STATUS.json')
status.update(independent_connected_state_checks=audit['connected_states'],independent_island_projection_checks=audit['island_projections'],independent_discrepancies=0,
    training_evaluation_lanes=sum(not r['held_out'] for r in evaluation),accepted_training_lanes=sum(r['accepted_with_trip_assumption'] and not r['held_out'] for r in evaluation),
    held_out_evaluation_lanes=sum(r['held_out'] for r in evaluation),accepted_held_out_lanes=sum(r['accepted_with_trip_assumption'] and r['held_out'] for r in evaluation),
    s1_status=load(ROOT/'artifacts/s1_closeout/STATUS.json')['status'])
(OUT/'STATUS.json').write_text(json.dumps(status,indent=2)+'\n')
main_status['confirmed_multidemand_followup']=status
(BASE/'STATUS.json').write_text(json.dumps(main_status,indent=2)+'\n')
(OUT/'validation.json').write_text(json.dumps(dict(independent_discrepancies=0,connected_states=audit['connected_states'],island_projections=audit['island_projections'],library_code_changed=False,s1_closed=status['s1_status']=='closed',embedded_figures=len(figures),documentation_build='pending'),indent=2)+'\n')
with zipfile.ZipFile(figdir/'all_figures.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(figdir.glob('*')):
        if p.suffix in ['.png','.svg']:z.write(p,p.name)
paths=[ROOT/'examples/audit_s2_arpae14_multidemand.py',Path(__file__),OUT/'REPORT.md',ROOT/'docs/src/s2_14bus_multidemand.md']+[p for p in assets.iterdir() if p.suffix in ['.png','.svg']]
(OUT/'reporting_manifest.json').write_text(json.dumps({str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},indent=2)+'\n')
print(intro,len(figures),'figures generated')

from control_figure_reporting import attach_s2_solver_designs
attach_s2_solver_designs(ROOT/'docs/src/s2_14bus_multidemand.md',doc=True)
attach_s2_solver_designs(OUT/'REPORT.md',link='solver_design_comparison/REPORT.md')

from control_figure_reporting import attach_s2_ccopt_recovery
attach_s2_ccopt_recovery(ROOT/'docs/src/s2_14bus_multidemand.md',doc=True)
attach_s2_ccopt_recovery(OUT/'REPORT.md',link='solver_design_comparison/ccopt_recovery/REPORT.md')
