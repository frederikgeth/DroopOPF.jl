"""Compare independently optimized shared droop controllers without replacing history."""
from pathlib import Path
import json,hashlib,shutil,zipfile
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from control_figure_reporting import attach

ROOT=Path(__file__).resolve().parents[1];BASE=ROOT/'artifacts/s2_scopf/ieee14_native';MULTI=BASE/'multidemand';OUT=MULTI/'solver_design_comparison'
load=lambda p:json.loads(p.read_text());data=lambda p:load(p)['data']
summary=load(OUT/'summary.json');audit=load(OUT/'independent_audit.json');status=load(OUT/'STATUS.json')
assert audit['classification_discrepancies']==0
series={'ipopt':dict(directory=MULTI/'design-ipopt',record=load(MULTI/'design-ipopt/summary.json'))}
for solver,name in summary['selected'].items():series[solver]=dict(directory=OUT/name,record=load(OUT/name/'summary.json'))
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
plots=OUT/'plots';plots.mkdir(exist_ok=True);assets=ROOT/'docs/src/assets/s2_14bus_solver_designs';assets.mkdir(parents=True,exist_ok=True)
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
attempt_table='\n'.join(f"| {r['name']} | {r['solver_status']} | {'Pass' if r['accepted'] else 'Unqualified'} | {format(r['nominal_loss_mw'],'.9f') if r['accepted'] else '—'} |" for r in [series['ipopt']['record']]+summary['attempts'])
parameter_table='\n'.join(f"| G{i+1} | {s} | {'Accepted' if row['accepted'] else 'Unqualified iterate'} | {row['full_q_span_slope_percent']:.8f} | {row['v_ref_pu']:.10f} | {row['maximum_curve_difference_from_ipopt_mvar']:.7g} |" for i in range(5) for s,rows in comparisons.items() for row in [rows[i]])
held_table='\n'.join(f"| {r['solver']} | {r['factor']*100:g}% | {r['final']['solver_status']} | {'Pass' if r['accepted'] else 'Unqualified'} |" for r in summary['heldout'])
new_accepted=sorted(summary['selected']);short=f"Accepted free multi-demand designs: **{', '.join(series)}**."
ccrows=[r for r in summary['attempts'] if r['solver']=='ccopt']
ccinfo='; '.join(f"{r['name']}: {r.get('ccopt_diagnostics',{}).get('complementarity_pairs','unavailable')} complementarity pairs" for r in ccrows)
ccoutcome=''
if ccrows:
    finalcc=ccrows[-1]
    blocks=[r for r in audit['connected'] if r['name'].startswith(finalcc['name']+'/')]
    projected=[r for r in audit['islands'] if r['name'].startswith(finalcc['name']+'/')]
    if not finalcc['accepted'] and blocks and all(r['physical_valid'] for r in blocks) and len(projected)==5 and all(r['valid'] for r in projected):
        ccoutcome=f"CCOpt’s final iterate passes the declared physical tolerances in all 125 training states and its five conditional projections, but reaches `{finalcc['solver_status']}` without native optimizer convergence. Its diagnostic nominal loss is {finalcc['nominal_loss_mw']:.9f} MW. It is a physically feasible training candidate, not an accepted optimal design; it is not included in the accepted-design objective/equipment comparisons or held-out qualification."
diagnostic_table=''
for row in summary['attempts']:
    blocks=[r for r in audit['connected'] if r['name'].startswith(row['name']+'/')]
    checks=[c for r in blocks for c in r['checks'] if not c.get('missing')]
    if not checks:continue
    diagnostic_table+=f"| {row['name']} | {sum(not c['valid'] for c in checks)} | {max(c['power_balance_max_pu'] for c in checks):.6g} | {max(c['exact_droop_max_pu'] for c in checks):.6g} | {format(row['complementarity_product_max'],'.6g') if 'complementarity_product_max' in row else '—'} |\n"
body=f'''# S2 independent multi-demand solver designs

{short} These are locally solved designs with physical replay, not global optimality certificates. Failed attempts remain visible below.

## Scope and numerical initialization

The user confirmed the existing equipment configuration for this follow-up: all three taps corrective within source-ratio ±5% bounds; bus 11 bank 3 continuous B in [0,0.4] pu, corrective; no additional movement budget. The S1 Pmin=0/symmetric-Q case, source voltage/angle/Rate-A limits, Pmax-weighted response within each demand, 2–8% full-Q-span droop bounds and calibration ±0.02 pu reference bounds remain unchanged.

Every design master contains 125 AC states: five training demands (90/95/100/105/110%), each with a base state and 24 connected outages. Five slopes and five references are free and shared across the entire master; zero deadband and zero reactive reference remain fixed. The objective is 100% base active loss. Taps and the continuous bank remain free per state.

The new MadNLP and CCOpt primary attempts start from the prior accepted Ipopt multi-demand curves, voltages, dispatch **and corrective equipment values**. A retry starts from its own backend's preceding iterate. They optimize all ten shared parameters freely; they are not frozen-controller evaluations. Droop and equipment coordinates are normalized to their physical bounds. The earlier MadNLP design attempts reset tap/bank starts rather than reusing the full witness. Primary budgets here are 3,000 iterations/120 native seconds, with one 6,000-iteration/300-second retry per backend. Different starts/formulations/budgets prevent interpreting these runs as a controlled solver-speed comparison.

MadNLP uses the smooth native formulation with absolute reactive smoothing 1e-6 pu. CCOpt uses native exact-complementarity scenario models with shared free droop parameters. {ccinfo}. CCOpt diagnostics describe its final relaxed NLP and do not establish original-MPCC stationarity.

## Design outcomes

| Attempt | Native status | Physical/native acceptance | Nominal loss MW |
|---|---|---|---:|
{attempt_table}

| New attempt | Physically invalid training states / 125 | Max AC residual pu | Max exact-droop residual pu | Max complementarity product |
|---|---:|---:|---:|---:|
{diagnostic_table}

{ccoutcome}

Ipopt is the historical accepted multi-demand design; its numerical artifacts are unchanged. Failed native statuses or physical violations are not accepted as alternative optimal curves. `comparison_values.json` contains controller values with explicit acceptance flags and accepted-design training-state equipment settings. If a backend remains unqualified, its final curve is included only as a clearly marked diagnostic iterate; objective and equipment comparisons use accepted designs only.

## Shared droop parameter comparison

| Generator | Design backend | Qualification | Full-Q-span slope % | Vref pu | Max curve ΔQ vs Ipopt MVAr |
|---|---|---|---:|---:|---:|
{parameter_table}

The curve difference is evaluated over 0.90–1.12 pu voltage, including all saturation breakpoints. Multiple parameter sets can give nearly identical nominal losses because the other training states have feasibility constraints without objective weights. This comparison alone does not prove uniqueness or a continuum of global optima.

## Held-out qualification

Each newly accepted controller is frozen and checked on its own backend at 92.5/97.5/102.5/107.5% demand; none of those conditions enters design. Training-state acceptance and held-out outcomes are reported separately.

| Controller/backend | Held-out demand | Native status | Combined acceptance |
|---|---:|---|---|
{held_table}

The line 7–8 outage retains the previously confirmed G5-trip and unloaded-bus8-disconnection assumption. Its G5-outage witness is projected to the retained 13-bus network and checked independently; protection and dynamics are outside this claim. Passing sampled demands does not establish a continuous demand envelope.

## Independent verification

Independent Python replay checks **{audit['connected_states']} connected-state records** and **{audit['island_projections']} conditional projections**, with **zero classification discrepancies**. This includes rejected attempts where present. The audit verifies all run hashes, five-demand shared-curve identity, design/equipment bounds, exact AC and droop physics, outages, angle/voltage/thermal/P/Q limits, preventive response and nominal master-objective replay. The usual physical tolerances remain unchanged. No library equations or defaults changed, and S1 remains closed.

```sh
julia --project=. examples/s2_arpae14_solver_designs.jl "Explicit confirmation of this campaign configuration"
python3 examples/audit_s2_arpae14_solver_designs.py
python examples/report_s2_arpae14_solver_designs.py
```
'''
def gallery(prefix):return '\n\n'.join(f'![{name}]({prefix}/{name}.png)\n\n{caption}' for name,caption in figures)
(OUT/'REPORT.md').write_text(body+'\n## Figures\n\n'+gallery('plots')+'\n')
(ROOT/'docs/src/s2_14bus_solver_designs.md').write_text(body+'\n## Figures\n\n'+gallery('assets/s2_14bus_solver_designs')+'\n')
note=f'''## Independent MadNLP and CCOpt shared-design follow-up

{short} The new backends optimize their own shared slopes/references from the accepted Ipopt full witness; accepted designs are independently replayed and compared with Ipopt. See the [solver design comparison](s2_14bus_solver_designs.md). Original campaign scores, rejected attempts and S1 closure remain unchanged.'''
for name in ['s2_14bus_multidemand.md','s2_14bus.md','milestones.md','future_work.md']:
    attach(ROOT/'docs/src'/name,'S2_SOLVER_DESIGNS',note)
attach(MULTI/'REPORT.md','S2_SOLVER_DESIGNS',note.replace('(s2_14bus_solver_designs.md)','(solver_design_comparison/REPORT.md)'))
attach(BASE/'REPORT.md','S2_SOLVER_DESIGNS',note.replace('(s2_14bus_solver_designs.md)','(multidemand/solver_design_comparison/REPORT.md)'))
for name in ['README.md','RELEASE_NOTES_UNRELEASED.md','CHANGELOG.md']:
    attach(ROOT/name,'S2_SOLVER_DESIGNS',note.replace('(s2_14bus_solver_designs.md)','(docs/src/s2_14bus_solver_designs.md)'))
status.update(independent_discrepancies=0,connected_state_checks=audit['connected_states'],island_projection_checks=audit['island_projections'],figure_count=len(figures))
feasible_candidates=[]
for solver in ['madnlp','ccopt']:
    attempts=[r for r in summary['attempts'] if r['solver']==solver]
    if not attempts or attempts[-1]['accepted']:continue
    name=attempts[-1]['name'];blocks=[r for r in audit['connected'] if r['name'].startswith(name+'/')]
    projections=[r for r in audit['islands'] if r['name'].startswith(name+'/')]
    if len(blocks)==5 and all(r['physical_valid'] for r in blocks) and len(projections)==5 and all(r['valid'] for r in projections):feasible_candidates.append(solver)
status.update(reference_design_backend='ipopt',accepted_free_design_backends_including_reference=list(series),unconverged_training_feasible_backends=feasible_candidates)
(OUT/'STATUS.json').write_text(json.dumps(status,indent=2)+'\n')
parent=load(MULTI/'STATUS.json');parent['independent_solver_design_followup']=status;(MULTI/'STATUS.json').write_text(json.dumps(parent,indent=2)+'\n')
main=load(BASE/'STATUS.json');main['confirmed_multidemand_followup']=parent;(BASE/'STATUS.json').write_text(json.dumps(main,indent=2)+'\n')
with zipfile.ZipFile(plots/'all_figures.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(plots.iterdir()):
        if p.suffix in ['.png','.svg']:z.write(p,p.name)
(OUT/'validation.json').write_text(json.dumps(dict(independent_discrepancies=0,library_code_changed=False,s1_closed=load(ROOT/'artifacts/s1_closeout/STATUS.json')['status']=='closed',embedded_figures=len(figures),documentation_build='pending'),indent=2)+'\n')
paths=[Path(__file__),ROOT/'examples/audit_s2_arpae14_solver_designs.py',OUT/'REPORT.md',OUT/'comparison_values.json',ROOT/'docs/src/s2_14bus_solver_designs.md']+list(assets.iterdir())
(OUT/'reporting_manifest.json').write_text(json.dumps({str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},indent=2)+'\n')
print(short,len(figures),'figures generated')

from control_figure_reporting import attach_s2_ccopt_recovery
attach_s2_ccopt_recovery(ROOT/'docs/src/s2_14bus_solver_designs.md',doc=True)
attach_s2_ccopt_recovery(OUT/'REPORT.md',link='ccopt_recovery/REPORT.md')
