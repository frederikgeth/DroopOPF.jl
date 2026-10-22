"""Independent raw-MATPOWER equipment reference and comparison; no optimization.

prepare OUT: create deterministic snapshots and reference values
report OUT: compare Julia evaluation, assert acceptance, write tables and plots
"""
import csv
import hashlib
import json
import math
from pathlib import Path
import re
import sys

ATOL = 2e-11
RTOL = 2e-11
ROOT = Path(__file__).resolve().parents[1]

def table(text, name):
    body = re.search(r'mpc\.' + name + r'\s*=\s*\[(.*?)\];', text, re.S)[1]
    body = re.sub(r'%[^\n]*', '', body)
    return [[float(x) for x in row.split()] for row in body.split(';') if row.strip()]

def replace_table(text, name, rows):
    body = '\n' + '\n'.join(' '.join(format(x, '.17g') for x in row) + ';' for row in rows) + '\n'
    return re.sub(r'(mpc\.' + name + r'\s*=\s*\[).*?(\];)', lambda m: m[1]+body+m[2], text, flags=re.S)

def reference(bus, branches, vm, va, base, fault=None):
    # Scalar polar terminal equations, independently parsed from source tables.
    # Convention matches MATPOWER makeYbus (from-side complex tap).
    idx = {int(row[0]): i for i, row in enumerate(bus)}
    sf, st = [], []
    injection = [0j for _ in bus]
    for row in branches:
        i, j = idx[int(row[0])], idx[int(row[1])]
        if row[10] == 0:
            sf.append(0j); st.append(0j); continue
        g_b = 1 / complex(row[2], row[3]); g, b = g_b.real, g_b.imag
        t = row[8] or 1.0
        if fault == 'reciprocal_tap': t = 1/t
        phase = math.radians(row[9]) * (-1 if fault == 'phase_sign' else 1)
        d = va[i]-va[j]-phase
        vi, vj = vm[i], vm[j]
        p = g*vi*vi/t**2 - vi*vj/t*(g*math.cos(d)+b*math.sin(d))
        q = -(b+row[4]/2)*vi*vi/t**2 + vi*vj/t*(b*math.cos(d)-g*math.sin(d))
        pr = g*vj*vj - vi*vj/t*(g*math.cos(-d)+b*math.sin(-d))
        qr = -(b+row[4]/2)*vj*vj + vi*vj/t*(b*math.cos(-d)-g*math.sin(-d))
        sf.append(complex(p,q)); st.append(complex(pr,qr))
        injection[i] += sf[-1]; injection[j] += st[-1]
    shunts = []
    for k, row in enumerate(bus):
        if row[4] or row[5]:
            power = complex(row[4], row[5] if fault == 'shunt_sign' else -row[5])*vm[k]**2/base
            shunts.append(power); injection[k] += power
    pairs = lambda xs: [[x.real,x.imag] for x in xs]
    return dict(from_=pairs(sf), to=pairs(st), shunts=pairs(shunts), injection=pairs(injection))

def prepare(out):
    source = out/'source/case14.m'; text = source.read_text()
    bus, branch = table(text,'bus'), table(text,'branch')
    base = float(re.search(r'mpc.baseMVA\s*=\s*([^;]+)', text)[1])
    assert len(bus)==14 and len(branch)==20
    assert sum(r[8] not in (0,1) for r in branch)==3
    assert sum(bool(r[4] or r[5]) for r in bus)==1
    snapshots, refs = [], []
    for label in ('published', 'signed_phase_and_conductance', 'offline_branch'):
        bs = [r[:] for r in bus]; br = [r[:] for r in branch]
        vm = [r[7] for r in bs]; va = [math.radians(r[8]) for r in bs]
        path = source
        if label != 'published':
            br[7][9], br[8][9] = 11.0, -7.0
            bs[8][4] = 2.5
            vm = [v*(0.97+0.003*(i%5)) for i,v in enumerate(vm)]
            va = [v+0.004*math.sin(i) for i,v in enumerate(va)]
            if label == 'offline_branch': br[7][10] = 0
            path = out/(label+'.m')
            path.write_text(replace_table(replace_table(text,'bus',bs),'branch',br))
        snapshots.append(dict(id=label,case_path=str(path.resolve()),vm=vm,va=va))
        ref = reference(bs,br,vm,va,base); ref['from'] = ref.pop('from_'); ref['ybus_injection'] = ref['injection']
        faults = {}
        for fault, key in [('reciprocal_tap','from_'),('phase_sign','from_'),('shunt_sign','shunts')]:
            bad = reference(bs,br,vm,va,base,fault)
            good = ref['from' if key=='from_' else key]
            faults[fault] = max(abs(a-b) for x,y in zip(bad[key],good) for a,b in zip(x,y))
        refs.append(dict(id=label,values=ref,negative_controls=faults))
    (out/'inputs.json').write_text(json.dumps(dict(snapshots=snapshots),indent=2)+'\n')
    (out/'reference.json').write_text(json.dumps(refs,indent=2)+'\n')
    files = [source,out/'source/makeYbus.m',out/'source/LICENSE',ROOT/'examples/m10_1_reference.jl',Path(__file__),ROOT/'Project.toml',ROOT/'Manifest.toml',ROOT/'src/physics.jl',ROOT/'src/matpower.jl',ROOT/'src/network.jl']
    manifest = dict(source_release='MATPOWER 8.1', date='2026-10-18',
        case_url='https://raw.githubusercontent.com/MATPOWER/matpower/8.1/data/case14.m',
        equations_url='https://raw.githubusercontent.com/MATPOWER/matpower/8.1/lib/makeYbus.m',
        license='MATPOWER BSD 3-clause; upstream source and license retained verbatim',
        hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
        absolute_tolerance_pu=ATOL, relative_tolerance=RTOL,
        snapshot_scope='Published voltages, not a newly solved or feasibility-qualified state; other snapshots explicitly modified',
        optimization_runs=0)
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')

def report(out):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    refs = json.loads((out/'reference.json').read_text())
    actual = json.loads((out/'actual.json').read_text())
    assert [r['id'] for r in refs] == [r['id'] for r in actual['snapshots']]
    rows=[]; checks=[]
    for ref, got in zip(refs,actual['snapshots']):
        for kind in ('from','to','shunts','injection','ybus_injection'):
            expected, observed = ref['values'][kind], got[kind]
            assert len(expected)==len(observed)
            for i,(exp,obs) in enumerate(zip(expected,observed),1):
                for component,a,b in zip(('P','Q'),exp,obs):
                    err=abs(a-b); limit=ATOL+RTOL*abs(a)
                    rows.append(dict(snapshot=ref['id'],kind=kind,index=i,component=component,
                                     reference_pu=a,computed_pu=b,absolute_error_pu=err,tolerance_pu=limit))
                    assert math.isfinite(b) and err<=limit, rows[-1]
        for fault,delta in ref['negative_controls'].items():
            # Phase sensitivity requires the labelled signed-phase variant.
            required = fault != 'phase_sign' or ref['id'] != 'published'
            if required: assert delta > 1e-4, (ref['id'],fault,delta)
            checks.append(dict(snapshot=ref['id'],fault=fault,max_error_pu=delta,required=required,detected=delta>1e-4))
    with (out/'comparison.csv').open('w') as f:
        writer=csv.DictWriter(f,fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    max_error=max(r['absolute_error_pu'] for r in rows)
    assert len(rows)==414
    result=dict(status='PASS',scalar_checks=len(rows),max_absolute_error_pu=max_error,
        negative_controls=checks,julia_version=actual['julia_version'],python_version=sys.version,matplotlib_version=matplotlib.__version__,optimization_runs=0)
    (out/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    fig, axes = plt.subplots(1,2,figsize=(11,4.3))
    native=[r for r in rows if r['snapshot']=='published' and r['kind'] in ('from','to')]
    for comp, marker in [('P','o'),('Q','x')]:
        rs=[r for r in native if r['component']==comp]
        axes[0].scatter([r['reference_pu'] for r in rs],[r['computed_pu'] for r in rs],s=22,marker=marker,label=comp)
    limits=axes[0].get_xlim(); axes[0].plot(limits,limits,color='gray',linestyle='--'); axes[0].legend()
    axes[0].set(xlabel='Independent reference (pu)',ylabel='DroopOPF (pu)',title='Published case: both terminal powers')
    for label in [r['id'] for r in refs]:
        rs=[r for r in rows if r['snapshot']==label]
        axes[1].semilogy(range(len(rs)),[max(r['absolute_error_pu'],1e-17) for r in rs],label=label)
    axes[1].axhline(ATOL,color='red',linestyle='--',label='absolute tolerance')
    axes[1].set(xlabel='Scalar comparison index',ylabel='Absolute error (pu)',title='Terminal, shunt and bus injection errors')
    axes[1].legend(fontsize=7); fig.tight_layout()
    fig.savefig(out/'comparison.png',dpi=160); fig.savefig(out/'comparison.svg'); plt.close(fig)
    (out/'REPORT.md').write_text(f'''# M10.1 sourced equipment physics comparison

Acceptance: **PASS**. {len(rows)} scalar comparisons across three voltage snapshots; maximum absolute error **{max_error:.3e} pu**. Acceptance is |error| <= {ATOL:g} + {RTOL:g}|reference| pu. No optimization was run.

## Source and reference method

The unmodified [MATPOWER 8.1 IEEE 14-bus case](https://github.com/MATPOWER/matpower/blob/8.1/data/case14.m) supplies 20 branches, three off-nominal taps (0.978, 0.969, 0.932), and a bus-9 shunt of +19 MVAr at 1 pu. Source files, the BSD license, release URLs and SHA-256 hashes are retained in `source` and `manifest.json`.

The independent Python parser reads raw MATPOWER bus/branch tables. Scalar polar terminal equations follow the conventions of [MATPOWER makeYbus](https://github.com/MATPOWER/matpower/blob/8.1/lib/makeYbus.m); they do not call DroopOPF admittance, parser or flow helpers. DroopOPF separately imports each case and evaluates terminal P/Q, fixed-shunt consumption and total bus injections through both terminal summation and the optimizer admittance matrix. Capacitive shunt consumption is negative Q. MATPOWER itself was not executed; this is a sourced equation-reference comparison, not an external-solver benchmark.

## Snapshot scope and sensitivity

The published snapshot uses the supplied Vm/Va unchanged. These rounded voltages are not claimed to satisfy AC balance or source operational limits. The source has zero branch ratings (unspecified), and some published voltages exceed its OPF voltage bounds. No thermal, OPF, droop or security qualification follows from this physics comparison.

Two explicitly derived snapshots add +11/-7 degree transformer phase shifts, bus-9 conductance of 2.5 MW at 1 pu, deterministic voltage perturbations, and then an offline transformer. They exercise signed phase, active shunt consumption, V-squared scaling and zero flow on an unavailable device. These modifications are not source-case operating results.

Negative controls replace ratios by reciprocals, reverse phase signs and reverse the shunt-Q convention. Every applicable control must cause a discrepancy greater than 1e-4 pu; phase-sign sensitivity is inapplicable to the zero-phase published snapshot. Detailed outcomes are in `RESULTS.json`. This detects three plausible convention errors rather than only comparing two agreeing calculations.

![Reference and error comparisons](comparison.png)

## Reproduction and acceptance records

From the repository root, using Python with Matplotlib and Julia with this project:

```sh
python3 examples/report_m10_1_reference.py prepare artifacts/m10_1_reference
julia --project=. examples/m10_1_reference.jl artifacts/m10_1_reference/inputs.json artifacts/m10_1_reference/actual.json
python3 examples/report_m10_1_reference.py report artifacts/m10_1_reference
```

`comparison.csv` retains every expected/computed component and its tolerance; `reference.json`, `inputs.json` and `actual.json` retain the numerical inputs and outputs. `manifest.json` records source and runner hashes. This is example-level reference evidence; the public case is not added to the package unit suite. M10.1's sourced equipment-physics package is complete for this declared scope. M10.2 matched studies and M10.3 overall closeout remain open; S2 is unchanged.
''')
    print(json.dumps({k:v for k,v in result.items() if k!='negative_controls'}))

if __name__=='__main__':
    mode=sys.argv[1]; out=Path(sys.argv[2]).resolve()
    {'prepare':prepare,'report':report}[mode](out)
