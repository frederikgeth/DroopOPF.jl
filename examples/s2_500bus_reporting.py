"""Operating envelopes of independently qualified saved 500-bus designs."""
import copy
import numpy as np
import matplotlib.pyplot as plt
from audit_s2_arpae500 import OUT, ROOT, data, load
from s2_followup_physics import check_case


def nominal_selection():
    p = OUT/'qualification/summary-expanded-madnlp-reserve.json'
    if not p.exists() or not load(p)['accepted']:
        return None
    return p, load(p)


def nominal_envelopes(figures):
    selected = nominal_selection()
    if selected is None:
        return []
    path, phase = selected
    master = OUT/phase['selected']
    study = data(master/'optimized-1.0.json')
    result = data(master/'result-1.0.json')
    label = path.stem.removeprefix('summary-')
    scan = load(OUT/f"qualification/{label}/round-{phase['rounds'][-1]['round']}/demand-1.0/scan.json")
    assert scan['exhaustive'] and len(scan['attempts']) == 389 and not scan['failed']
    records = [('base', study['case'], result['states']['base'], result['tap_settings']['base'], result['shunt_settings']['base'])]
    for row in scan['attempts']:
        folder = OUT/row['final']['name']
        r, s = data(folder/'result.json'), data(folder/'input.json')
        sid = row['event']
        case = copy.deepcopy(s['case'])
        event = s['contingencies'][0]
        for b in case['network']['branches']:
            if b['id'] in event['branch_ids']:
                b['available'] = False
        for g in case['generators']:
            if g['id'] in event['generator_ids']:
                g['available'] = False
        records.append((sid, case, r['states'][sid], r['tap_settings'][sid], r['shunt_settings'][sid]))
    c = study['case']
    gens = [(i, g) for i, g in enumerate(c['generators']) if g['available']]
    gids = [g['id'] for i, g in gens]
    branches = [b for b in c['network']['branches'] if b['available']]
    bids = [b['id'] for b in branches]
    angles = load(ROOT/'artifacts/s1_free_droop/500/angle_limits.json')
    flows = []
    for sid, case, state, taps, banks in records:
        check = check_case(case, state, taps, banks, angles)
        assert check['valid'], sid
        flows.append([100*check['branch_max_terminal_s_pu'].get(str(b['id']), np.nan)/b['thermal_limit'] for b in branches])
    fig, axes = plt.subplots(3, 1, figsize=(13, 10), constrained_layout=True)
    for ax, field, prefix, unit in zip(axes[:2], ['pg', 'qg'], ['p', 'q'], ['MW', 'MVAr']):
        values = np.array([[r[2][field][i]*c['base_power'] for i, g in gens] for r in records])
        ax.fill_between(gids, values.min(axis=0), values.max(axis=0), alpha=.3, label='390-state min–max envelope')
        ax.plot(gids, values[0], lw=1, label='common base')
        for bound in ['min', 'max']:
            ax.plot(gids, [g[f'{prefix}_{bound}']*c['base_power'] for i, g in gens], 'k--', lw=.8)
        ax.set_xlabel('Generator ID')
        ax.set_ylabel(f'{prefix.upper()} generation ({unit})')
    values = np.array(flows)
    axes[2].fill_between(bids, np.nanmin(values, axis=0), np.nanmax(values, axis=0), alpha=.3)
    axes[2].plot(bids, values[0], lw=.7)
    axes[2].axhline(100, color='black', ls='--')
    axes[2].set_xlabel('Branch ID')
    axes[2].set_ylabel('Max terminal |S| / Rate A (%)')
    for ax in axes:
        ax.grid(alpha=.2)
    axes[0].legend(fontsize=8)
    fig.suptitle('500-bus MadNLP: common nominal base and all 389 connected outages')
    names = ['nominal-qualified-generation-flows.png']
    fig.savefig(figures/names[-1], dpi=150)
    plt.close(fig)
    fig, axes = plt.subplots(3, 1, figsize=(13, 10), constrained_layout=True)
    busids = [b['id'] for b in c['network']['buses']]
    taps = sorted(map(int, result['tap_settings']['base']))
    banks = sorted(map(int, result['shunt_settings']['base']))
    arrays = [np.array([r[2]['vm'] for r in records]),
              np.array([[r[3].get(str(i), np.nan) for i in taps] for r in records]),
              np.array([[r[4][str(i)] for i in banks] for r in records])]
    for ax, ids, values, xlabel, ylabel in zip(axes, [busids, taps, banks], arrays,
            ['Bus ID', 'Transformer ID', 'Bank ID'], ['Voltage (pu)', 'Tap ratio', 'Susceptance (pu)']):
        ax.fill_between(ids, np.nanmin(values, axis=0), np.nanmax(values, axis=0), alpha=.3, label='390-state min–max envelope')
        ax.plot(ids, values[0], lw=1, label='common base')
        ax.set_xlabel(xlabel)
        ax.set_ylabel(ylabel)
        ax.grid(alpha=.2)
    for key in ['v_min', 'v_max']:
        axes[0].plot(busids, [b[key] for b in c['network']['buses']], 'k--', lw=.8)
    for bound in [.95, 1.05]:
        axes[1].axhline(bound, color='black', ls='--')
    bounds = {b['bank_id']: b for b in study['shunt_controls']}
    for key in ['lower', 'upper']:
        axes[2].plot(banks, [bounds[i][key] for i in banks], 'k--', lw=.8)
    axes[0].legend(fontsize=8)
    fig.suptitle('500-bus MadNLP: corrective equipment across all 389 connected outages')
    names.append('nominal-qualified-voltage-equipment.png')
    fig.savefig(figures/names[-1], dpi=150)
    plt.close(fig)
    return names
