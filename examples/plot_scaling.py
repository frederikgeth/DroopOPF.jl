import json,sys
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
out=Path(sys.argv[1]);rows=json.loads((out/'evidence.json').read_text())['rows']
def save(fig,name):
    fig.savefig(out/(name+'.png'),dpi=160);fig.savefig(out/(name+'.pdf'));plt.close(fig)
fig,axes=plt.subplots(1,3,figsize=(12,4),layout='constrained')
for free in [False,True]:
    rs=[r for r in rows if r['free']==free and 'build_seconds' in r]
    for ax,key in zip(axes,['build_seconds','solve_seconds','validation_seconds']):
        ax.scatter([r['buses'] for r in rs],[r[key] for r in rs],label='Joint optimized' if free else 'All fixed');ax.scatter([r['buses'] for r in rs if not r['valid']],[r[key] for r in rs if not r['valid']],marker='x',color='red',zorder=5);ax.set(xlabel='Buses',ylabel='Seconds',title=key.replace('_seconds','').capitalize(),yscale='log');ax.legend(fontsize=8);ax.grid(alpha=.2)
fig.suptitle('Synthetic scaling · red crosses mark unsuccessful overall validation');save(fig,'timings')
fig,axes=plt.subplots(1,2,figsize=(9,4),layout='constrained')
for free in [False,True]:
    rs=[r for r in rows if r['free']==free and 'model_size' in r]
    for ax,vals in zip(axes,[[r['model_size']['variables'] for r in rs],[r['allocated_bytes']/1e6 for r in rs]]):
        ax.scatter([r['buses'] for r in rs],vals,label='Joint optimized' if free else 'All fixed');ax.set_xlabel('Buses');ax.legend(fontsize=8)
axes[0].set_ylabel('JuMP variables');axes[1].set_ylabel('Julia allocated MB per solve');save(fig,'resources')
