"""Publish targeted CCOpt recovery, diagnostic endpoints and refreshed design curves."""
from pathlib import Path
import json,hashlib,shutil,zipfile
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from control_figure_reporting import attach
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'artifacts/s2_scopf/ieee14_native';MULTI=BASE/'multidemand';COMPARE=MULTI/'solver_design_comparison';OUT=COMPARE/'ccopt_recovery'
load=lambda p:json.loads(p.read_text());data=lambda p:load(p)['data']
summary=load(OUT/'summary.json');audit=load(OUT/'independent_audit.json');status=load(OUT/'STATUS.json');diagnosis=load(OUT/'diagnosis.json')
assert audit['classification_discrepancies']==0
series={'ipopt':dict(directory=MULTI/'design-ipopt',record=load(MULTI/'design-ipopt/summary.json')),
        'madnlp':dict(directory=COMPARE/'design-madnlp',record=load(COMPARE/'design-madnlp/summary.json'))}
if summary['selected']:
    directory=OUT/summary['selected'];series['ccopt']=dict(directory=directory,record=load(directory/'summary.json'))
colors={'ipopt':'#2577ad','madnlp':'#d68222','ccopt':'#429b61'}
for solver,entry in series.items():entry['controls']=data(entry['directory']/'controller.json')['case']['controls']
curve_series={s:dict(entry,accepted=True) for s,entry in series.items()}
for solver in ['madnlp','ccopt']:
    if solver in series:continue
    attempts=[r for r in summary['attempts'] if r['solver']==solver]
    if attempts:
        last=attempts[-1];directory=OUT/last['name']
        if (directory/'controller.json').exists():
            curve_series[solver]=dict(directory=directory,record=last,controls=data(directory/'controller.json')['case']['controls'],accepted=False)
original=data(BASE/'full-frozen-ipopt/input.json')['case']['controls']
plots=OUT/'plots';plots.mkdir(exist_ok=True);assets=ROOT/'docs/src/assets/s2_14bus_ccopt_recovery';assets.mkdir(parents=True,exist_ok=True)
plt.rcParams.update({'font.size':10,'axes.grid':True,'grid.alpha':.22,'figure.constrained_layout.use':True})
figures=[];comparisons={}
breakpoints=[]
for curve in original+[d for entry in curve_series.values() for d in entry['controls']]:
    for q in [curve['capability']['q_min'],curve['capability']['q_max']]:
        value=curve['schedule']['v_ref']-curve['slope']*(q-curve['q_at_deadband'])
        if .9<=value<=1.12:breakpoints.append(value)
voltage=np.unique(np.r_[np.linspace(.9,1.12,1400),breakpoints])
def save(fig,name,caption):
    for ext in ['png','svg']:
        p=plots/f'{name}.{ext}';fig.savefig(p,dpi=170);shutil.copy2(p,assets/p.name)
    plt.close(fig);figures.append((name,caption))
def response(d,vm):return np.clip(d['q_at_deadband']+(d['schedule']['v_ref']-vm)/d['slope'],d['capability']['q_min'],d['capability']['q_max'])*100
for i in range(5):
    fig,(ax,delta)=plt.subplots(2,1,figsize=(9,7),height_ratios=[2.5,1],sharex=True)
    ax.plot(voltage,response(original[i],voltage),'--',color='#888888',label='S1 calibrated base')
    reference=response(series['ipopt']['controls'][i],voltage)
    for solver,entry in curve_series.items():
        d=entry['controls'][i];q=response(d,voltage)
        label=f'{solver}: free shared design' if entry['accepted'] else f'{solver}: UNQUALIFIED last iterate'
        ax.plot(voltage,q,color=colors[solver],label=label,lw=1.8,ls={'ipopt':'-','madnlp':'--','ccopt':':' }[solver])
        if solver!='ipopt':delta.plot(voltage,q-reference,color=colors[solver],label=solver,lw=1.4)
        comparisons.setdefault(solver,[]).append(dict(generator=i+1,accepted=entry['accepted'],slope=d['slope'],full_q_span_slope_percent=d['slope']*(d['capability']['q_max']-d['capability']['q_min'])*100,
            v_ref_pu=d['schedule']['v_ref'],delta_v_ref_from_ipopt_pu=d['schedule']['v_ref']-series['ipopt']['controls'][i]['schedule']['v_ref'],maximum_curve_difference_from_ipopt_mvar=float(max(abs(q-reference)))))
    cap=original[i]['capability'];ax.axhline(cap['q_min']*100,color='crimson',ls=':',lw=.7);ax.axhline(cap['q_max']*100,color='crimson',ls=':',lw=.7)
    ax.set(title=f'G{i+1}: shared multi-demand curves'+(' (failed iterate marked)' if any(not e['accepted'] for e in curve_series.values()) else ''),ylabel='Reactive response (MVAr)');ax.legend(fontsize=8)
    delta.axhline(0,color='#555555',lw=.8);delta.set(xlabel='Measured voltage (pu)',ylabel='ΔQ vs Ipopt\n(MVAr)')
    if len(curve_series)>1:delta.legend(fontsize=8)
    save(fig,f'droop-{i+1}',f'G{i+1}: shared curves and reactive-response differences from Ipopt. Any unqualified last iterate is explicitly marked and is diagnostic only, not an accepted optimal design.')

fig,ax=plt.subplots(figsize=(8,4));base_loss=series['ipopt']['record']['nominal_loss_mw']
names=list(series);difference=[(series[s]['record']['nominal_loss_mw']-base_loss)*1e6 for s in names]
bars=ax.bar(names,difference,color=[colors[s] for s in names]);ax.axhline(0,color='#444444',lw=.8)
for bar,diff in zip(bars,difference):ax.annotate(f'{diff:+.5f} W',(bar.get_x()+bar.get_width()/2,diff),xytext=(0,5 if diff>=0 else -13),textcoords='offset points',ha='center',fontsize=9)
ax.margins(y=.3);ax.set(title=f'Nominal loss difference; Ipopt baseline {base_loss:.9f} MW',ylabel='Difference from Ipopt (W)')
save(fig,'nominal-loss','Nominal objective differences among accepted designs. All non-nominal training states impose feasibility only; this is not a global optimality or solver-speed ranking.')

training=[.9,.95,1.,1.05,1.1];state_ids=['base']+[c['id'] for c in data(BASE/'full-frozen-ipopt/input.json')['contingencies']]
devices=[('tap_settings','19','Transformer 19: 4–7',.9291,1.0269),('tap_settings','20','Transformer 20: 4–9',.92055,1.01745),('tap_settings','21','Transformer 21: 5–6',.8854,.9786),('shunt_settings','3','Bus 11 bank 3: continuous B pu',0,.4)]
equipment={}
for field,key,title,lo,hi in devices:
    fig,axes=plt.subplots(5,1,figsize=(13,12),sharex=True)
    for ax,f in zip(axes,training):
        for solver,entry in series.items():
            result=data(entry['directory']/f'result-{f}.json')
            values=[result[field][sid].get(key,np.nan) for sid in state_ids]
            equipment.setdefault(solver,{}).setdefault(str(f),{})[f'{field}-{key}']=[None if np.isnan(v) else v for v in values]
            ax.plot(range(25),values,'o-',ms=3,lw=1,label=solver,color=colors[solver],alpha=.8)
        ax.axhline(lo,color='crimson',ls='--',lw=.8);ax.axhline(hi,color='crimson',ls='--',lw=.8);ax.set_ylabel(f'{f*100:g}% demand')
    axes[0].legend(ncol=3,fontsize=9);axes[-1].set(xticks=range(25),xticklabels=['base']+[sid.replace('generator_','G').replace('branch_','B') for sid in state_ids[1:]])
    axes[-1].tick_params(axis='x',rotation=65,labelsize=8);axes[-1].set_xlabel('Base and connected-outage state (B = branch, G = generator)')
    fig.suptitle(title+' — corrective values in each independently optimized master')
    save(fig,f'{field}-{key}',title+': all 125 training states for every accepted free design, with confirmed absolute bounds; a tripped transformer has no tap variable.')

(OUT/'comparison_values.json').write_text(json.dumps(dict(controllers=comparisons,equipment=equipment,state_order=state_ids,nominal_losses_mw={s:e['record']['nominal_loss_mw'] for s,e in series.items()}),indent=2)+'\n')

old=[load(COMPARE/name/'summary.json') for name in ['design-ccopt','retry-design-ccopt']]
endpoints=old+summary['attempts']
fig,axes=plt.subplots(2,2,figsize=(13,8));names=[r['name'].replace('design-','').replace('madnlp-seed-','Mad seed\n').replace('scheduled-','Scheduled\n') for r in endpoints]
colors_end=['#479a68' if r['accepted'] else '#b86f4d' for r in endpoints]
for ax,key,title in zip(axes.flat,['primal_feasibility','dual_feasibility','complementarity_feasibility','inner_iterations'],['Native primal feasibility','Native relaxed-NLP dual feasibility','Complementarity product residual','Cumulative inner iterations']):
    values=[max(r['ccopt_diagnostics'][key],1e-16) for r in endpoints]
    ax.bar(range(len(values)),values,color=colors_end);ax.set(xticks=range(len(names)),xticklabels=names,title=title)
    if key!='inner_iterations':ax.set_yscale('log')
    ax.tick_params(axis='x',labelsize=8)
fig.suptitle('CCOpt endpoint diagnostics: historical attempts and targeted recovery; green = native/physical acceptance')
save(fig,'convergence-endpoints','Native final relaxed-NLP metrics and cumulative iteration counts, not complete iteration traces or original-MPCC stationarity certificates. Different starts and continuation rules prevent causal attribution from these endpoints alone.')

attempt_table='\n'.join(f"| {r['name']} | {r['solver_status']} | {'Pass' if r['accepted'] else 'Unqualified'} | {r['ccopt_diagnostics']['primal_feasibility']:.6g} | {r['ccopt_diagnostics']['dual_feasibility']:.6g} | {r['complementarity_product_max']:.6g} | {format(r['nominal_loss_mw'],'.9f') if r['accepted'] else '—'} |" for r in endpoints)
parameter_table='\n'.join(f"| G{i+1} | {solver} | {'Accepted' if row['accepted'] else 'Unqualified iterate'} | {row['full_q_span_slope_percent']:.8f} | {row['v_ref_pu']:.10f} |" for i in range(5) for solver,rows in comparisons.items() for row in [rows[i]])
held_table='\n'.join(f"| {r['factor']*100:g}% | {r['final']['solver_status']} | {'Pass' if r['accepted'] else 'Unqualified'} |" for r in summary['heldout'])
outcome='**CCOpt recovered an accepted free multi-demand design.**' if summary['selected'] else '**CCOpt remains unqualified after the two declared recovery attempts.**'
physical_table=''
for r in summary['attempts']:
    checks=[c for block in audit['connected'] if block['name'].startswith(r['name']+'/') for c in block['checks']]
    physical_table+=f"| {r['name']} | {sum(not c['valid'] for c in checks)} | {max(c['power_balance_max_pu'] for c in checks):.6g} | {max(c['exact_droop_max_pu'] for c in checks):.6g} |\n"
body=f'''# S2 targeted CCOpt convergence recovery

{outcome} Ipopt and MadNLP retain their earlier accepted local designs. Historical failed attempts are preserved separately.

## Diagnosis and confirmed contract

The earlier CCOpt retry satisfied training physics but ended with native relaxed-NLP dual feasibility 478.226, primal feasibility 5.8985e-7 and complementarity product 7.5366e-9. Feasibility alone did not establish optimizer convergence. The installed proportional update ties the relaxation parameter to the barrier. A different accepted primal start and a stationarity-gated scheduled update are tested as recovery hypotheses; these observations do not prove a single numerical cause.

The user confirmed this recovery campaign: all three taps corrective within source-relative ±5%, bus 11 bank 3 continuous B in [0,0.4] pu and corrective, with no additional movement budget. Each master retains all 125 training states, ten shared free droop parameters, 1,200 complementarity pairs, the 100% base-loss objective and the existing Pmin=0/symmetric-Q case. Active response, source voltage/angle/Rate-A limits, slope/reference bounds, zero deadband and physical tolerances are unchanged.

Both strategies start from the same accepted **MadNLP full primal witness**, including five-demand voltages, dispatch, curves and corrective equipment. Dual multipliers are initialized by CCOpt, not transferred from MadNLP. The primary uses proportional relaxation and mu_init=1e-8. Its one retry uses scheduled relaxation with sigma_init=1e-6, sigma_min=1e-14, target_accuracy=1e-11 and mu_init=1e-6. Each has a 6,000-iteration/300-native-second budget. Native tol and acceptable_tol remain 1e-11. No physical constraint or acceptance tolerance is relaxed to obtain a pass.

## Convergence outcomes

| Attempt | Native status | Acceptance | Native primal residual | Native dual residual | Complementarity product | Accepted nominal loss MW |
|---|---|---|---:|---:|---:|---:|
{attempt_table}

Native residuals describe the final relaxed NLP, not an original-MPCC stationarity certificate. The retained coordinate residual diagnostics use MadNLP's internal scaled-NLP arrays before its aggregate residual normalization. They do not identify physical equation errors or prove original-problem stationarity.

| Recovery attempt | Physically invalid training states / 125 | Max AC residual pu | Max exact-droop residual pu |
|---|---:|---:|---:|
{physical_table}

The plots mark any unconverged last iterate as diagnostic only. Accepted-objective and equipment comparisons exclude unqualified candidates.

## Shared curve comparison

| Generator | Backend | Qualification | Full-Q-span slope % | Vref pu |
|---|---|---|---:|---:|
{parameter_table}

## Held-out qualification

Accepted recovered curves are frozen at 92.5/97.5/102.5/107.5% demand. Each held-out master retains all 24 connected outages. No held-out point enters training.

| Demand | Native status | Combined acceptance |
|---|---|---|
{held_table or '| — | No accepted recovered controller | Not run |'}

The line 7–8 event retains the confirmed G5-trip/unloaded-bus8-disconnection assumption and independently checked retained-network projection. Protection, dynamics and qualification between sampled demands remain outside this claim.

## Verification and stage decision

Independent replay checks **{audit['connected_states']} connected-state records** and **{audit['island_projections']} conditional projections**, with **zero classification discrepancies**. It verifies source and installed solver hashes, the exact accepted MadNLP starting states, unchanged equipment and shared-design policies, load factors, outage catalogue, all exact physical limits and nominal objective replay. S1 remains closed. No library equations or defaults changed, and no 500-bus optimisation was started.

The [14-bus qualification review](s2_14bus_review.md) records the closeout decision from the accepted recovered design and held-out outcomes; an unqualified recovery would not close the outstanding CCOpt optimizer-convergence item. Broader S2 and 500-bus qualification are separate scopes.

```sh
julia --project=. examples/s2_arpae14_ccopt_recovery.jl "Explicit confirmation of this recovery configuration"
python3 examples/audit_s2_arpae14_ccopt_recovery.py
python examples/report_s2_arpae14_ccopt_recovery.py
python3 examples/report_s2_14bus_review.py
```
'''
def gallery(prefix):return '\n\n'.join(f'![{name}]({prefix}/{name}.png)\n\n{caption}' for name,caption in figures)
(OUT/'REPORT.md').write_text(body.replace('(s2_14bus_review.md)','(../../../14bus_review/REPORT.md)')+'\n## Figures\n\n'+gallery('plots')+'\n')
(ROOT/'docs/src/s2_14bus_ccopt_recovery.md').write_text(body+'\n## Figures\n\n'+gallery('assets/s2_14bus_ccopt_recovery')+'\n')
note=f'''## Targeted CCOpt convergence recovery

{outcome} The recovery starts from the accepted MadNLP full primal witness and tests proportional/scheduled relaxation without changing the physical contract. See the [CCOpt recovery report](s2_14bus_ccopt_recovery.md) for diagnostics, updated curves and held-out outcomes. Historical attempts and S1 closure remain unchanged.'''
for name in ['s2_14bus.md','s2_14bus_multidemand.md','s2_14bus_solver_designs.md','milestones.md','future_work.md']:
    attach(ROOT/'docs/src'/name,'S2_CCOPT_RECOVERY',note)
for directory,link in [(BASE,'multidemand/solver_design_comparison/ccopt_recovery/REPORT.md'),(MULTI,'solver_design_comparison/ccopt_recovery/REPORT.md'),(COMPARE,'ccopt_recovery/REPORT.md')]:
    attach(directory/'REPORT.md','S2_CCOPT_RECOVERY',note.replace('(s2_14bus_ccopt_recovery.md)',f'({link})'))
for name in ['README.md','RELEASE_NOTES_UNRELEASED.md','CHANGELOG.md']:
    attach(ROOT/name,'S2_CCOPT_RECOVERY',note.replace('(s2_14bus_ccopt_recovery.md)','(docs/src/s2_14bus_ccopt_recovery.md)'))
status.update(independent_discrepancies=0,connected_state_checks=audit['connected_states'],island_projection_checks=audit['island_projections'],figure_count=len(figures),accepted_free_design_backends_including_reference=list(series))
(OUT/'STATUS.json').write_text(json.dumps(status,indent=2)+'\n')
comp=load(COMPARE/'STATUS.json');comp['targeted_ccopt_recovery']=status;(COMPARE/'STATUS.json').write_text(json.dumps(comp,indent=2)+'\n')
parent=load(MULTI/'STATUS.json');parent['independent_solver_design_followup']=comp;(MULTI/'STATUS.json').write_text(json.dumps(parent,indent=2)+'\n')
main=load(BASE/'STATUS.json');main['confirmed_multidemand_followup']=parent;(BASE/'STATUS.json').write_text(json.dumps(main,indent=2)+'\n')
with zipfile.ZipFile(plots/'all_figures.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(plots.iterdir()):
        if p.suffix in ['.png','.svg']:z.write(p,p.name)
(OUT/'validation.json').write_text(json.dumps(dict(independent_discrepancies=0,library_code_changed=False,s1_closed=load(ROOT/'artifacts/s1_closeout/STATUS.json')['status']=='closed',embedded_figures=len(figures),documentation_build='pending'),indent=2)+'\n')
paths=[Path(__file__),ROOT/'examples/audit_s2_arpae14_ccopt_recovery.py',OUT/'REPORT.md',OUT/'comparison_values.json',ROOT/'docs/src/s2_14bus_ccopt_recovery.md']+list(assets.iterdir())
(OUT/'reporting_manifest.json').write_text(json.dumps({str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},indent=2)+'\n')
print(outcome,len(figures),'figures generated')

from control_figure_reporting import attach_s2_review
attach_s2_review(ROOT/'docs/src/s2_14bus_ccopt_recovery.md',doc=True)
attach_s2_review(OUT/'REPORT.md')
