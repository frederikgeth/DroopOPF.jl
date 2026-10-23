"""Plot 15 retained S1 14-bus all-free-control joint-anchor designs; no solves.

Dashboard style follows plot_s2_arpae14.py. Each demand is independently designed;
CCOpt freely optimizes the curves here, unlike the fixed-curve S2 checks.
"""
from pathlib import Path
import os,json,cmath,hashlib,zipfile
os.environ.setdefault('MPLCONFIGDIR','/tmp/s2-arpae14-matplotlib')
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
DATA=ROOT/'artifacts/s1_free_droop/14'
OUT=ROOT/'artifacts/s1_14bus_control_plots';OUT.mkdir(exist_ok=True)
load=lambda p:json.loads(p.read_text())
FACTORS=[.9,.95,1.,1.05,1.1]
SCENARIOS=['d90','d95','base','d105','d110']
LABELS=dict(zip(SCENARIOS,['90%','95%','100%','105%','110%']))
LONG={s:'Demand '+LABELS[s]+(' (nominal)' if s=='base' else '') for s in SCENARIOS}
COLOR=dict(zip(SCENARIOS,['#2563eb','#06b6d4','#111827','#f59e0b','#dc2626']))
SOLVER={'ipopt':'Ipopt','madnlp':'MadNLP','ccopt':'CCOpt (free curve design)'}
STYLE={'Base':dict(color='#374151',ls='--',lw=1.8),'Ipopt':dict(color='#2563eb',ls='-',lw=2.4),'MadNLP':dict(color='#d97706',ls='-.',lw=1.8),'CCOpt':dict(color='#059669',ls=':',lw=2.)}
MARK={'Ipopt':'o','MadNLP':'^','CCOpt':'x'}
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.spines.top':False,'axes.spines.right':False,'savefig.facecolor':'white'})
rows={};sources=[]
for solver in ['ipopt','madnlp','ccopt']:
    rows[solver]={}
    for factor,sid in zip(FACTORS,SCENARIOS):
        path=DATA/'attempts'/f'design-droop_tap_shunt-{factor}-joint-{solver}.json'
        r=load(path);assert r['accepted'] and r['point_pass'] and r['design_policy_valid']
        assert r['tags']['stage']=='design' and r['tags']['family']=='droop_tap_shunt'
        rows[solver][sid]=r;sources += [path,ROOT/r['model_path'],ROOT/r['base_model_path'],ROOT/r['result_path']]
s1path=ROOT/'artifacts/s1_arpae14_closeout/calibration_reference.json';s1=load(s1path)
basepath=ROOT/'artifacts/s1_arpae14_joint_reference/relative5-study.json';base=load(basepath)['data']['case']
base_study=dict(case=base,**rows['ipopt']['base']['policy'])
studies={name:dict(case=load(ROOT/rows[name.lower()]['base']['model_path'])['data']['case'],contingencies=[]) for name in ['Ipopt','MadNLP','CCOpt']}
results={name:dict(states={s:r['state'] for s,r in rows[name.lower()].items()},tap_settings={s:r['taps'] for s,r in rows[name.lower()].items()},shunt_settings={s:r['susceptances'] for s,r in rows[name.lower()].items()}) for name in ['Ipopt','MadNLP','CCOpt']}
idx={b['id']:i for i,b in enumerate(base['network']['buses'])};gidx={g['id']:i for i,g in enumerate(base['generators'])}
files=[];metrics=[];curve_data=[];equipment_data=[]
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

def save(fig,name):
    for extension in ['png','svg']:
        path=OUT/f'{name}.{extension}';fig.savefig(path,dpi=160,bbox_inches='tight');files.append(path)
    plt.close(fig)

def legend(ax,extra=None):
    ax.axis('off')
    handles=[Line2D([],[],marker='*' if s=='base' else 'o',linestyle='',color=COLOR[s],markersize=9 if s=='base' else 5,label=LONG[s]) for s in SCENARIOS]
    if extra:handles+=extra
    ax.legend(handles=handles,loc='center',ncol=5,fontsize=10,frameon=False,handletextpad=.4,columnspacing=1.9)

def points(ax,values,available=None,base=True):
    n=values.shape[1]
    for k,sid in enumerate(SCENARIOS):
        off=(k-(len(SCENARIOS)-1)/2)*.10
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
    gpq=np.empty((len(SCENARIOS),len(d['gens'])*2));gpq[:,0::2]=d['P'];gpq[:,1::2]=d['Q']
    lower=np.column_stack((lim['pmin'],lim['qmin'])).ravel();upper=np.column_stack((lim['pmax'],lim['qmax'])).ravel()
    bounds(axes[0],lower,upper);points(axes[0],gpq,np.repeat(d['ag'],2,axis=1))
    axes[0].axhline(0,color='#64748b',lw=.6)
    axes[0].set_xticks(np.arange(len(lower)),[f"G{g['id']} P\nbus {g['bus_id']}" if k==0 else f"G{g['id']} Q\nbus {g['bus_id']}" for g in d['gens'] for k in [0,1]],fontsize=8)
    axes[0].set(ylabel='P (MW) / Q (MVAr)',title='Generation and capability bounds')
    bounds(axes[1],lim['vlo'],lim['vhi']);points(axes[1],d['V'])
    axes[1].set_xticks(np.arange(len(d['buses'])),[str(b['id']) for b in d['buses']])
    axes[1].set(xlabel='Bus',ylabel='Voltage magnitude (pu)',title='Voltage magnitudes and source bounds')
    branchlabels=[f"{'T' if b['kind']=='transformer' else 'L'}{b['id']}\n{b['from_bus']}–{b['to_bus']}" for b in d['branches']]
    bounds(axes[2],np.zeros(len(d['branches'])),lim['ratings']);points(axes[2],d['S'],d['ab'])
    axes[2].set_xticks(np.arange(len(branchlabels)),branchlabels,fontsize=7)
    axes[2].set(ylabel='max(|S from|, |S to|) (MVA)',title='Both-terminal apparent flow and Rate-A ratings')
    loading=d['S']/lim['ratings']*100
    points(axes[3],loading,d['ab']);axes[3].axhline(100,color='#b91c1c',ls='--',lw=1.6,label='100% of Rate A')
    axes[3].set_xticks(np.arange(len(branchlabels)),branchlabels,fontsize=7)
    axes[3].set(ylabel='Loading (% of source Rate A)',title='Normalized flow · reveals stress on small-rated branches')
    axes[3].legend(loc='lower right',fontsize=9);axes[3].set_ylim(-5,105)
    x=np.arange(len(SCENARIOS));cols=['#2563eb','#d97706','#7c3aed']
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
    axes[4].set(title='Transformer taps · dashed = absolute bounds',ylabel='Tap ratio (pu)')
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
    zoom.set_xticks([0,1,2,3,4],[LABELS[SCENARIOS[i]] for i in [0,1,2,3,4]],fontsize=6)
    zoom.tick_params(axis='y',labelsize=6);zoom.set_title('Settings detail (upper bound 0.4 pu outside zoom)',fontsize=7)
    zoom.grid(alpha=.15)
    axes[5].set(title='Continuous shunt-bank settings · not discrete steps',ylabel='Susceptance B (pu on 100 MVA base)')
    axes[5].legend(fontsize=9,loc='upper left')
    for ax in axes[4:]:
        ax.set_xticks(x,[LABELS[s] for s in SCENARIOS],rotation=70,fontsize=8);ax.set_xlabel('Demand level (independently redesigned)');ax.grid(alpha=.18)
        ax.axvspan(1.6,2.4,color='#e2e8f0',alpha=.7,zorder=-1)
    n=len(lim['violations'])+len(tap_violations)+len(bank_violations)
    fig.suptitle(f"14-bus S1 · {SOLVER[solver]} · {'original frozen 8% curves' if arm=='frozen' else 'free slope/reference design at each demand'}\nFive independently redesigned demand levels · all-free droop, taps and bank · limit violations beyond tolerance: {n}",fontsize=16,y=.985)
    legend(fig.add_subplot(gs[3,:]))
    fig.text(.5,.008,'Red caps = equipment/operating bounds. Colored points = the five saved demand states; black star = nominal 100% demand.\nTolerance: power/ratings 0.0001 MW/MVAr/MVA, voltage/taps/B 1e-6 pu. S1 base-case steady state only; no contingencies are included.',ha='center',fontsize=9)
    fig.subplots_adjust(top=.91,bottom=.08,left=.065,right=.98)
    save(fig,f'{solver}_{arm}_all_states')
    metrics.append(dict(solver=solver,arm=arm,violations=lim['violations'],raw_bound_exceedances=lim['raw_overshoots'],
                        tap_violations=tap_violations,shunt_violations=bank_violations,taps=tapvalues,shunts=bankvalues,
                        max_branch_loading_percent=float(np.nanmax(loading))))
datasets={}
for solver in rows:
    study=dict(case=base,contingencies=[dict(id=s,branch_ids=[],generator_ids=[]) for s in SCENARIOS if s!='base'],**rows[solver]['base']['policy'])
    datasets[solver]=collect(study,results[{'ipopt':'Ipopt','madnlp':'MadNLP','ccopt':'CCOpt'}[solver]])
for solver,d in datasets.items():dashboard(solver,'designed',d)

scenarios=SCENARIOS;labels=LABELS
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
        label=f"{'S1 base' if solver=='Base' else solver}: {span:.4f}%, Vref={d['schedule']['v_ref']:.6f}"
        ax.plot(voltage,q_curve(d,voltage),label=label,**STYLE[solver])
        row['curves'][solver]=dict(full_Q_span_percent=span,v_ref=d['schedule']['v_ref'],slope=d['slope'])
        if solver=='Base':continue
        for sid in ['base']:
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
    zoom.set(xlim=(zl,zh),ylim=(zmin-pad,zmax+pad),title='Operating-region detail · nominal-demand operating points')
    fig.suptitle(f'G{gid} at bus {bus} · original S1 base versus independent S1 nominal-demand droop designs',fontsize=15)
    fig.text(.5,.025,'Base = original S1 8% calibrated curve. Each curve is the independently optimized 100%-demand S1 design. Stars = base-case operating points.\nIpopt, MadNLP and CCOpt all optimize free slopes/references here. Stars show their nominal operating points; gray star = original S1 reference.',ha='center',fontsize=9)
    fig.subplots_adjust(top=.85,bottom=.20,wspace=.23)
    row['ipopt_ccopt_curve_difference_max_MVAr']=float(np.max(abs(q_curve(curves['Ipopt'],voltage)-q_curve(curves['CCOpt'],voltage))))
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
    ref=np.full(len(scenarios),initial);ref[np.isnan(vals['Ipopt'])]=np.nan
    fig,(ax,delta)=plt.subplots(2,1,figsize=(15,8.8),sharex=True,gridspec_kw={'height_ratios':[2.2,1]})
    x=np.arange(len(scenarios))
    ax.plot(x,ref,label=f'S1 base reference = {initial:.8f}',**STYLE['Base'])
    for solver,v in vals.items():
        ax.plot(x,v,marker=MARK[solver],ms=5,label=solver,**STYLE[solver])
        assert np.all((v[np.isfinite(v)]>=lo-1e-6)&(v[np.isfinite(v)]<=hi+1e-6))
    ax.axhline(lo,color='#b91c1c',ls='--',lw=.9,label=f'Absolute bounds: {lo:.5f}–{hi:.5f}')
    ax.axhline(hi,color='#b91c1c',ls='--',lw=.9)
    pad=(hi-lo)*.10;ax.set_ylim(lo-pad,hi+pad)
    ax.set(ylabel=units,title='Absolute setting by demand · all four references on one axis')
    ax.legend(loc='upper left',fontsize=9,ncol=2)
    if not tap:
        zoom=ax.inset_axes([.38,.40,.59,.43])
        zoom.plot(x,ref,**STYLE['Base'])
        for solver,v in vals.items():zoom.plot(x,v,marker=MARK[solver],ms=2,**{**STYLE[solver],'lw':1.})
        zoom.set_ylim(-.002,max(float(np.nanmax(v)) for v in vals.values())*1.16)
        zoom.set_title('Settings zoom (0.4 pu upper bound is outside this inset)',fontsize=8)
        zoom.set_xticks([0,1,2,3,4],[labels[scenarios[i]] for i in [0,1,2,3,4]],fontsize=7)
        zoom.tick_params(axis='y',labelsize=7);zoom.grid(alpha=.18)
    if np.isnan(ref).any():
        for k in np.flatnonzero(np.isnan(ref)):
            for a in (ax,delta):a.axvspan(k-.35,k+.35,color='#e2e8f0',alpha=.8)
            ax.text(k,lo+pad*.2,'Outaged\nno tap',ha='center',fontsize=8,color='#475569')
    for solver,v in vals.items():
        delta.plot(x,v-vals['Ipopt'],marker=MARK[solver],ms=4,label=f'{solver} − Ipopt',**STYLE[solver])
    delta.axhline(0,color='#64748b',lw=.7);delta.ticklabel_format(axis='y',style='sci',scilimits=(0,0))
    delta.set(ylabel='Difference from Ipopt (pu)',xlabel='Demand level (%) · each point is independently redesigned')
    delta.legend(loc='best',fontsize=8,ncol=3)
    for a in (ax,delta):a.grid(alpha=.18);a.axvspan(1.65,2.35,color='#f1f5f9',zorder=-2)
    delta.set_xticks(x,[labels[s] for s in scenarios],rotation=60,ha='right',fontsize=9)
    fig.suptitle(f'{title} · S1 base reference versus S1 all-free-control solver settings',fontsize=15)
    fig.text(.5,.025,'Dashed gray = original nominal S1 calibration reference (constant). Each colored point is an independent base-case design at that demand.\nAll three backends independently optimize droop, taps and continuous B; these are not frozen-design demand tests or contingencies.',ha='center',fontsize=9)
    fig.subplots_adjust(top=.88,bottom=.18,hspace=.16)
    equipment_data.append(dict(kind=kind,id=did,base_reference=initial,lower=lo,upper=hi,
        scenarios=scenarios,values={k:[None if not np.isfinite(v) else float(v) for v in row] for k,row in vals.items()},
        max_abs_difference_from_ipopt={k:float(np.nanmax(abs(row-vals['Ipopt']))) for k,row in vals.items()}))
    save(fig,stem)

for control in base_study['tap_controls']:equipment_plot('tap',control)
for control in base_study['shunt_controls']:equipment_plot('shunt',control)
assert all(not d['violations'] and not d['tap_violations'] and not d['shunt_violations'] for d in metrics)
audit=load(OUT/'independent_audit.json');assert audit['states_replayed']==15 and audit['discrepancies']==0
validation=dict(figures=12,operating_dashboards=3,droop_comparisons=5,tap_comparisons=3,shunt_comparisons=1,
 selected_attempts=15,independent_states=15,discrepancies=0,new_optimizations=0,
 scope='Saved 14-bus all-free droop/tap/shunt designs, matched joint anchor, five sampled demands, three solvers; nominal curves compared separately',
 ccopt_freely_designs_curves=True,curves=curve_data,equipment=equipment_data,operating_limits=metrics,
 source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in set(sources+[s1path,basepath,Path(__file__),ROOT/'examples/audit_s1_14bus_control_plots.py'])})
(OUT/'validation.json').write_text(json.dumps(validation,indent=2)+'\n')
lines=['# S1 14-bus all-free-control solver comparison','','S1 visual follow-up: 15 previously accepted matched joint-anchor results, independently replayed with zero discrepancies. No optimization was rerun. All three backends independently optimized slopes, references, all three taps and bank 3. CCOpt is a genuine free-curve design in this S1 comparison.','','Each demand (90/95/100/105/110%) has its own optimized controller/equipment design. These are not one frozen design across demands, and there are no contingencies in these figures. Droop overlays compare the 100%-demand designs only; their stars are nominal operating points. The dashed base reference is the original S1 calibrated 8% curve and nominal equipment reference.','','| Demand | Ipopt loss MW | MadNLP loss MW | CCOpt loss MW |','|---:|---:|---:|---:|']
for factor,sid in zip(FACTORS,SCENARIOS):lines.append(f"| {factor:.0%} | {rows['ipopt'][sid]['loss_mw']:.9f} | {rows['madnlp'][sid]['loss_mw']:.9f} | {rows['ccopt'][sid]['loss_mw']:.9f} |")
lines += ['', 'All plotted generation, voltage, both-terminal branch-flow, tap and shunt limits pass within the original declared tolerances. Original study Pmin=0/symmetric Q limits, ±5%-of-source taps, bank-specific continuous B, independent 2–8% full-Q-span slopes and reference movement ±0.02 pu remain unchanged. Historical direct scores, failures/recoveries and selected frozen 8% baseline are preserved. Similar losses do not imply unique curve settings, and no global optimum is claimed. These retained numerical results predate the zero-deadband specialization and are not presented as fresh solver performance measurements.','','## Operating solution values','']
for solver in rows:lines += [f'### {SOLVER[solver]}','',f'![{SOLVER[solver]} operating limits]({solver}_designed_all_states.png)','']
lines += ['## Nominal droop comparisons','']
for a in base['attachments']:
 gid=a['generator_id'];lines += [f'### G{gid} at bus {a["location"]["bus_id"]}','',f'![G{gid} droop](droop_G{gid}_solver_comparison.png)','']
lines += ['## Equipment settings across demands','']
for t in base_study['tap_controls']:
 did=t['branch_id'];lines += [f'### Transformer T{did}','',f'![T{did}](tap_T{did}_solver_comparison.png)','']
lines += ['### Shunt bank 3','','![Bank 3](shunt_B3_solver_comparison.png)','','SVG copies accompany every PNG. Exact values, selected source hashes and plot checks are retained in validation.json; independent complex AC/design-policy replay is in independent_audit.json. Regenerate with `python3 examples/audit_s1_14bus_control_plots.py` followed by `python examples/plot_s1_14bus_control_comparisons.py` (matplotlib 3.9.4, numpy 2.2.6).','']
(OUT/'REPORT.md').write_text('\n'.join(lines))
with zipfile.ZipFile(OUT/'all_figures.zip','w',zipfile.ZIP_DEFLATED) as archive:
 for p in files+[OUT/'REPORT.md',OUT/'validation.json',OUT/'independent_audit.json']:archive.write(p,p.name)
print('S1: 12 figure pairs; 15 selected states; no bound violations beyond tolerance; genuine CCOpt curve designs.')
