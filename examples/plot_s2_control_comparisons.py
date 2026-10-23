"""Overlay original S1 and saved solver controller settings; no optimization."""
from pathlib import Path
import os,json,zipfile,hashlib
os.environ.setdefault('MPLCONFIGDIR','/tmp/s2-arpae14-matplotlib')
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
DATA=ROOT/'artifacts/s2_scopf/ieee14_native'
PLOTS=DATA/'plots';OUT=PLOTS/'comparisons';OUT.mkdir(exist_ok=True)
load=lambda p:json.loads(p.read_text())
NAMES={'Ipopt':'full-designed-ipopt','MadNLP':'full-designed-madnlp','CCOpt':'exact-designed-ccopt'}
STYLE={'Base':dict(color='#374151',ls='--',lw=1.8),
       'Ipopt':dict(color='#2563eb',ls='-',lw=2.4),
       'MadNLP':dict(color='#d97706',ls='-.',lw=1.8),
       'CCOpt':dict(color='#059669',ls=':',lw=2.0)}
MARK={'Ipopt':'o','MadNLP':'^','CCOpt':'x'}
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.spines.top':False,'axes.spines.right':False,'savefig.facecolor':'white'})
studies={k:load(DATA/v/'optimized_input.json')['data'] for k,v in NAMES.items()}
results={k:load(DATA/v/'result.json')['data'] for k,v in NAMES.items()}
base_study=load(DATA/'full-designed-ipopt/input.json')['data'];base=base_study['case']
s1path=ROOT/'artifacts/s1_arpae14_closeout/calibration_reference.json';s1=load(s1path)
entries=[e for e in load(DATA/'catalog.json')['data']['entries'] if e['disposition']=='eligible']
scenarios=['base']+[e['contingency']['id'] for e in entries]
labels={'base':'Base'}
for e in entries:labels[e['contingency']['id']]={'line':'L','transformer':'T','generator':'G'}[e['device_kind']]+str(e['device_id'])
idx={b['id']:i for i,b in enumerate(base['network']['buses'])};gidx={g['id']:i for i,g in enumerate(base['generators'])}
assert all(studies['Ipopt']['case']['controls']==studies['CCOpt']['case']['controls'] for _ in [0])
files=[];curve_data=[];equipment_data=[]

def save(fig,name):
    for suffix in ['png','svg']:
        p=OUT/f'{name}.{suffix}';fig.savefig(p,dpi=180,bbox_inches='tight');files.append(p)
    plt.close(fig)

def q_curve(d,v):
    s=d['schedule'];c=d['capability']
    raw=d['q_at_deadband']+(np.maximum(s['v_db_low']-v,0)-np.maximum(v-s['v_db_high'],0))/d['slope']
    return np.clip(raw,c['q_min'],c['q_max'])*base['base_power']

for a in base['attachments']:
    cid=a['control_id'];gid=a['generator_id'];bus=a['location']['bus_id']
    curves={'Base':base['controls'][cid-1]}|{solver:s['case']['controls'][cid-1] for solver,s in studies.items()}
    lower=min(.9,*[d['schedule']['v_ref']-d['slope']*d['capability']['q_max'] for d in curves.values()])-.005
    upper=max(1.1,*[d['schedule']['v_ref']-d['slope']*d['capability']['q_min'] for d in curves.values()])+.005
    voltage=np.linspace(lower,upper,1800)
    fig,(ax,zoom)=plt.subplots(1,2,figsize=(14.5,6.3),gridspec_kw={'width_ratios':[1.12,1]})
    actual=[]
    row=dict(generator=gid,bus=bus,curves={})
    for solver,d in curves.items():
        span=100*d['slope']*(d['capability']['q_max']-d['capability']['q_min'])
        label=f"{'S1 base' if solver=='Base' else 'CCOpt = Ipopt curve' if solver=='CCOpt' else solver}: {span:.4f}%, Vref={d['schedule']['v_ref']:.6f}"
        ax.plot(voltage,q_curve(d,voltage),label=label,**STYLE[solver])
        row['curves'][solver]=dict(full_Q_span_percent=span,v_ref=d['schedule']['v_ref'],slope=d['slope'])
        if solver=='Base':continue
        for sid in scenarios:
            event=next((c for c in studies[solver]['contingencies'] if c['id']==sid),None)
            if event and gid in event['generator_ids']:continue
            state=results[solver]['states'][sid];v=state['vm'][idx[bus]];q=state['qg'][gidx[gid]]*base['base_power']
            actual.append((solver,sid,v,q))
    sv=s1['state']['vm'][idx[bus]];sq=s1['state']['qg'][gidx[gid]]*base['base_power']
    actual_voltage=[x[2] for x in actual]+[sv]
    zl=min(actual_voltage)-.002;zh=max(actual_voltage)+.002
    if zh-zl<.006:
        mid=(zh+zl)/2;zl=mid-.003;zh=mid+.003
    zv=np.linspace(zl,zh,800)
    for solver,d in curves.items():zoom.plot(zv,q_curve(d,zv),**STYLE[solver])
    for solver,sid,v,q in actual:
        for target in (ax,zoom):
            target.scatter([v],[q],marker='*' if sid=='base' else MARK[solver],s=105 if sid=='base' else 19,
                           color=STYLE[solver]['color'],linewidths=.7,alpha=.9 if sid=='base' else .45,zorder=5)
    for target in (ax,zoom):target.scatter([sv],[sq],color=STYLE['Base']['color'],marker='*',s=125,edgecolor='white',linewidth=.7,zorder=7)
    cap=curves['Base']['capability']
    for target in (ax,zoom):
        target.axhline(cap['q_min']*100,color='#b91c1c',ls='--',lw=.75)
        target.axhline(cap['q_max']*100,color='#b91c1c',ls='--',lw=.75)
        target.axvline(.9,color='#b91c1c',ls=':',lw=.8);target.axvline(1.1,color='#b91c1c',ls=':',lw=.8)
        target.grid(alpha=.18);target.set(xlabel=f'Regulated voltage at bus {bus} (pu)',ylabel='Reactive generation Q (MVAr)')
    ax.axvspan(lower,.9,color='#fee2e2',alpha=.5);ax.axvspan(1.1,upper,color='#fee2e2',alpha=.5)
    ax.set(xlim=(lower,upper),title='Full saturated curve · red lines = Q and V bounds')
    ax.legend(loc='lower left',fontsize=8.1)
    zy=np.concatenate([q_curve(d,zv) for d in curves.values()]+[np.array([x[3] for x in actual]+[sq])])
    zmin,zmax=float(zy.min()),float(zy.max());pad=max(.2,(zmax-zmin)*.13)
    zoom.set(xlim=(zl,zh),ylim=(zmin-pad,zmax+pad),title='Operating-region detail · all available-generator states')
    fig.suptitle(f'G{gid} at bus {bus} · original S1 base versus shared S2 droop designs',fontsize=15)
    fig.text(.5,.025,'Base = original S1 8% calibrated curve. Each S2 curve is shared across base + 24 connected outages. Stars = base-case operating points.\nCCOpt uses the Ipopt curve settings exactly; green dots overlay blue. CCOpt operating points can differ. Outaged-generator points are omitted.',ha='center',fontsize=9)
    fig.subplots_adjust(top=.85,bottom=.20,wspace=.23)
    row['ipopt_ccopt_curve_difference_max_MVAr']=float(np.max(abs(q_curve(curves['Ipopt'],voltage)-q_curve(curves['CCOpt'],voltage))))
    assert row['ipopt_ccopt_curve_difference_max_MVAr']==0.
    curve_data.append(row);save(fig,f'droop_G{gid}_solver_comparison')

def equipment_plot(kind,control):
    tap=kind=='tap';key='branch_id' if tap else 'bank_id';did=control[key]
    if tap:
        device=next(b for b in base['network']['branches'] if b['id']==did)
        title=f"Transformer T{did} ({device['from_bus']}–{device['to_bus']})"
        initial=s1['taps'][str(did)];lo,hi=control['lower'],control['upper'];units='Tap ratio (pu)';stem=f'tap_T{did}_solver_comparison'
    else:
        device=next(b for b in base['network']['banks'] if b['id']==did)
        title=f"Shunt bank {did} at bus {device['bus_id']}"
        initial=s1['susceptances'][str(did)];lo,hi=control['lower'],control['upper'];units='Continuous susceptance B (pu)';stem=f'shunt_B{did}_solver_comparison'
    setting='tap_settings' if tap else 'shunt_settings'
    vals={solver:np.array([r[setting][s].get(str(did),np.nan) for s in scenarios]) for solver,r in results.items()}
    assert all(np.array_equal(np.isnan(vals['Ipopt']),np.isnan(v)) for v in vals.values())
    ref=np.full(25,initial);ref[np.isnan(vals['Ipopt'])]=np.nan
    fig,(ax,delta)=plt.subplots(2,1,figsize=(15,8.8),sharex=True,gridspec_kw={'height_ratios':[2.2,1]})
    x=np.arange(25)
    ax.plot(x,ref,label=f'S1 base reference = {initial:.8f}',**STYLE['Base'])
    for solver,v in vals.items():
        ax.plot(x,v,marker=MARK[solver],ms=5,label=solver,**STYLE[solver])
        assert np.all((v[np.isfinite(v)]>=lo-1e-6)&(v[np.isfinite(v)]<=hi+1e-6))
    ax.axhline(lo,color='#b91c1c',ls='--',lw=.9,label=f'Absolute bounds: {lo:.5f}–{hi:.5f}')
    ax.axhline(hi,color='#b91c1c',ls='--',lw=.9)
    pad=(hi-lo)*.10;ax.set_ylim(lo-pad,hi+pad)
    ax.set(ylabel=units,title='Absolute setting by scenario · all four references on one axis')
    ax.legend(loc='upper left',fontsize=9,ncol=2)
    if not tap:
        zoom=ax.inset_axes([.38,.40,.59,.43])
        zoom.plot(x,ref,**STYLE['Base'])
        for solver,v in vals.items():zoom.plot(x,v,marker=MARK[solver],ms=2,**{**STYLE[solver],'lw':1.})
        zoom.set_ylim(-.002,max(float(np.nanmax(v)) for v in vals.values())*1.16)
        zoom.set_title('Settings zoom (0.4 pu upper bound is outside this inset)',fontsize=8)
        zoom.set_xticks([0,5,10,15,20,24],[labels[scenarios[i]] for i in [0,5,10,15,20,24]],fontsize=7)
        zoom.tick_params(axis='y',labelsize=7);zoom.grid(alpha=.18)
    if np.isnan(ref).any():
        for k in np.flatnonzero(np.isnan(ref)):
            for a in (ax,delta):a.axvspan(k-.35,k+.35,color='#e2e8f0',alpha=.8)
            ax.text(k,lo+pad*.2,'Outaged\nno tap',ha='center',fontsize=8,color='#475569')
    for solver,v in vals.items():
        delta.plot(x,v-vals['Ipopt'],marker=MARK[solver],ms=4,label=f'{solver} − Ipopt',**STYLE[solver])
    delta.axhline(0,color='#64748b',lw=.7);delta.ticklabel_format(axis='y',style='sci',scilimits=(0,0))
    delta.set(ylabel='Difference from Ipopt (pu)',xlabel='Base case and each connected eligible contingency')
    delta.legend(loc='best',fontsize=8,ncol=3)
    for a in (ax,delta):a.grid(alpha=.18);a.axvspan(-.35,.35,color='#f1f5f9',zorder=-2)
    delta.set_xticks(x,[labels[s] for s in scenarios],rotation=60,ha='right',fontsize=9)
    fig.suptitle(f'{title} · S1 base reference versus S2 optimized solver settings',fontsize=15)
    fig.text(.5,.025,'The dashed S1 line is the calibration reference, not a solved contingency trajectory. S2 taps/B are corrective and optimized separately in each state.\nCCOpt uses Ipopt-designed droop curves but reoptimizes state/equipment variables. Gaps mark an outaged transformer; no setting is assigned.',ha='center',fontsize=9)
    fig.subplots_adjust(top=.88,bottom=.18,hspace=.16)
    equipment_data.append(dict(kind=kind,id=did,base_reference=initial,lower=lo,upper=hi,
        scenarios=scenarios,values={k:[None if not np.isfinite(v) else float(v) for v in row] for k,row in vals.items()},
        max_abs_difference_from_ipopt={k:float(np.nanmax(abs(row-vals['Ipopt']))) for k,row in vals.items()}))
    save(fig,stem)

for control in base_study['tap_controls']:equipment_plot('tap',control)
for control in base_study['shunt_controls']:equipment_plot('shunt',control)
validation=dict(figures=9,droop_figures=5,tap_figures=3,shunt_figures=1,states_per_equipment_figure=25,
    base_definition='Original S1 calibrated 8% droop and S1 nominal joint-reference tap/bank settings; not source RAW settings or a solved N-1 trajectory',
    ccopt_definition='Exact verification of Ipopt-designed shared curves; CCOpt reoptimizes scenario states and equipment',
    ipopt_ccopt_curves_identical=True,equipment_bounds_valid=True,curves=curve_data,equipment=equipment_data,
    source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__),s1path,DATA/'full-designed-ipopt/input.json',DATA/'catalog.json']+[DATA/name/f for name in NAMES.values() for f in ['result.json','optimized_input.json']]})
(OUT/'comparison_values.json').write_text(json.dumps(validation,indent=2)+'\n')
lines=['# Direct solver comparisons by control','','Five individual generator-droop figures, three transformer-tap figures, and one shunt-bank figure. Each overlays the original S1 base reference, Ipopt, MadNLP, and CCOpt. No optimization was run.','','**CCOpt curves coincide exactly with Ipopt by construction:** CCOpt verifies those curves using the exact complementarity model; it does not independently redesign them. MadNLP supplies an independent shared curve design. All saved operating/equipment values are from optimized-curve S2 runs.','','The S1 base equipment line is a constant calibration reference; it is not a contingency solution. Each S2 tap/bank setting is corrective and varies by state. A gap means the transformer is outaged. Lower panels expose differences from Ipopt. `comparison_values.json` contains exact curve parameters, settings, differences, bounds, and source hashes.','','[Download all comparison figures](control_comparisons.zip)','']
for a in base['attachments']:
    gid=a['generator_id'];name=f'droop_G{gid}_solver_comparison';lines += [f'## G{gid} droop','',f'![G{gid} curves]({name}.png)','',f'[SVG]({name}.svg)','']
for control in base_study['tap_controls']:
    did=control['branch_id'];name=f'tap_T{did}_solver_comparison';lines += [f'## Transformer T{did}','',f'![T{did} taps]({name}.png)','',f'[SVG]({name}.svg)','']
for control in base_study['shunt_controls']:
    did=control['bank_id'];name=f'shunt_B{did}_solver_comparison';lines += [f'## Shunt bank {did}','',f'![Bank {did} settings]({name}.png)','',f'[SVG]({name}.svg)','']
lines+=['Regenerate with `python examples/plot_s2_control_comparisons.py` (matplotlib 3.9.4, numpy 2.2.6).','','Line 11 (7–8) islanding remains excluded from the 24 connected-contingency study.']
(OUT/'README.md').write_text('\n'.join(lines)+'\n')
with zipfile.ZipFile(OUT/'control_comparisons.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in files+[OUT/'README.md',OUT/'comparison_values.json']:z.write(p,p.name)
parent=PLOTS/'README.md';text=parent.read_text();marker='<!-- CONTROL_COMPARISONS -->'
if marker in text:text=text.split(marker)[0].rstrip()+'\n'
text+='\n'+marker+'\n\n## Direct comparison of each individual control\n\n[Five droop, three tap and one shunt comparison figures](comparisons/README.md) overlay S1 base, Ipopt, MadNLP and CCOpt.\n'
parent.write_text(text)
with zipfile.ZipFile(PLOTS/'all_figures.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(PLOTS.rglob('*')):
        if p.is_file() and p.suffix in ['.png','.svg','.json','.md']:z.write(p,p.relative_to(PLOTS))
print('Created 5 droop + 3 tap + 1 shunt comparison figures; CCOpt/Ipopt curves identical; equipment bounds checked.')
