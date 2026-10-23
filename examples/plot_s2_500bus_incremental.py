"""Accepted native feasibility designs; do not label these as loss optima."""
from pathlib import Path
import json
import shutil
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/s2_scopf/ieee500_native/incremental_shared_recovery'
FIG = OUT / 'figures'
DOC = ROOT / 'docs/src/assets/s2_500bus/incremental_shared_recovery'


def main():
    FIG.mkdir(exist_ok=True); DOC.mkdir(parents=True, exist_ok=True)
    fig, axes = plt.subplots(2, 1, figsize=(12, 7), constrained_layout=True)
    for solver in ('ipopt', 'madnlp'):
        folder = OUT / f'normal-zero-{solver}-3d-r1-feasibility-p1'
        assert json.loads((folder / 'summary.json').read_text())['accepted']
        study = json.loads((folder / 'controller-feasibility.json').read_text())['data']
        controls = study['case']['controls']; attachments = study['case']['attachments']
        gen = [a['generator_id'] for a in attachments]
        ds = [controls[a['control_id'] - 1] for a in attachments]
        axes[0].plot(gen, [d['slope'] * (d['capability']['q_max'] - d['capability']['q_min']) for d in ds], '.-', label=solver)
        axes[1].plot(gen, [d['schedule']['v_ref'] for d in ds], '.-', label=solver)
        states = json.loads((folder / 'point-feasibility.json').read_text())['states']
        eqfig, eqaxes = plt.subplots(2, 1, figsize=(13, 9), constrained_layout=True)
        for ax, key, controls, id_key, title in zip(eqaxes, ('taps', 'banks'), (study['tap_controls'], study['shunt_controls']),
                                                  ('branch_id', 'bank_id'), ('Transformer taps', 'Continuous shunt susceptance')):
            ids = [str(c[id_key]) for c in controls]
            values = np.array([[s[key].get(i, np.nan) for i in ids] for s in states])
            lo = np.array([c['lower'] for c in controls]); hi = np.array([c['upper'] for c in controls])
            normalized = (values - lo) / (hi - lo)
            assert np.nanmin(normalized) >= -1e-5 and np.nanmax(normalized) <= 1 + 1e-5
            im = ax.imshow(normalized, aspect='auto', vmin=0, vmax=1, cmap='viridis')
            ax.set_yticks(range(len(states)), [f"{s['factor']*100:g}% / {s['id']}" for s in states], fontsize=7)
            step = max(1, len(ids)//16); ax.set_xticks(range(0, len(ids), step), ids[::step])
            ax.set_title(title); eqfig.colorbar(im, ax=ax, label='Fraction of allowed range')
        eqfig.suptitle(f'{solver}: accepted shared 90/95/100% feasibility design; loss optimum unresolved')
        save(eqfig, f'{solver}-shared-equipment')
    axes[0].set_ylabel('Slope × reactive capability span (pu V)')
    axes[1].set_ylabel('Reference voltage (pu)'); axes[1].set_xlabel('Generator ID')
    for ax in axes: ax.grid(alpha=.25); ax.legend()
    fig.suptitle('Shared 90/95/100% native feasibility designs — five critical outages per demand\nNormal ratings, exactly zero DR/shedding; loss optimum and exhaustive qualification unresolved')
    save(fig, 'shared-feasibility-droop-parameters')


def save(fig, name):
    for suffix in ('png', 'pdf'):
        fig.savefig(FIG / f'{name}.{suffix}', dpi=160)
    shutil.copyfile(FIG / f'{name}.png', DOC / f'{name}.png')
    plt.close(fig)


if __name__ == '__main__': main()
