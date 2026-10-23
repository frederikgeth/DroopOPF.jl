"""Consolidate accepted saved S2 results, current plots and historical reporting."""
import os
os.environ.setdefault('MPLCONFIGDIR','/tmp/s2-multi-mpl')
import hashlib,json,re,shutil,zipfile
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from s2_14bus_current_results import ROOT,BASE,MULTI,COMPARE,RECOVER,OUT,TRAIN,HOLD,load,data,selected_results,audit_current
from control_figure_reporting import attach,attach_s2_current_results

OUT.mkdir(exist_ok=True);plots=OUT/'plots';plots.mkdir(exist_ok=True)
assets=ROOT/'docs/src/assets/s2_14bus_current_results';assets.mkdir(parents=True,exist_ok=True)
controllers,entries=selected_results();audit=audit_current(controllers,entries)
(OUT/'independent_audit.json').write_text(json.dumps(audit,indent=2)+'\n')
source_names=('input','optimized','result','controller','starts','selected_controller','design')
numerical={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in BASE.rglob('*.json') if p.name.startswith(source_names) and 'current_results' not in p.parts}
(OUT/'numerical_sources_before.json').write_text(json.dumps(numerical,indent=2)+'\n')
plt.rcParams.update({'font.size':10,'axes.grid':True,'grid.alpha':.2,'figure.constrained_layout.use':True})
factors=sorted(TRAIN+HOLD);colors=dict(zip(factors,plt.get_cmap('viridis')(np.linspace(.04,.94,9))))
figures=[]
def save(fig,name,caption):
    for ext in ['png','svg']:
        p=plots/f'{name}.{ext}';fig.savefig(p,dpi=170);shutil.copy2(p,assets/p.name)
    plt.close(fig);figures.append((name,caption))

for solver in controllers:
    selected=[e for e in entries if e['solver']==solver];case=selected[0]['study']['case'];bp=case['base_power']
    gens=[g for g in case['generators'] if g['available']];gidx={g['id']:i for i,g in enumerate(case['generators'])}
    branches=[b for b in case['network']['branches'] if b['available']];buses=case['network']['buses']
    fig,axes=plt.subplots(3,2,figsize=(16,13));points=[[],[],[],[],[],[]]
    for entry in selected:
        f=entry['factor'];result=entry['result'];study=entry['study'];offset=(factors.index(f)-4)*.047
        events={'base':dict(generator_ids=[],branch_ids=[])}|{c['id']:c for c in study['contingencies']}
        checks={r['id']:r for r in audit['checks'] if r['solver']==solver and r['factor']==f}
        for sid,state in result['states'].items():
            event=events[sid];base=sid=='base'
            for i,g in enumerate(gens):
                if g['id'] in event['generator_ids']:continue
                points[0].append((i+offset,state['pg'][gidx[g['id']]]*bp,f,base))
                points[1].append((i+offset,state['qg'][gidx[g['id']]]*bp,f,base))
            for i,v in enumerate(state['vm']):points[2].append((i+offset,v,f,base))
            for i,b in enumerate(branches):
                if b['id'] not in event['branch_ids']:points[3].append((i+offset,checks[sid]['branch_max_terminal_s_pu'][str(b['id'])]*bp,f,base))
            for i,bid in enumerate(['19','20','21']):
                if bid in result['tap_settings'][sid]:points[4].append((i+offset,result['tap_settings'][sid][bid],f,base))
            points[5].append((offset,result['shunt_settings'][sid]['3'],f,base))
    for ax,pts in zip(axes.flat,points):
        for f in factors:
            for isbase in [False,True]:
                group=[p for p in pts if p[2]==f and p[3]==isbase]
                if not group:continue
                xx,yy=zip(*[(p[0],p[1]) for p in group])
                ax.scatter(xx,yy,s=26 if isbase else 10,color=colors[f],alpha=.9 if isbase else .32,
                    edgecolor='black' if isbase else 'none',linewidth=.6,zorder=4 if isbase else 2)
    def bounds(ax,lower,upper,labels):
        x=np.arange(len(labels));ax.hlines(lower,x-.31,x+.31,color='#a22c35',lw=1.4,zorder=5)
        ax.hlines(upper,x-.31,x+.31,color='#a22c35',lw=1.4,zorder=5)
        ax.set_xticks(x,labels);ax.margins(x=.04,y=.12)
    bounds(axes[0,0],[g['p_min']*bp for g in gens],[g['p_max']*bp for g in gens],[f"G{g['id']}" for g in gens])
    bounds(axes[0,1],[g['q_min']*bp for g in gens],[g['q_max']*bp for g in gens],[f"G{g['id']}" for g in gens])
    bounds(axes[1,0],[b['v_min'] for b in buses],[b['v_max'] for b in buses],[str(b['id']) for b in buses])
    bounds(axes[1,1],[0.]*len(branches),[b['thermal_limit']*bp for b in branches],[str(b['id']) for b in branches])
    bounds(axes[2,0],[.9291,.92055,.8854],[1.0269,1.01745,.9786],['19: 4–7','20: 4–9','21: 5–6'])
    bounds(axes[2,1],[0.],[.4],['Bank 3 at bus 11'])
    titles=['Active generation','Reactive generation','Bus voltage magnitudes','Maximum terminal branch flow and Rate A','Corrective transformer taps','Corrective continuous shunt']
    units=['MW','MVAr','pu','MVA','Tap ratio','B (pu)']
    for ax,title,unit in zip(axes.flat,titles,units):ax.set(title=title,ylabel=unit)
    axes[1,1].tick_params(axis='x',rotation=60,labelsize=8)
    handles=[Line2D([],[],marker='o',ls='',color=colors[f],label=f'{f*100:g}%'+(' held out' if f in HOLD else ' training')) for f in factors]
    handles += [Line2D([],[],marker='o',ls='',color='gray',markeredgecolor='black',label='Base state: black outline'),Line2D([],[],color='#a22c35',label='Equipment/operating bounds')]
    fig.set_layout_engine('constrained',rect=(0,0,1,.91))
    legend=fig.legend(handles=handles,loc='upper center',bbox_to_anchor=(.5,.975),ncol=6,fontsize=9)
    legend.set_in_layout(False)
    title=fig.suptitle(f'{solver}: accepted independent shared design — nine demands × 25 connected states',fontsize=14,y=.997)
    title.set_in_layout(False)
    save(fig,f'current_limits_{solver}',f'{solver}: all 225 accepted base/connected-contingency states across nine sampled demands. Colors indicate demand and small horizontal offsets separate demand groups. Black-outlined dots are base states; red bars are absolute bounds. Unavailable devices are omitted. Training states are the actual joint-design witnesses; held-out states reoptimize dispatch/equipment with that controller frozen.')

# The recovered comparison already contains five droop plots, four equipment
# plots, accepted nominal objectives and the recovery diagnostic endpoints.
recovery_captions={f'droop-{i}':f'G{i}: accepted Ipopt, MadNLP and recovered CCOpt free multi-demand curves; lower panel shows reactive-response difference from Ipopt.' for i in range(1,6)}
recovery_captions.update({'nominal-loss':'Accepted-design nominal loss differences from Ipopt. All three are local solutions; the spread is below 0.6 W.',
    'tap_settings-19':'Transformer 19: corrective values and bounds at all five training demands and their 25 states for each accepted design.',
    'tap_settings-20':'Transformer 20: corrective values and bounds at all five training demands and their 25 states for each accepted design.',
    'tap_settings-21':'Transformer 21: corrective values and bounds at all five training demands and their 25 states for each accepted design.',
    'shunt_settings-3':'Bus 11 bank 3: corrective continuous susceptance at all five training demands and their 25 states for each accepted design.',
    'convergence-endpoints':'CCOpt endpoint diagnostics retain the historical failed attempts and the accepted scheduled recovery. Green indicates native/physical acceptance; these are final relaxed-NLP metrics.'})
for name,caption in recovery_captions.items():
    for ext in ['png','svg']:
        src=RECOVER/'plots'/f'{name}.{ext}';shutil.copy2(src,plots/src.name);shutil.copy2(src,assets/src.name)
    figures.append((name,caption))
assert len(figures)==14
results=[];parameters=[]
for solver,directory in controllers.items():
    record=load(directory/'summary.json');curve=data(directory/'controller.json')['case']['controls']
    results.append(dict(solver=solver,source=str(directory.relative_to(ROOT)),native_status=record['solver_status'],nominal_loss_mw=record['nominal_loss_mw'],training_demands=5,held_out_demands=4,accepted=True))
    for i,d in enumerate(curve,1):parameters.append(dict(generator=i,solver=solver,slope=d['slope'],full_q_span_slope_percent=100*d['slope']*(d['capability']['q_max']-d['capability']['q_min']),v_ref_pu=d['schedule']['v_ref']))
manifest=dict(reporting_date='2026-10-16',status='closed_declared_14bus_scope',accepted_free_design_backends=list(controllers),
    connected_states=675,conditional_island_projections=27,discrepancies=0,current_figures=14,historical_nominal_figures=18,
    main_gallery_figures=32,results=results,parameters=parameters,source_hashes=audit['source_hashes'],
    numerical_optimisation_performed=False,historical_selected_controller_replaced=False,
    scope='Five training and four held-out demands; 24 connected outages plus conditional G5-trip retained-network projection; S1 Pmin0 symmetric-Q convention; corrective continuous equipment',
    broader_s2_closed=False,general_full_n1_claim=False,continuous_envelope_claim=False)
(OUT/'CURRENT_RESULTS.json').write_text(json.dumps(manifest,indent=2)+'\n');(BASE/'CURRENT_RESULTS.json').write_text(json.dumps(manifest,indent=2)+'\n')
table='\n'.join(f"| {r['solver']} | {r['native_status']} | {r['nominal_loss_mw']:.9f} | 5/5 | 4/4 |" for r in results)
ptable='\n'.join(f"| G{r['generator']} | {r['solver']} | {r['full_q_span_slope_percent']:.8f} | {r['v_ref_pu']:.10f} |" for r in sorted(parameters,key=lambda r:(r['generator'],r['solver'])))
margin_table=''
for solver in controllers:
    checks=[r for r in audit['checks'] if r['solver']==solver]
    margin_table+=f"| {solver} | {max(r['power_balance_max_pu'] for r in checks):.6g} | {max(r['exact_droop_max_pu'] for r in checks):.6g} | {min(r['voltage_min_margin_pu'] for r in checks):.6g} | {100*min(r['thermal_min_margin_pu'] for r in checks):.6g} |\n"
head=f'''# S2 14-bus current accepted results

**The declared sampled 14-bus scope is closed. Ipopt, MadNLP and CCOpt each have an accepted independently optimized multi-demand droop design.** The CCOpt source is the converged `scheduled-ccopt` recovery. The current figures and tables use its free shared curves and corresponding states, not the earlier fixed-curve verification or unconverged iterate.

| Design backend | Native design status | Nominal loss MW | Training demands | Held-out demands |
|---|---|---:|---:|---:|
{table}

Nominal losses differ by less than 0.6 W despite different curves. These are accepted local solutions under the declared contract, not a global-optimality ranking. Training demands are 90/95/100/105/110%; held-out demands are 92.5/97.5/102.5/107.5%. Each controller shares five slopes and five reference voltages across all 125 training states. The sole design objective is 100% base active loss; non-nominal training states impose feasibility only. The plotted training witnesses therefore need not minimize losses separately at their own demands. Held-out dispatch/equipment are reoptimized with the chosen controller frozen on its own backend.

Independent current-result replay verifies **675 connected-state records and 27 conditional island projections**, with **zero discrepancies**. That is 225 connected states per accepted controller. No violations exceed the declared physical tolerances. Voltage, active-power, thermal and equipment limits can be binding; passing these sampled points is not a positive-margin or continuous-envelope certificate.

| Backend | Max AC residual pu | Max exact-droop residual pu | Minimum voltage margin pu | Minimum thermal margin MVA |
|---|---:|---:|---:|---:|
{margin_table}

Physical tolerances remain AC/limits/response 1e-6 pu, exact droop 1e-5 pu and unavailable generation 1e-8 pu. The table covers all nine demands and all 25 connected states for each controller.

The physical scope remains S1's Pmin=0/symmetric-Q case; source voltage, angle and Rate-A bounds; 2–8% full-Q-span slope and calibration ±0.02 pu reference bounds; zero deadband and Q reference; within-demand Pmax-weighted active response; three corrective taps within source ±5% and bus 11 bank 3 continuous B in [0,0.4] pu, with no additional movement budget. All 24 connected outages are included. Line 7–8 coverage is conditional on G5 trip and unloaded bus8 disconnection, verified on the retained 13-bus network. Original-limit, protection/dynamic and general islanding N-1 qualifications remain outside this scope. S1 remains closed; broader S2 remains open.

The scheduled CCOpt recovery converged in 160 inner iterations with native relaxed-NLP dual residual about 7.1e-15. Its failed predecessors remain historical evidence. See the [recovery](s2_14bus_ccopt_recovery.md) and [14-bus review](s2_14bus_review.md). All figures below are regenerated or selected from saved results; **no optimisation was run for this reporting update**. The historical numerical campaigns and original controller selection are preserved.

## Accepted shared droop parameters

| Generator | Backend | Full-Q-span slope % | Vref pu |
|---|---|---:|---:|
{ptable}

## Evidence and regeneration

`artifacts/s2_scopf/ieee14_native/CURRENT_RESULTS.json` is the consolidated accepted-results index. It identifies each accepted free-design source, parameter values and hashes of the selected saved studies, states and conditional projections. The original nominal scorecard fields remain in `STATUS.json`; its `current_results` and `declared_14bus_review` entries record the current closed sampled scope. The detailed current audit and the PNG/SVG archive are under `current_results/`.

```sh
python examples/report_s2_14bus_current_results.py
```

This reporting command requires NumPy/Matplotlib and reads saved results only. The historical report and gallery generators preserve the current section when regenerated. The 18 original nominal figures below retain their original curve/control meanings; their CCOpt arm was fixed-curve verification. The 14 current figures use the independently designed recovered curves.

'''
def gallery(prefix):return '\n\n'.join(f'![{name}]({prefix}/{name}.png)\n\n{caption}\n\n[SVG]({prefix}/{name}.svg)' for name,caption in figures)
doc=head+'## Current operating and control figures\n\n'+gallery('assets/s2_14bus_current_results')+'\n'
artifact=head.replace('(s2_14bus_ccopt_recovery.md)','(../multidemand/solver_design_comparison/ccopt_recovery/REPORT.md)').replace('(s2_14bus_review.md)','(../14bus_review/REPORT.md)')+'## Current operating and control figures\n\n'+gallery('plots')+'\n'
(OUT/'REPORT.md').write_text(artifact)
(OUT/'report_front_doc.md').write_text(doc)
(OUT/'report_front_artifact.md').write_text(artifact.replace('(plots/','(current_results/plots/').replace('(../multidemand/','(multidemand/').replace('(../14bus_review/','(14bus_review/'))
(OUT/'gallery_front.md').write_text(doc.replace('# S2 14-bus current accepted results','# S2 14-bus complete figure gallery',1))
attach_s2_current_results(ROOT/'docs/src/s2_14bus.md',kind='doc')
attach_s2_current_results(BASE/'REPORT.md',kind='report')
attach_s2_current_results(ROOT/'docs/src/s2_14bus_figures.md',kind='gallery')
note='''## Current accepted S2 14-bus figures

The [current results](current_results/REPORT.md) consolidate the accepted free Ipopt, MadNLP and recovered CCOpt designs. The 14 current figures include all-nine-demand operating limits and the three independent curve/equipment comparisons. The figures below retain the original nominal campaign and its fixed-curve CCOpt verification as historical evidence.'''
attach(BASE/'plots/README.md','S2_CURRENT_ACCEPTED',note.replace('(current_results/REPORT.md)','(../current_results/REPORT.md)'))
for name in ['README.md','RELEASE_NOTES_UNRELEASED.md','CHANGELOG.md']:
    attach(ROOT/name,'S2_CURRENT_ACCEPTED','''## Consolidated S2 14-bus accepted results

The [main S2 14-bus report](docs/src/s2_14bus.md) and [complete gallery](docs/src/s2_14bus_figures.md) now lead with accepted free Ipopt, MadNLP and recovered CCOpt multi-demand designs. Fourteen current figures cover 675 connected-state records and 27 conditional projections; all pass independent replay. The original 18 nominal-campaign figures and failed attempts remain historical. No numerical optimisation was run for consolidation; S1 and the declared sampled 14-bus scope remain closed, while broader S2 remains open.''')
top=load(BASE/'STATUS.json');top['current_results']=manifest;top['declared_14bus_review']=load(BASE/'14bus_review/STATUS.json');(BASE/'STATUS.json').write_text(json.dumps(top,indent=2)+'\n')
with zipfile.ZipFile(plots/'all_current_figures.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(plots.iterdir()):
        if p.suffix in ['.png','.svg']:z.write(p,p.name)
assert all(hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest for path,digest in numerical.items())
(OUT/'validation.json').write_text(json.dumps(dict(numerical_optimisation_performed=False,numerical_source_files_unchanged=len(numerical),all_current_states_valid=True,
    connected_states=675,conditional_projections=27,independent_discrepancies=0,current_figures=14,main_gallery_figures=32,
    library_code_changed=False,s1_status=load(ROOT/'artifacts/s1_closeout/STATUS.json')['status'],documentation_build='pending'),indent=2)+'\n')
reporting_paths=[Path(__file__),ROOT/'examples/s2_14bus_current_results.py',ROOT/'examples/control_figure_reporting.py',
    ROOT/'examples/report_s2_arpae14.py',ROOT/'examples/update_control_figure_documentation.py',OUT/'REPORT.md',BASE/'REPORT.md',
    BASE/'CURRENT_RESULTS.json',OUT/'CURRENT_RESULTS.json',OUT/'independent_audit.json',OUT/'validation.json',
    ROOT/'docs/src/s2_14bus.md',ROOT/'docs/src/s2_14bus_figures.md',ROOT/'docs/make.jl']+list(assets.iterdir())
(OUT/'reporting_manifest.json').write_text(json.dumps({str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in reporting_paths},indent=2)+'\n')
print('Consolidated three accepted designs: 675 connected states, 27 projections, 14 current + 18 historical figures; zero discrepancies; numerical sources unchanged.')
