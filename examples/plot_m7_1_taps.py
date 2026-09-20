import json,sys
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
out=Path(sys.argv[1]); data=json.loads((out/'evidence.json').read_text()); runs=data['runs']
def save(fig,name):
    fig.savefig(out/(name+'.png'),dpi=160);fig.savefig(out/(name+'.pdf'));plt.close(fig)
fig,axes=plt.subplots(2,1,figsize=(8,6),layout='constrained',sharex=True)
rows=data['sweep']; axes[0].plot([r['tap'] for r in rows],[r['objective'] for r in rows],label='Fixed-tap OPF sweep')
r=runs[1];axes[0].scatter(r['taps']['11'],r['objective'],marker='*',s=160,color='red',label='Continuous optimized tap',zorder=4)
axes[0].set(ylabel='Baseline objective',title='M7.1: one transformer · fixed droop and shunts');axes[0].legend();axes[0].grid(alpha=.2)
axes[1].scatter([r['tap'] for r in rows],[int(r['valid']) for r in rows]);axes[1].set(xlabel='Transformer 11 tap ratio',ylabel='Physical validation',yticks=[0,1],yticklabels=['Fail','Pass'],ylim=(-.2,1.2));save(fig,'tap_sweep')
fig,axes=plt.subplots(1,2,figsize=(10,4.5),layout='constrained')
for r in runs:
    axes[0].plot([10,20,30],r['vm'],marker='o',label=r['name']);axes[1].plot([7,9],r['qg'],marker='o',label=r['name'])
axes[0].set(xlabel='Bus ID',ylabel='Voltage (pu)',xticks=[10,20,30]);axes[1].set(xlabel='Generator ID',ylabel='Reactive output (pu)',xticks=[7,9]);axes[0].legend(fontsize=8);fig.suptitle('Matched fixed / optimized tap configurations');save(fig,'operating_points')
fig,axes=plt.subplots(1,2,figsize=(10,4.5),layout='constrained')
for ax,id,bounds,supplied in zip(axes,['11','22'],[(.95,1.05),(.98,1.02)],[1.02,1.]):
    ax.axhspan(*bounds,alpha=.12,color='green',label='Envelope when enabled');ax.axhline(supplied,ls='--',color='gray',label='Supplied ratio')
    ax.scatter(range(3),[r['taps'][id] for r in runs],s=65);ax.set(xticks=range(3),xticklabels=['Fixed','11 free','11 + 22 free'],ylabel='Tap ratio',title='Branch '+id);ax.legend(fontsize=8)
save(fig,'tap_settings')
