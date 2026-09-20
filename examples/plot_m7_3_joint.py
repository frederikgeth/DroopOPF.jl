import json,sys
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
out=Path(sys.argv[1]);data=json.loads((out/'evidence.json').read_text());rows=data['selected'];labels=[r['configuration'] for r in rows]
def save(fig,name):
    fig.savefig(out/(name+'.png'),dpi=160);fig.savefig(out/(name+'.pdf'));plt.close(fig)
fig,ax=plt.subplots(figsize=(9,4.5),layout='constrained');a=[r['metrics']['active_dispatch_component'] for r in rows];b=[r['metrics']['reactive_dispatch_component'] for r in rows]
ax.bar(labels,a,label='Active dispatch');ax.bar(labels,b,bottom=a,label='Reactive dispatch (weighted)');ax.set(xlabel='Free tap / shunt / droop flags',ylabel='Objective',title='M7.3: identical objective across eight configurations');ax.legend();save(fig,'objectives')
fig,axes=plt.subplots(3,1,figsize=(9,8),layout='constrained',sharex=True)
for ax,key,bounds,title in zip(axes,['tap','B','slope'],[(.95,1.05),(0,.06),(.04,.1)],['Tap 11 ratio','Bank 201 B (pu)','Droop 2 slope']):
    ax.axhspan(*bounds,color='green',alpha=.1,label='Bounds when enabled');ax.scatter(labels,[r[key] for r in rows]);ax.set(ylabel=title);ax.grid(alpha=.2)
axes[-1].set_xlabel('Free tap / shunt / droop flags');fig.suptitle('Selected continuous settings');save(fig,'settings')
fig,axes=plt.subplots(1,2,figsize=(11,5),layout='constrained')
for r in rows:
    axes[0].plot([10,20,30],r['vm'],marker='o',label=r['configuration']);axes[1].plot([7,9],r['qg'],marker='o',label=r['configuration'])
axes[0].set(xlabel='Bus ID',ylabel='Voltage (pu)',xticks=[10,20,30]);axes[1].set(xlabel='Generator ID',ylabel='Reactive output (pu)',xticks=[7,9]);axes[0].legend(title='T/S/D',fontsize=8,ncol=2);fig.suptitle('Matched operating states');save(fig,'operating_points')
fig,axes=plt.subplots(1,2,figsize=(11,4.5),layout='constrained')
for r in data['attempts']:
    if 'objective' in r:axes[0].scatter(r['configuration'],r['objective'],marker='o' if r['run']==1 else 'x',color='tab:blue' if r['valid'] else 'red')
axes[0].set(xlabel='T/S/D',ylabel='Objective',title='All starts: circles=start 1, crosses=start 2')
for k in ['tap','B','slope']:axes[1].plot(labels,[r['parameter_spread'][k] for r in rows],marker='o',label=k)
axes[1].set(xlabel='T/S/D',ylabel='Raw parameter spread (own units)',title='Parameter variability across valid starts');axes[1].legend();save(fig,'multistart')
fig,ax=plt.subplots(figsize=(8,4.5),layout='constrained');b=data['matched_droop_benefits'];ax.bar([r['equipment'] for r in b],[r['droop_objective_improvement'] for r in b]);ax.axhline(0,color='black',lw=.7);ax.set(ylabel='Objective decrease when freeing droop',title='Matched droop benefit depends on equipment freedom');save(fig,'matched_benefits')
