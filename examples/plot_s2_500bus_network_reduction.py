"""Sparsity comparison; original branch constraints remain in every formulation."""
import sys
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from analyse_s2_500bus_network_reduction import load,BASE,partition,admittance,ROOT

s=load(BASE/'pilot_study.json')['data'];y=admittance(s['case'],{},{});panels=[('Original network',y)]
for mode,label in (('all','123 buses eliminated'),('independent-degree3','70 buses eliminated')):
    r,e=partition(s,mode);h=-np.linalg.solve(y[np.ix_(e,e)],y[np.ix_(e,r)])
    panels.append((label,y[np.ix_(r,r)]+y[np.ix_(r,e)]@h))
fig,axes=plt.subplots(1,3,figsize=(12,4.4),layout='constrained')
for ax,(name,a) in zip(axes,panels):
    ax.spy(abs(a)>1e-12,markersize=.65,color='#185b85')
    ax.set_title(f'{name}\n{len(a)} buses; {np.count_nonzero(abs(a)>1e-12):,} nonzeros')
    ax.set_xlabel('Bus index');ax.set_ylabel('Bus index');ax.xaxis.set_ticks_position('bottom')
fig.suptitle('Exact zero-injection reduction: variable count versus admittance fill-in',fontsize=13)
out=ROOT/'docs/src/assets/s2_500bus/network_reduction';out.mkdir(parents=True,exist_ok=True)
for ext in ('png','pdf'):fig.savefig(out/f'admittance-sparsity.{ext}',dpi=180)
print(out/'admittance-sparsity.png')
