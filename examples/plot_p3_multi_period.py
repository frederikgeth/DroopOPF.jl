"""Three compact figures for independently accepted P3 period designs."""
import json
import sys
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(sys.argv[1])
OUT = ROOT/'figures'
OUT.mkdir(exist_ok=True)
load = lambda p: json.loads(p.read_text())
assert load(ROOT/'python-replay.json')['valid']
plt.rcParams.update({'font.size':10, 'axes.spines.top':False, 'axes.spines.right':False,
                     'figure.facecolor':'white', 'savefig.facecolor':'white'})
blue, orange = '#2374AB', '#D76A27'

def save(fig, name):
    for ext in ('png','svg'):
        fig.savefig(OUT/f'{name}.{ext}', dpi=170, bbox_inches='tight')
    plt.close(fig)

fig, axes = plt.subplots(1,3,figsize=(13.4,3.8),layout='constrained')
for ax,n in zip(axes,(3,14,500)):
    folder=ROOT/str(n); factors=load(folder/'inputs.json')['factors']
    baseline=load(folder/'fixed/result.json'); design=load(folder/'design/result.json')
    ax.plot(range(1,6),[r['objective'] for r in baseline['periods']], 'o--',color=blue,label='Fixed droop')
    ax.plot(range(1,6),[r['objective'] for r in design['periods']], 'o-',color=orange,label='Shared designed droop')
    gain=100*(baseline['objective_mwh']-design['objective_mwh'])/baseline['objective_mwh']
    ax.set(title=f'{n} buses · {gain:.2f}% less loss energy',xlabel='Hour / demand',ylabel='Active loss (MW)')
    ax.set_xticks(range(1,6),[f'{t}\n{f:.0%}' for t,f in enumerate(factors,1)])
    ax.grid(alpha=.18);ax.legend(fontsize=8)
fig.suptitle('Five-hour operation with ramp limits and fixed equipment',fontsize=14)
save(fig,'loss_profiles')

fig,axes=plt.subplots(2,2,figsize=(12,6.2),layout='constrained')
for col,n in enumerate((14,500)):
    folder=ROOT/str(n); case=load(folder/'design/period-1.json')['data']['case']; result=load(folder/'design/result.json')
    old=case['controls']; new=result['droops']; ids=list(range(1,len(old)+1))
    spans=[d['capability']['q_max']-d['capability']['q_min'] for d in old]
    axes[0,col].plot(ids,[100*d['slope']*q for d,q in zip(old,spans)],'o--',color=blue,ms=3,label='Supplied')
    axes[0,col].plot(ids,[100*new[str(i)]['slope']*q for i,q in zip(ids,spans)],'o-',color=orange,ms=3,label='Designed')
    axes[0,col].axhspan(2,8,alpha=.06,color=orange)
    axes[0,col].set(title=f'{n}-bus shared curves',ylabel='Voltage span across full Q range (%)')
    axes[0,col].legend(fontsize=8)
    axes[1,col].bar(ids,[1000*(new[str(i)]['v_ref']-d['schedule']['v_ref']) for i,d in zip(ids,old)],color=orange)
    axes[1,col].axhline(0,color='gray',lw=.8)
    axes[1,col].set(xlabel='Control index',ylabel='Reference change (10⁻³ pu)',ylim=(-22,22))
    for ax in axes[:,col]:
        ax.grid(alpha=.15)
        ax.set_xticks(ids if n==14 else [1,10,20,30,40,51])
        ax.set_xlim(.5,len(old)+.5)
fig.suptitle('One common droop design across all five periods',fontsize=14)
save(fig,'shared_parameters')

folder=ROOT/'500';c=load(folder/'design/period-1.json')['data']['case'];r=load(folder/'design/result.json')
attachments={a['control_id']:a for a in c['attachments']};gids={g['id']:i for i,g in enumerate(c['generators'])};bids={b['id']:i for i,b in enumerate(c['network']['buses'])}
# Show the three controls with the largest physical reactive capability spans.
selected=sorted(attachments,key=lambda i:c['controls'][i-1]['capability']['q_max']-c['controls'][i-1]['capability']['q_min'],reverse=True)[:3]
fig,axes=plt.subplots(1,3,figsize=(13.4,4.0),layout='constrained')
for ax,i in zip(axes,selected):
    d=c['controls'][i-1];s=d['schedule'];p=r['droops'][str(i)];a=attachments[i];gi=gids[a['generator_id']];bi=bids[a['location']['bus_id']]
    vm=np.array([o['state']['vm'][bi] for o in r['periods']]);q=np.array([o['state']['qg'][gi] for o in r['periods']])*c['base_power']
    lo=min(min(vm)-.01,s['v_ref']-.05,p['v_ref']-.05);hi=max(max(vm)+.01,s['v_ref']+.05,p['v_ref']+.05)
    v=np.linspace(lo,hi,500);cap=d['capability']
    curve=lambda low,high,slope:np.clip(d['q_at_deadband']+(np.maximum(low-v,0)-np.maximum(v-high,0))/slope,cap['q_min'],cap['q_max'])*c['base_power']
    ax.plot(v,curve(s['v_db_low'],s['v_db_high'],d['slope']), '--',color=blue,label='Supplied curve')
    ax.plot(v,curve(p['v_ref']-p['deadband_low'],p['v_ref']+p['deadband_high'],p['slope']),color=orange,label='Shared design')
    groups={}
    for t,(x,y) in enumerate(zip(vm,q),1):
        key=(round(float(x),6),round(float(y),3))
        groups.setdefault(key,[]).append(t)
    factors=load(folder/'inputs.json')['factors']
    for color,((x,y),hours) in zip(('#4F2A84','#20908D','#9AAA00'),groups.items()):
        label='Hours '+', '.join(map(str,hours)) if len(hours)>1 else 'Hour '+str(hours[0])
        label+=f' ({factors[hours[0]-1]:.0%})'
        ax.scatter([x],[y],color=color,s=48,edgecolors='white',zorder=3,label=label)
    ax.set(title=f'Control {i} · generator {a["generator_id"]}',xlabel='Regulated voltage (pu)',ylabel='Reactive output (MVAr)')
    ax.grid(alpha=.18);ax.legend(fontsize=8)
fig.suptitle('500-bus design: largest-capability controllers and hourly operating points',fontsize=13)
save(fig,'500_droop_curves')
print(OUT)
