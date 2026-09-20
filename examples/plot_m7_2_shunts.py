import json,sys
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
out=Path(sys.argv[1]);data=json.loads((out/'evidence.json').read_text())
def save(fig,name):
    fig.savefig(out/(name+'.png'),dpi=160);fig.savefig(out/(name+'.pdf'));plt.close(fig)
fig,axes=plt.subplots(2,2,figsize=(11,7),layout='constrained')
for col,name in enumerate(['capacitor','reactor']):
    rows=[r for r in data['sweeps'] if r['equipment']==name];opt=next(r for r in data['runs'] if r['equipment']==name and r['mode']=='one free')
    axes[0,col].plot([r['B'] for r in rows],[r['objective'] for r in rows],label='Fixed-B sweep');axes[0,col].scatter(opt['settings']['201'],opt['objective'],color='red',marker='*',s=120,label='Optimized B',zorder=4)
    axes[0,col].set(title=name,ylabel='Baseline objective');axes[0,col].legend();axes[0,col].grid(alpha=.2)
    axes[1,col].scatter([r['B'] for r in rows],[int(r['valid']) for r in rows]);axes[1,col].set(xlabel='Bank 201 susceptance B (pu)',ylabel='Physical validation',yticks=[0,1],yticklabels=['Fail','Pass'],ylim=(-.2,1.2))
fig.suptitle('M7.2: simple-bank sweep validation');save(fig,'susceptance_sweep')
fig,axes=plt.subplots(2,2,figsize=(11,7),layout='constrained')
for col,name in enumerate(['capacitor','reactor']):
    runs=[r for r in data['runs'] if r['equipment']==name]
    for r in runs:
        axes[0,col].plot([10,20,30],r['vm'],marker='o',label=r['mode'])
    axes[0,col].set(title=name,xlabel='Bus ID',ylabel='Voltage (pu)',xticks=[10,20,30]);axes[0,col].legend()
    axes[1,col].bar([r['mode'] for r in runs],[r['reactive_support'] for r in runs]);axes[1,col].axhline(0,color='black',lw=.7);axes[1,col].set(ylabel='Net shunt reactive injection (pu)')
fig.suptitle('Matched fixed / optimized simple banks');save(fig,'operating_points')
fig,axes=plt.subplots(1,2,figsize=(10,4.5),layout='constrained')
for ax,name,sign in zip(axes,['capacitor','reactor'],[1,-1]):
    ax.plot([0,sign*.06],[0,.003],label='Continuous G/B relation')
    ax.scatter([sign*.02*n for n in range(4)],[.001*n for n in range(4)],label='Legal counts 0–3',s=45)
    r=next(r for r in data['runs'] if r['equipment']==name and r['mode']=='one free');s=r['metrics']['settings'][0]
    ax.scatter(s['solved'],s['conductance'],marker='*',color='red',s=130,label='Optimized admittance',zorder=4)
    ax.set(title=name,xlabel='Susceptance B (pu)',ylabel='Conductance G (pu)');ax.legend(fontsize=8);ax.grid(alpha=.2)
fig.suptitle('Bank 201: one step type, one fractional count');save(fig,'bank_envelopes')
fig,axes=plt.subplots(1,2,figsize=(10,4.5),layout='constrained')
for ax,name in zip(axes,['capacitor','reactor']):
    runs=[r for r in data['runs'] if r['equipment']==name]
    branch=[r['metrics']['branch_active_loss'] for r in runs]
    shunt=[r['metrics']['shunt_active_consumption'] for r in runs]
    ax.bar([r['mode'] for r in runs],branch,label='Branch active loss')
    ax.bar([r['mode'] for r in runs],shunt,bottom=branch,label='Shunt active consumption')
    ax.set(title=name,ylabel='Active consumption (pu)');ax.legend(fontsize=8)
fig.suptitle('Loss metrics evaluated separately from the objective');save(fig,'active_losses')
