"""Render M5 numerical evidence using Matplotlib (no package-core dependency)."""
import json
import sys
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

out=Path(sys.argv[1])
data=json.loads((out/'evidence.json').read_text())
plt.rcParams.update({'font.size':10,'axes.spines.top':False,'axes.spines.right':False})
fig,axes=plt.subplots(2,2,figsize=(11,7),layout='constrained')
for row,(name,xlabel) in enumerate([('ratio','Tap ratio (dimensionless)'),('phase','Phase shift (rad)')]):
    records=data['sweeps'][name]; x=[r['x'] for r in records]
    for col,indices in enumerate([(0,2),(1,3)]):
        ax=axes[row,col]
        for k,color,label in zip(indices,['#2563eb','#c2410c'],['From terminal','To terminal']):
            ax.plot(x,[r['reference'][k] for r in records],color=color,label=label+' reference')
            ax.plot(x,[r['actual'][k] for r in records],linestyle='none',marker='o',markersize=4,
                    markerfacecolor='none',color=color,label=label+' computed')
        ax.set(xlabel=xlabel,ylabel=('Active P' if col==0 else 'Reactive Q')+' (pu)')
        ax.grid(alpha=.2); ax.axhline(0,color='gray',lw=.6)
        ax.set_title(('M5.2 fixed ratio' if row==0 else 'M5.3 signed phase')+f" · max error {max(r['max_error'] for r in records):.1e} pu")
axes[0,0].legend(fontsize=8)
fig.savefig(out/'reference_sweeps.png',dpi=160)
fig.savefig(out/'reference_sweeps.pdf')
plt.close(fig)
panels=data['scenarios']
if panels:
    fig,axes=plt.subplots(2,2,figsize=(11,7),layout='constrained')
    for ax,p in zip(axes.flat,panels):
        x=list(range(len(p['branch_ids'])))
        ax.bar([i-.18 for i in x],[v/r for v,r in zip(p['from_abs'],p['ratings'])],width=.36,label='From terminal',color='#2563eb')
        ax.bar([i+.18 for i in x],[v/r for v,r in zip(p['to_abs'],p['ratings'])],width=.36,label='To terminal',color='#c2410c')
        ax.axhline(1,color='#dc2626',linestyle='--',label='Rating')
        ax.set_xticks(x,[str(i) for i in p['branch_ids']]); ax.set_ylim(0,1.1)
        ax.set(title=p['scenario'],xlabel='Branch ID (11 = transformer)',ylabel='Apparent power / rating')
        ax.grid(axis='y',alpha=.2)
    axes[0,0].legend(fontsize=8)
    fig.savefig(out/'terminal_loadings.png',dpi=160)
    fig.savefig(out/'terminal_loadings.pdf')
    plt.close(fig)
