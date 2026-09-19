"""Plot fixed-shunt analytical checks from the M6.1 JSON evidence."""
import json
import sys
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

out=Path(sys.argv[1])
data=json.loads((out/'evidence.json').read_text())
plt.rcParams.update({'font.size':10,'axes.spines.top':False,'axes.spines.right':False})
fig,axes=plt.subplots(1,2,figsize=(11,4.5),layout='constrained')
for name,color in [('capacitor','#2563eb'),('reactor','#c2410c'),('conductance','#15803d')]:
    rows=[r for r in data['sweeps'] if r['equipment']==name]
    for ax,component in zip(axes,['p','q']):
        # All three share the same G; plot the common active-power curve once.
        if component=='p' and name!='conductance':
            continue
        x=[r['voltage_pu'] for r in rows]
        label='All devices: G = 0.04' if component=='p' else f"{name}: B = {rows[0]['b_pu']}"
        ax.plot(x,[r['expected_'+component] for r in rows],color=color,label=label)
        ax.plot(x,[r['actual_'+component] for r in rows],color=color,linestyle='none',marker='o',markersize=4,markerfacecolor='none')
for ax,label in zip(axes,['Active consumption P (pu)','Reactive consumption Q (pu)']):
    ax.set(xlabel='Voltage magnitude (pu)',ylabel=label)
    ax.axhline(0,color='gray',lw=.7); ax.grid(alpha=.2); ax.legend(fontsize=8)
fig.suptitle('M6.1 · Fixed shunts: analytic lines and computed markers')
fig.savefig(out/'shunt_voltage_curves.png',dpi=160)
fig.savefig(out/'shunt_voltage_curves.pdf')
plt.close(fig)
fig,ax=plt.subplots(figsize=(7,4),layout='constrained')
rows=data['negative_checks']
ax.bar([r['case'] for r in rows],[r['ac_residual'] for r in rows],color='#b91c1c')
ax.axhline(1e-6,color='#111827',linestyle='--',label='Acceptance tolerance: 1e-6 pu')
ax.set_yscale('log'); ax.set_ylim(1e-7,1)
ax.set(ylabel='Maximum AC residual (pu)',title='Deliberate errors correctly rejected')
ax.legend(fontsize=9); ax.grid(axis='y',alpha=.2)
fig.savefig(out/'accounting_checks.png',dpi=160)
fig.savefig(out/'accounting_checks.pdf')
plt.close(fig)
