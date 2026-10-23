"""Static figures for accepted mixed-control base-operation states only."""
import json,math,sys
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

def load(p):return json.loads(Path(p).read_text())
def plot(root):
    root=Path(root);folder=root/'multi-design-hot';r=load(folder/'result.json')['data'];case=load(folder/'period-1.json')['data']['case']
    assert load(folder/'summary.json')['accepted'] and load(folder/'python-audit.json')['valid']
    out=root/'figures';out.mkdir(exist_ok=True)
    modes={a['generator_id']:a['mode']['type'] for a in r['periods'][0]['reactive_assignments']}
    plt.rcParams.update({'font.size':10,'axes.spines.top':False,'axes.spines.right':False,'savefig.dpi':180})
    fig,ax=plt.subplots(figsize=(6.5,5.5))
    theta=np.linspace(-np.pi/2,np.pi/2,400);ax.plot(np.cos(theta),np.sin(theta),color='#4b5563',lw=1.4,label='Apparent-power limit')
    for mode,color,marker,label in [('AVR','#2563eb','o','15 AVR units'),('VoltVarDroop','#d97706','^','36 droop units')]:
        pts=[(p['states']['base']['pg'][i]/g['s_rated'],p['states']['base']['qg'][i]/g['s_rated']) for p in r['periods'] for i,g in enumerate(case['generators']) if g['available'] and modes[g['id']]==mode]
        ax.scatter(*zip(*pts),s=24,c=color,marker=marker,alpha=.55,label=label,edgecolors='none')
    ax.set(xlabel='Active power / rated apparent power',ylabel='Reactive power / rated apparent power',xlim=(-.03,1.06),ylim=(-1.07,1.07),title='Capability use across five accepted periods')
    ax.set_aspect('equal');ax.grid(alpha=.18);ax.legend(loc='upper left',fontsize=9)
    fig.tight_layout();fig.savefig(out/'capability_use.png');fig.savefig(out/'capability_use.svg');plt.close(fig)
    controls={str(a['control_id']):a for a in case['attachments']};gindex={g['id']:i for i,g in enumerate(case['generators'])}
    ids=sorted(r['droops'],key=int)
    score=lambda k:abs(r['droops'][k]['v_ref']-case['controls'][int(k)-1]['schedule']['v_ref'])
    selected=sorted(ids,key=score,reverse=True)[:3]
    fig,axes=plt.subplots(1,3,figsize=(12,3.8))
    for ax,k in zip(axes,selected):
        original=case['controls'][int(k)-1];setting=r['droops'][k];a=controls[k];i=gindex[a['generator_id']];g=case['generators'][i];S=g['s_rated']
        p=r['periods'][1]['states']['base']['pg'][i];h=math.sqrt(max(S*S-p*p,0));lo=max(original['capability']['q_min'],-h);hi=min(original['capability']['q_max'],h)
        s=original['schedule'];before=dict(slope=original['slope'],v_ref=s['v_ref'],deadband_low=s['v_ref']-s['v_db_low'],deadband_high=s['v_db_high']-s['v_ref'])
        bidx={b['id']:j for j,b in enumerate(case['network']['buses'])}[a['location']['bus_id']]
        observed=[period['states']['base']['vm'][bidx] for period in r['periods']]
        x=np.linspace(min(before['v_ref'],setting['v_ref'],min(observed))-.035,
                      max(before['v_ref'],setting['v_ref'],max(observed))+.035,600)
        for pars,color,style,label in [(before,'#64748b','--','Supplied'),(setting,'#059669','-','Designed')]:
            raw=original['q_at_deadband']+(np.maximum(pars['v_ref']-pars['deadband_low']-x,0)-np.maximum(x-pars['v_ref']-pars['deadband_high'],0))/pars['slope']
            ax.plot(x,np.clip(raw,lo,hi)/S,style,color=color,label=label)
        bidx={b['id']:j for j,b in enumerate(case['network']['buses'])}[a['location']['bus_id']]
        for t,period in enumerate(r['periods']):
            state=period['states']['base'];ax.scatter([state['vm'][bidx]],[state['qg'][i]/S],c='#111827',s=18,zorder=5)
        ax.set(title=f"Generator {g['id']}",xlabel='Regulated voltage (pu)',ylabel='Q / rated apparent power');ax.grid(alpha=.18)
    axes[0].legend(fontsize=9);fig.suptitle('Shared droop designs and period operating points',y=1.01)
    fig.text(.5,-.015,'Curves use period-2 active output for capability clipping; points use each period’s own active output.',ha='center',fontsize=9)
    fig.tight_layout();fig.savefig(out/'shared_droop_curves.png',bbox_inches='tight');fig.savefig(out/'shared_droop_curves.svg',bbox_inches='tight');plt.close(fig)
    fig,ax=plt.subplots(figsize=(7.5,3.6));times=np.arange(1,6)
    vm=np.array([p['states']['base']['vm'] for p in r['periods']]);ax.fill_between(times,vm.min(axis=1),vm.max(axis=1),color='#a7f3d0',alpha=.6,label='All-bus voltage range')
    ax.plot(times,vm.min(axis=1),'o-',color='#047857',lw=1.5);ax.plot(times,vm.max(axis=1),'o-',color='#047857',lw=1.5)
    ax.set(xticks=times,xticklabels=['1 · 90%','2 · 100%','3 · 105%','4 · 100%','5 · 90%'],xlabel='One-hour period and demand factor',ylabel='Voltage (pu)',title='Accepted base-operation voltage envelope')
    ax.grid(alpha=.18);ax.legend(fontsize=9);fig.tight_layout();fig.savefig(out/'voltage_envelope.png');fig.savefig(out/'voltage_envelope.svg');plt.close(fig)
    return out
if __name__=='__main__':print(plot(sys.argv[1]))
