"""Render compact documentation figures from the bundled evidence summary.

Requires matplotlib; no network inputs, solver, or private archives are needed.
Run from any directory: python3 tools/release/plot_validation_references.py
"""
from pathlib import Path
import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
root = Path(__file__).resolve().parents[2]
out = root / 'docs/src/assets/validation'
data = json.loads((out / 'summary.json').read_text())
plt.rcParams.update({'font.size': 10, 'figure.dpi': 140})
fig, axes = plt.subplots(1, 2, figsize=(10, 3.8), layout='constrained')
for ax, metric, title in zip(axes, ['balance_pu','droop_pu'], ['AC power balance', 'Exact droop']):
    for key, label, marker in [('julia_rows','Julia replay','o'),('python_rows','Independent Python replay','s')]:
        vals = [max(row[metric] for row in data[key] if row['period']==p) for p in range(1,6)]
        ax.semilogy(range(1,6), vals, marker=marker, label=label)
    ax.set(title=title, xlabel='Period (one hour each)', ylabel='Maximum residual (pu)', xticks=range(1,6))
    ax.grid(alpha=.25); ax.legend(fontsize=8)
fig.suptitle('Selected joint model: base + outages 21, 36, 562 (20 states)')
fig.savefig(out / 'joint_replay.png'); plt.close(fig)
fig, ax = plt.subplots(figsize=(8,4), layout='constrained')
for gen in sorted(data['avr_targets'][0], key=int):
    ax.plot(range(1,6), [p[gen] for p in data['avr_targets']], marker='.', label=gen)
ax.set(title='Preventive AVR schedule — 15 generators', xlabel='Period (demand: 90 / 100 / 105 / 100 / 90%)', ylabel='Voltage setpoint (pu)', xticks=range(1,6))
ax.grid(alpha=.25); ax.legend(title='Generator', ncol=3, fontsize=7, loc='center left', bbox_to_anchor=(1, .5))
fig.savefig(out / 'avr_schedule.png'); plt.close(fig)
