import json, sys
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
out=Path(sys.argv[1]); data=json.loads((out/'evidence.json').read_text())
def save(fig,name):
    fig.savefig(out/(name+'.png'),dpi=160); fig.savefig(out/(name+'.pdf')); plt.close(fig)
fig,ax=plt.subplots(figsize=(8,4.5),layout='constrained')
for state in ([0,0],[1,0],[2,0],[0,1],[1,1]):
    rows=[r for r in data['bank_sweep'] if r['state']==state]
    ax.plot([r['v'] for r in rows],[r['q'] for r in rows],marker='o',label=str(state))
ax.set(xlabel='Voltage (pu)',ylabel='Bank reactive consumption (pu)',title='M6.2: supplied legal states · negative Q is capacitive')
ax.legend(title='Step counts'); ax.grid(alpha=.2); save(fig,'bank_states')
fig,axes=plt.subplots(2,2,figsize=(10,7),layout='constrained')
for i,ax in enumerate(axes.flat):
    for r in data['runs']:
        s=r['scenarios'][i]; ax.plot([10,20,30],s['vm'],marker='o',label=str(r['state']))
    ax.set(title=s['id'],xlabel='Bus ID',ylabel='Voltage (pu)',xticks=[10,20,30]); ax.legend(title='Bank state'); ax.grid(alpha=.2)
fig.suptitle('M6.3: matched fixed-state preventive SCOPF'); save(fig,'voltage_profiles')
fig,axes=plt.subplots(1,2,figsize=(12,4.8),layout='constrained')
scenarios=data['runs'][1]['scenarios']; labels=[s['id'].replace('_','\n') for s in scenarios]
for j,(key,label) in enumerate([('qgen','Generation'),('qload','Load'),('qfixed','Fixed shunt'),('qbank','Bank'),('qbranch','Branches')]):
    axes[0].bar([i+(j-2)*.15 for i in range(4)],[s[key] for s in scenarios],width=.15,label=label)
axes[0].set(xticks=range(4),xticklabels=labels,ylabel='Reactive power (pu)',title='Nominal bank state [1, 0]: signed accounting'); axes[0].legend(fontsize=8); axes[0].axhline(0,color='black',lw=.7)
for r in data['runs']:
    axes[1].plot(range(4),[max(s['ac_residual'],1e-16) for s in r['scenarios']],marker='o',label=str(r['state']))
axes[1].axhline(1e-6,color='black',ls='--',label='AC acceptance tolerance'); axes[1].set(yscale='log',xticks=range(4),xticklabels=labels,ylabel='Maximum AC residual (pu)',title='Independent physical validation'); axes[1].legend(fontsize=8)
save(fig,'reactive_balance')
