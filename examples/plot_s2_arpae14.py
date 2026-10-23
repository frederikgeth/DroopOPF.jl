"""Scientific limit and controller plots for every retained full S2 master.

Reads saved data only; independently recomputes both branch terminal flows.
No SCOPF optimization is started. Outaged devices are marked, not tested
against their in-service bounds. All 24 connected eligible outages are shown.
"""
from pathlib import Path
import os
os.environ.setdefault('MPLCONFIGDIR','/tmp/s2-arpae14-matplotlib')
import json, cmath, hashlib, zipfile
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
DATA=ROOT/'artifacts/s2_scopf/ieee14_native'
OUT=DATA/'plots';OUT.mkdir(exist_ok=True)
load=lambda p:json.loads(p.read_text())
protocol=load(DATA/'protocol.json');catalog=load(DATA/'catalog.json')['data']['entries']
entries=[e for e in catalog if e['disposition']=='eligible']
SCENARIOS=['base']+[e['contingency']['id'] for e in entries]
LABELS={'base':'Base'}
LONG={'base':'Base case'}
for e in entries:
    key=e['contingency']['id'];prefix={'line':'L','transformer':'T','generator':'G'}[e['device_kind']]
    LABELS[key]=prefix+str(e['device_id'])
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.spines.top':False,
                     'axes.spines.right':False,'savefig.facecolor':'white','figure.dpi':120})
COLORS=np.vstack(([0.04,0.06,0.10,1.],plt.get_cmap('turbo')(np.linspace(.03,.97,24))))
COLOR=dict(zip(SCENARIOS,COLORS))
LANES={'ipopt':{'frozen':'full-frozen-ipopt','designed':'full-designed-ipopt'},
       'madnlp':{'frozen':'full-frozen-madnlp','designed':'full-designed-madnlp'},
       'ccopt':{'frozen':'exact-frozen-ccopt','designed':'exact-designed-ccopt'}}
SOLVER={'ipopt':'Ipopt','madnlp':'MadNLP','ccopt':'CCOpt (exact; Ipopt-designed curves frozen)'}
files=[];metrics=[];datasets={}

def read_lane(name):
    study=load(DATA/name/'optimized_input.json')['data'];result=load(DATA/name/'result.json')['data']
    assert set(result['states'])==set(SCENARIOS)
    return study,result

def branch_flow(branch,state,idx,taps):
    i,j=idx[branch['from_bus']],idx[branch['to_bus']]
    vf=cmath.rect(state['vm'][i],state['va'][i]);vt=cmath.rect(state['vm'][j],state['va'][j])
    t=cmath.rect(taps.get(str(branch['id']),branch['tap_ratio']),branch['phase_shift'])
    y=1/complex(branch['resistance'],branch['reactance']);yc=complex(0,branch['charging']/2)
    sf=vf*(((y+yc)/abs(t)**2*vf-y/t.conjugate()*vt).conjugate())
    st=vt*(((y+yc)*vt-y/t*vf).conjugate())
    return max(abs(sf),abs(st))

def collect(study,result):
    c=study['case'];buses=c['network']['buses'];gens=[g for g in c['generators'] if g['available']]
    branches=[b for b in c['network']['branches'] if b['available']]
    idx={b['id']:i for i,b in enumerate(buses)};gidx={g['id']:i for i,g in enumerate(c['generators'])}
    outages={'base':dict(branch_ids=[],generator_ids=[])}|{e['id']:e for e in study['contingencies']}
    P=[];Q=[];V=[];S=[];available_g=[];available_b=[]
    for sid in SCENARIOS:
        state=result['states'][sid]
        P.append([state['pg'][gidx[g['id']]]*c['base_power'] for g in gens])
        Q.append([state['qg'][gidx[g['id']]]*c['base_power'] for g in gens])
        V.append(state['vm'])
        ag=[g['id'] not in outages[sid]['generator_ids'] for g in gens]
        ab=[b['id'] not in outages[sid]['branch_ids'] for b in branches]
        available_g.append(ag);available_b.append(ab)
        S.append([branch_flow(b,state,idx,result['tap_settings'][sid])*c['base_power'] if a else np.nan for b,a in zip(branches,ab)])
    return dict(study=study,result=result,c=c,buses=buses,gens=gens,branches=branches,idx=idx,gidx=gidx,
                P=np.array(P),Q=np.array(Q),V=np.array(V),S=np.array(S),ag=np.array(available_g),ab=np.array(available_b))

for solver,lanes in LANES.items():
    datasets[solver]={arm:collect(*read_lane(name)) for arm,name in lanes.items()}
c=datasets['ipopt']['frozen']['c']
for e in entries:
    sid=e['contingency']['id']
    if e['device_kind']=='generator':
        g=next(g for g in c['generators'] if g['id']==e['device_id']);LONG[sid]=f"G{g['id']} off @ bus {g['bus_id']}"
    else:
        b=next(b for b in c['network']['branches'] if b['id']==e['device_id']);LONG[sid]=f"{LABELS[sid]} off: {b['from_bus']}–{b['to_bus']}"

def save(fig,name):
    for extension in ['png','svg']:
        path=OUT/f'{name}.{extension}';fig.savefig(path,dpi=160,bbox_inches='tight');files.append(path)
    plt.close(fig)

def legend(ax,extra=None):
    ax.axis('off')
    handles=[Line2D([],[],marker='*' if s=='base' else 'o',linestyle='',color=COLOR[s],markersize=9 if s=='base' else 5,label=LONG[s]) for s in SCENARIOS]
    if extra:handles+=extra
    ax.legend(handles=handles,loc='center',ncol=5,fontsize=8.5,frameon=False,handletextpad=.4,columnspacing=1.9)

def points(ax,values,available=None,base=True):
    n=values.shape[1]
    for k,sid in enumerate(SCENARIOS):
        off=(k-12)*.024
        mask=np.isfinite(values[k])
        if available is not None:mask &= available[k]
        if sid=='base':
            ax.scatter(np.arange(n)[mask]+off,values[k,mask],s=105,marker='*',color=COLOR[sid],edgecolor='white',linewidth=.6,zorder=6)
        else:
            ax.scatter(np.arange(n)[mask]+off,values[k,mask],s=18,color=COLOR[sid],alpha=.85,zorder=4)
        if available is not None:
            missing=~available[k]
            if missing.any():ax.scatter(np.arange(n)[missing]+off,np.zeros(missing.sum()),marker='x',s=24,color=COLOR[sid],zorder=5)
    ax.set_xlim(-.6,n-.4);ax.grid(axis='y',alpha=.18)

def bounds(ax,lower,upper):
    x=np.arange(len(lower));ax.vlines(x,lower,upper,color='#e2e8f0',lw=18,zorder=0)
    ax.scatter(x,lower,marker='_',s=310,color='#b91c1c',linewidth=1.5,zorder=2)
    ax.scatter(x,upper,marker='_',s=310,color='#b91c1c',linewidth=1.5,zorder=2)

def values_and_violations(d):
    bm=d['c']['base_power'];tol=1e-6
    pmin=np.array([g['p_min']*bm for g in d['gens']]);pmax=np.array([g['p_max']*bm for g in d['gens']])
    qmin=np.array([g['q_min']*bm for g in d['gens']]);qmax=np.array([g['q_max']*bm for g in d['gens']])
    vlo=np.array([b['v_min'] for b in d['buses']]);vhi=np.array([b['v_max'] for b in d['buses']])
    ratings=np.array([b['thermal_limit']*bm for b in d['branches']])
    violations=[];raw_overshoots=[]
    for key,val,lo,hi,mask,units,threshold in [('P',d['P'],pmin,pmax,d['ag'],'MW',tol*bm),('Q',d['Q'],qmin,qmax,d['ag'],'MVAr',tol*bm),('V',d['V'],vlo,vhi,np.ones_like(d['V'],bool),'pu',tol),('S',d['S'],np.zeros_like(ratings),ratings,d['ab'],'MVA',tol*bm)]:
        violation=np.maximum(lo-val,val-hi)
        for si,di in np.argwhere(mask & (violation>0)):
            item=dict(quantity=key,scenario=SCENARIOS[si],device_index=int(di),excess=float(violation[si,di]),units=units,tolerance=threshold)
            raw_overshoots.append(item)
            if violation[si,di]>threshold:violations.append(item)
    return dict(pmin=pmin,pmax=pmax,qmin=qmin,qmax=qmax,vlo=vlo,vhi=vhi,ratings=ratings,violations=violations,raw_overshoots=raw_overshoots)

def dashboard(solver,arm,d):
    lim=values_and_violations(d);bm=d['c']['base_power']
    fig=plt.figure(figsize=(21,17));gs=fig.add_gridspec(4,2,height_ratios=[1,1,1,.32],hspace=.43,wspace=.18)
    axes=[fig.add_subplot(gs[i,j]) for i in range(3) for j in range(2)]
    gpq=np.empty((25,len(d['gens'])*2));gpq[:,0::2]=d['P'];gpq[:,1::2]=d['Q']
    lower=np.column_stack((lim['pmin'],lim['qmin'])).ravel();upper=np.column_stack((lim['pmax'],lim['qmax'])).ravel()
    bounds(axes[0],lower,upper);points(axes[0],gpq,np.repeat(d['ag'],2,axis=1))
    axes[0].axhline(0,color='#64748b',lw=.6)
    axes[0].set_xticks(np.arange(len(lower)),[f"G{g['id']} P\nbus {g['bus_id']}" if k==0 else f"G{g['id']} Q\nbus {g['bus_id']}" for g in d['gens'] for k in [0,1]],fontsize=8)
    axes[0].set(ylabel='P (MW) / Q (MVAr)',title='Generation and capability bounds · × = generator outaged')
    bounds(axes[1],lim['vlo'],lim['vhi']);points(axes[1],d['V'])
    axes[1].set_xticks(np.arange(len(d['buses'])),[str(b['id']) for b in d['buses']])
    axes[1].set(xlabel='Bus',ylabel='Voltage magnitude (pu)',title='Voltage magnitudes and source bounds')
    branchlabels=[f"{'T' if b['kind']=='transformer' else 'L'}{b['id']}\n{b['from_bus']}–{b['to_bus']}" for b in d['branches']]
    bounds(axes[2],np.zeros(len(d['branches'])),lim['ratings']);points(axes[2],d['S'],d['ab'])
    axes[2].set_xticks(np.arange(len(branchlabels)),branchlabels,fontsize=7)
    axes[2].set(ylabel='max(|S from|, |S to|) (MVA)',title='Both-terminal apparent flow and Rate-A ratings · × = outaged')
    loading=d['S']/lim['ratings']*100
    points(axes[3],loading,d['ab']);axes[3].axhline(100,color='#b91c1c',ls='--',lw=1.6,label='100% of Rate A')
    axes[3].set_xticks(np.arange(len(branchlabels)),branchlabels,fontsize=7)
    axes[3].set(ylabel='Loading (% of source Rate A)',title='Normalized flow · reveals stress on small-rated branches')
    axes[3].legend(loc='lower right',fontsize=9);axes[3].set_ylim(-5,105)
    x=np.arange(25);cols=['#2563eb','#d97706','#7c3aed']
    tapvalues={};tap_violations=[]
    for control,col in zip(d['study']['tap_controls'],cols):
        bid=control['branch_id'];b=next(b for b in d['branches'] if b['id']==bid)
        vals=np.array([d['result']['tap_settings'][s].get(str(bid),np.nan) for s in SCENARIOS])
        axes[4].plot(x,vals,'o-',ms=3,lw=1.1,color=col,label=f"T{bid} ({b['from_bus']}–{b['to_bus']})")
        axes[4].axhline(control['lower'],color=col,ls='--',lw=.8,alpha=.65);axes[4].axhline(control['upper'],color=col,ls='--',lw=.8,alpha=.65)
        axes[4].scatter(x[np.isnan(vals)],np.full(np.isnan(vals).sum(),control['nominal']),marker='x',s=50,color=col)
        tapvalues[str(bid)]={s:None if np.isnan(v) else float(v) for s,v in zip(SCENARIOS,vals)}
        for i,v in enumerate(vals):
            if np.isfinite(v) and not control['lower']-1e-6<=v<=control['upper']+1e-6:tap_violations.append(dict(id=bid,scenario=SCENARIOS[i],value=float(v)))
    axes[4].set(title='Transformer taps · dashed = bounds; × = outaged, no setting',ylabel='Tap ratio (pu)')
    axes[4].legend(fontsize=8,ncol=3,loc='upper left')
    bankvalues={};bank_violations=[]
    for control in d['study']['shunt_controls']:
        bid=control['bank_id'];b=next(b for b in d['c']['network']['banks'] if b['id']==bid)
        vals=np.array([d['result']['shunt_settings'][s][str(bid)] for s in SCENARIOS])
        if control['lower'] is None:
            legal=[sum(a*b for a,b in zip(b['step_susceptances'],state)) for state in b['legal_states']];lo,hi=min(legal),max(legal)
        else:lo,hi=control['lower'],control['upper']
        axes[5].plot(x,vals,'o-',color='#059669',ms=4,lw=1.2,label=f"Bank {bid} at bus {b['bus_id']}")
        axes[5].axhline(lo,color='#b91c1c',ls='--',lw=1);axes[5].axhline(hi,color='#b91c1c',ls='--',lw=1,label=f'Bounds: {lo:g}–{hi:g} pu')
        axes[5].set_ylim(lo-.025,hi+.025)
        bankvalues[str(bid)]={s:float(v) for s,v in zip(SCENARIOS,vals)}
        for i,v in enumerate(vals):
            if not lo-1e-6<=v<=hi+1e-6:bank_violations.append(dict(id=bid,scenario=SCENARIOS[i],value=float(v)))
    zoom=axes[5].inset_axes([.36,.43,.60,.40])
    for bid,settings in bankvalues.items():
        vv=np.array(list(settings.values()))
        zoom.plot(x,vv,'o-',color='#059669',ms=2,lw=.8)
        zoom.set_ylim(min(0,float(vv.min()))-.002,max(.008,float(vv.max())*1.2))
    zoom.axhline(0,color='#b91c1c',ls='--',lw=.6)
    zoom.set_xticks([0,5,10,15,20,24],[LABELS[SCENARIOS[i]] for i in [0,5,10,15,20,24]],fontsize=6)
    zoom.tick_params(axis='y',labelsize=6);zoom.set_title('Settings detail (upper bound 0.4 pu outside zoom)',fontsize=7)
    zoom.grid(alpha=.15)
    axes[5].set(title='Continuous shunt-bank settings · not discrete steps',ylabel='Susceptance B (pu on 100 MVA base)')
    axes[5].legend(fontsize=9,loc='upper left')
    for ax in axes[4:]:
        ax.set_xticks(x,[LABELS[s] for s in SCENARIOS],rotation=70,fontsize=8);ax.set_xlabel('Scenario (outage ID; all 24 eligible events)');ax.grid(alpha=.18)
        ax.axvspan(-.4,.4,color='#e2e8f0',alpha=.7,zorder=-1)
    n=len(lim['violations'])+len(tap_violations)+len(bank_violations)
    fig.suptitle(f"14-bus S2 · {SOLVER[solver]} · {'original frozen 8% curves' if arm=='frozen' else 'optimized shared droop curves'}\nBase + 24 connected outages · corrective taps/bank · limit violations beyond tolerance: {n}",fontsize=16,y=.985)
    legend(fig.add_subplot(gs[3,:]))
    fig.text(.5,.008,'Red caps = equipment/operating bounds. Colored points = every saved state; black star = base. Outaged device values are marked ×, not treated as in-service.\nTolerance: power/ratings 0.0001 MW/MVAr/MVA, voltage/taps/B 1e-6 pu. Line 11 (7–8) islanding outage is excluded from this study.',ha='center',fontsize=9)
    fig.subplots_adjust(top=.91,bottom=.08,left=.065,right=.98)
    save(fig,f'{solver}_{arm}_all_states')
    metrics.append(dict(solver=solver,arm=arm,violations=lim['violations'],raw_bound_exceedances=lim['raw_overshoots'],
                        tap_violations=tap_violations,shunt_violations=bank_violations,taps=tapvalues,shunts=bankvalues,
                        max_branch_loading_percent=float(np.nanmax(loading))))

def droop_plot(solver):
    original=datasets[solver]['frozen'];designed=datasets[solver]['designed']
    fig=plt.figure(figsize=(20,16));gs=fig.add_gridspec(4,2,height_ratios=[1,1,1,.30],hspace=.37,wspace=.20)
    axes=[fig.add_subplot(gs[i,j]) for i in range(3) for j in range(2)]
    for ai,g in enumerate(original['gens']):
        ax=axes[ai];attachment=next(a for a in original['c']['attachments'] if a['generator_id']==g['id'])
        cid=attachment['control_id'];bus=attachment['location']['bus_id'];curves=[d['c']['controls'][cid-1] for d in [original,designed]]
        lo=min(.9,*[d['schedule']['v_ref']-d['slope']*d['capability']['q_max'] for d in curves])-.005
        hi=max(1.1,*[d['schedule']['v_ref']-d['slope']*d['capability']['q_min'] for d in curves])+.005
        voltage=np.linspace(lo,hi,1300)
        for di,(data,d) in enumerate(zip([original,designed],curves)):
            cap=d['capability'];sch=d['schedule'];raw=d['q_at_deadband']+(np.maximum(sch['v_db_low']-voltage,0)-np.maximum(voltage-sch['v_db_high'],0))/d['slope']
            q=np.clip(raw,cap['q_min'],cap['q_max'])*100
            span=100*d['slope']*(cap['q_max']-cap['q_min'])
            ax.plot(voltage,q,color='#64748b' if di==0 else '#2563eb',ls='--' if di==0 else '-',lw=2,
                    label=f"{'Original' if di==0 else 'Optimized'}: {span:.3f}%, Vref={sch['v_ref']:.5f}")
            for k,sid in enumerate(SCENARIOS):
                gi=next(i for i,x in enumerate(data['gens']) if x['id']==g['id'])
                if not data['ag'][k,gi]:continue
                state=data['result']['states'][sid];v=state['vm'][data['idx'][bus]];q=state['qg'][data['gidx'][g['id']]]*100
                ax.scatter([v],[q],s=100 if sid=='base' else 28,marker='*' if sid=='base' else 'o',
                    facecolors='none' if di==0 else [COLOR[sid]],edgecolors=[COLOR[sid]],linewidths=1 if di==0 else .5,zorder=5)
        cap=curves[0]['capability']
        ax.axhline(cap['q_min']*100,color='#b91c1c',ls=':',lw=1);ax.axhline(cap['q_max']*100,color='#b91c1c',ls=':',lw=1)
        ax.axvspan(lo,.9,color='#fee2e2',alpha=.5,zorder=-2);ax.axvspan(1.1,hi,color='#fee2e2',alpha=.5,zorder=-2)
        ax.axvline(.9,color='#b91c1c',ls=':',lw=.8);ax.axvline(1.1,color='#b91c1c',ls=':',lw=.8)
        ax.set(xlabel='Regulated bus voltage (pu)',ylabel='Reactive generation Q (MVAr)',title=f"G{g['id']} · bus {bus}",xlim=(lo,hi))
        ax.legend(loc='lower left',fontsize=8);ax.grid(alpha=.18)
    axes[-1].axis('off');axes[-1].text(.02,.92,'How to read\n\nDashed gray: original S1 8% curve\nSolid blue: shared optimized curve\nHollow markers: original-curve SCOPF states\nFilled markers: optimized-curve SCOPF states\nStar: base case; circle: contingency\nRed dotted lines: Q bounds and V limits\nRed-shaded voltage: outside 0.90–1.10 pu\nOutaged generators are omitted\n\nOne curve per generator is shared across all states.\nCCOpt verifies the Ipopt curve settings;\nit does not redesign slope or reference.',va='top',fontsize=12,linespacing=1.5)
    legend(fig.add_subplot(gs[3,:]))
    fig.suptitle(f"14-bus S2 · {SOLVER[solver]}\nOriginal versus optimized saturated zero-deadband droop · all operating points",fontsize=16,y=.985)
    fig.subplots_adjust(top=.92,bottom=.07,left=.065,right=.98)
    save(fig,f'{solver}_droop_curves')

# Exact numerical comparisons drive the separate-solver decision.
comparisons=[]
for arm in ['frozen','designed']:
    ref=datasets['ipopt'][arm]
    for solver in ['madnlp','ccopt']:
        d=datasets[solver][arm]
        row=dict(arm=arm,solver=solver,
            max_P_difference_MW=float(np.max(abs(ref['P']-d['P']))),
            max_Q_difference_MVAr=float(np.max(abs(ref['Q']-d['Q']))),
            max_V_difference_pu=float(np.max(abs(ref['V']-d['V']))),
            max_branch_MVA_difference=float(np.nanmax(abs(ref['S']-d['S']))),
            max_tap_difference_pu=max(abs(ref['result']['tap_settings'][s][k]-d['result']['tap_settings'][s][k]) for s in SCENARIOS for k in ref['result']['tap_settings'][s]),
            max_shunt_difference_pu=max(abs(ref['result']['shunt_settings'][s][k]-d['result']['shunt_settings'][s][k]) for s in SCENARIOS for k in ref['result']['shunt_settings'][s]))
        comparisons.append(row)
for solver in LANES:
    for arm in ['frozen','designed']:dashboard(solver,arm,datasets[solver][arm])
    droop_plot(solver)
assert all(not x['violations'] and not x['tap_violations'] and not x['shunt_violations'] for x in metrics)
# Cross-check independently computed loading with the saved scientific audit.
audit=load(DATA/'independent_audit.json')
for solver in LANES:
    for arm in ['frozen','designed']:
        d=datasets[solver][arm];name=LANES[solver][arm]
        checks=next(x for x in audit['checks'] if x['name']==name)['scenarios']
        for i,sid in enumerate(SCENARIOS):
            check=next(x for x in checks if x['id']==sid)
            assert abs(float(np.nanmin(np.array([b['thermal_limit']*100 for b in d['branches']])-d['S'][i]))-check['thermal_min_margin_mva'])<1e-8
(OUT/'validation.json').write_text(json.dumps(dict(dashboards=6,droop_comparisons=3,states_per_dashboard=25,
    no_limit_violations_beyond_tolerance=True,branch_flows_checked_against_independent_audit=True,
    solver_comparisons=comparisons,plot_metrics=metrics,source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__)]+[DATA/name/file for ls in LANES.values() for name in ls.values() for file in ['result.json','optimized_input.json']]+[DATA/'independent_audit.json',DATA/'catalog.json',DATA/'protocol.json']}),indent=2)+'\n')
lines=['# S2 all-state limit and control plots','','All plots use saved full-enumeration solutions only: base + 24 connected outages. No new optimization was run. Line 11 (7–8) islanding outage remains excluded. **No plotted operating/equipment limit is violated beyond the declared tolerance.** Binding limits and raw sub-tolerance exceedances are retained in `validation.json`.','','Separate figures are supplied because solver values differ; objective agreement does not imply identical dispatch or equipment. CCOpt uses exact complementarity with the Ipopt-designed curves frozen; MadNLP designs its own shared curves.','','| Arm | Solver versus Ipopt | Max ΔP MW | Max ΔQ MVAr | Max ΔV pu | Max Δbranch MVA | Max Δtap pu | Max ΔB pu |','|---|---|---:|---:|---:|---:|---:|---:|']
for r in comparisons:lines.append(f"| {r['arm']} | {r['solver']} | {r['max_P_difference_MW']:.6g} | {r['max_Q_difference_MVAr']:.6g} | {r['max_V_difference_pu']:.6g} | {r['max_branch_MVA_difference']:.6g} | {r['max_tap_difference_pu']:.6g} | {r['max_shunt_difference_pu']:.6g} |")
lines+=['','Generation shows P and Q together with capability bounds; G6 is offline in every state and omitted. Outaged generators are marked × at zero, rather than treated as operating units. Branch flow is the larger of the two terminal apparent-power magnitudes, which tests both terminal ratings; P/Q branch components are retained in the original evaluation data. Transformer outages have no tap setting and are marked × at the nominal ratio for identification only. Taps and continuous shunt B are independently selected in each state.','','PNG and SVG versions of every figure are included in [all figures ZIP](all_figures.zip). Red caps/dashes denote bounds; the black star is the base state; colored points cover every contingency. The curves are shared across all states, with original and optimized operating points overlaid. Curves extend outside the legal voltage interval to show saturation; only the operating points must remain within voltage bounds.']
for solver in LANES:
    lines+=['',f'## {SOLVER[solver]}','']
    for suffix,label in [('frozen_all_states','Original frozen curves: generation, voltages, flows, taps and shunt'),('designed_all_states','Optimized curves: generation, voltages, flows, taps and shunt'),('droop_curves','Original versus optimized droop curves')]:
        name=f'{solver}_{suffix}';lines += [f'### {label}','',f'![{label}]({name}.png)','',f'[SVG]({name}.svg)','']
# Exact plotted values are retained with nulls for outaged branch flows.
def clean(value):
    if isinstance(value,list):return [clean(v) for v in value]
    if isinstance(value,dict):return {k:clean(v) for k,v in value.items()}
    if isinstance(value,float) and not np.isfinite(value):return None
    return value
plotted=[]
for solver in LANES:
    for arm in ['frozen','designed']:
        d=datasets[solver][arm];lim=values_and_violations(d)
        plotted.append(dict(solver=solver,arm=arm,scenarios=SCENARIOS,
            generator_ids=[g['id'] for g in d['gens']],bus_ids=[b['id'] for b in d['buses']],
            branch_ids=[b['id'] for b in d['branches']],P_MW=d['P'].tolist(),Q_MVAr=d['Q'].tolist(),
            V_pu=d['V'].tolist(),max_terminal_S_MVA=d['S'].tolist(),generator_in_service=d['ag'].tolist(),
            branch_in_service=d['ab'].tolist(),limits={k:lim[k].tolist() for k in ['pmin','pmax','qmin','qmax','vlo','vhi','ratings']},
            shared_curves=d['c']['controls'],tap_settings=d['result']['tap_settings'],shunt_settings=d['result']['shunt_settings']))
(OUT/'plotted_data.json').write_text(json.dumps(clean(plotted),indent=2)+'\n')
lines+=['', 'Regenerate with `python examples/plot_s2_arpae14.py` using matplotlib 3.9.4 and numpy 2.2.6. Exact plotted values and limits are in `plotted_data.json`; outaged branch flows are null, not in-service zeros. No optimization is run.', '']
(OUT/'README.md').write_text('\n'.join(lines)+'\n')
with zipfile.ZipFile(OUT/'all_figures.zip','w',compression=zipfile.ZIP_DEFLATED) as archive:
    for p in files+[OUT/'README.md',OUT/'validation.json',OUT/'plotted_data.json']:archive.write(p,arcname=p.name)
print('Created 6 dashboards + 3 droop figures (PNG/SVG); all 25 states in each; no violations beyond tolerance.')
