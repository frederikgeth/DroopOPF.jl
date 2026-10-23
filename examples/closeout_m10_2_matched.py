"""Review M10.2 comparative evidence without changing the failed all-feasible gate."""
import hashlib
import json
from pathlib import Path
import sys
from report_m10_2_matched import replay
from m10_2_fixedq_certificate import verify

def closeout(out):
    root=Path(__file__).resolve().parents[1]
    p=json.loads((out/'protocol.json').read_text());r=json.loads((out/'RESULTS.json').read_text())
    assert p['expected_groups']==r['groups']==55 and r['attempts']==110 and r['nominal_saved_replays']==16
    assert r['groups_accepted']==54 and r['accepted_attempts']==108 and r['independent_replay_discrepancies']==0
    assert len(r['failures'])==2 and all(x['group']=='111-fixed_q-1.05' for x in r['failures'])
    assert all(x['accepted']>0 for x in r['summaries'] if x['group']!='111-fixed_q-1.05')
    for family in ('source_hashes','code_environment_hashes'):
        for name,expected in p[family].items():assert hashlib.sha256((root/name).read_bytes()).hexdigest()==expected,name
    for x in json.loads((out/'nominal_replay.json').read_text()): assert replay(x['physical_case'],x['result'])['valid']
    for x in json.loads((out/'attempts.json').read_text()):
        study=json.loads((out/x['case_file']).read_text())['data']
        check=replay(study['case'],x.get('result',{}),study['reactive_assignments'])
        native=x.get('result',{}).get('termination_status') in ('OPTIMAL','LOCALLY_SOLVED','ALMOST_LOCALLY_SOLVED')
        assert (check['valid'] and native)==x['valid']
    cert=verify(out/'cases/111-fixed_q-1.05.json',out/'fixedq_certificate/certificate.json')
    decision=dict(status='COMPLETE_FOR_DECLARED_COMPARATIVE_SCOPE',original_all_feasible_gate_passed=False,
        original_results_status=r['status'],feasible_groups=54,certified_infeasible_groups=1,
        total_groups=55,saved_nominal_replays=16,fresh_opf_attempts=110,rejected_attempts_retained=2,
        droop_grid_feasible_groups=40,control_mode_feasible_groups_including_reused_droop=19,
        certificate=cert,
        rationale='Original comparative milestone requires matched studies, held-out margins and retained failures. The stricter run protocol required all groups feasible and remains failed. Every comparison now has either accepted physical evidence or a verified infeasibility certificate; no limits, targets or acceptance tolerances changed.',
        limitations=['Synthetic base-case scope only','Finite sampled demands, no continuous-range guarantee',
            'Local solutions, no global objective comparison','No discrete recovery','Transformer AVR and dynamics excluded','No SCOPF or S2 run'],
        next_step='M10.3 reproducibility and regression/performance closeout')
    (out/'CLOSEOUT.json').write_text(json.dumps(decision,indent=2)+'\n')
    # Keep the original all-feasible report and objective plot unchanged.
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,axes=plt.subplots(1,2,figsize=(10.5,4.3))
    for mode in ('droop','fixed_q','free_q','avr'):
        rows=sorted([x for x in r['summaries'] if x['tag']=='111' and x['mode']==mode and x['metrics']],key=lambda x:x['factor'])
        axes[0].semilogy([x['factor'] for x in rows],[x['metrics']['objective'] for x in rows],marker='o',label=mode)
        axes[1].plot([x['factor'] for x in rows],[x['metrics']['voltage_margin_pu'] for x in rows],marker='o',label=mode)
    axes[0].set(xlabel='Demand factor',ylabel='Dispatch-deviation objective (log scale)',title='Matched frozen-equipment control modes')
    axes[1].set(xlabel='Demand factor',ylabel='Minimum voltage margin (pu)',title='Margins of accepted local states')
    for ax in axes:ax.grid(alpha=.2);ax.legend(fontsize=8)
    axes[0].annotate('FixedQ at 1.05:\ncertified infeasible',xy=(1.05,0.001),xytext=(1.004,0.01),arrowprops=dict(arrowstyle='->'),fontsize=8)
    fig.tight_layout();fig.savefig(out/'control_modes.png',dpi=160);plt.close(fig)
    body=f'''# M10.2 comparative evidence closeout

The declared synthetic base-case comparison package is complete: **54 feasible groups and one certified infeasible comparator**, covering all 55 planned groups. The original all-feasible protocol gate **failed and remains failed** in `RESULTS.json` and `REPORT.md`. No operating limits, fixed targets or tolerances were changed to obtain this decision.

## Functionality and evidence

All eight nominal tap/shunt/droop design configurations were replayed from both saved starts, and all 40 frozen-droop configuration/demand groups passed. Demand factors are 0.95, 0.975, 1.0, 1.025 and 1.05; four were declared held-out before solving. Two nominal starts were used per group with equipment and curves frozen. The matched nominal design comparisons hold equipment freedom and objective fixed; held-out rankings concern separately selected frozen designs.

On the same tag-111 equipment, droop, FreeQ and generator AVR passed all five demand points. FixedQ passed four; both attempts at 105% demand were rejected with AC residual near 7.25e-4 pu at the voltage ceiling. All **110 fresh attempts**, both failures, and **16 historical nominal replays** are retained. Independent scalar-equation replay found zero discrepancies.

The comparison uses the dispatch-deviation objective, with losses reported separately. FixedQ schedules and AVR targets are calibrated once at nominal demand. FreeQ has additional reactive-dispatch freedom within unchanged generator limits; it is a different policy, not a realized automatic controller. The two-start spread does not establish global optimality.

![Matched mode objectives and margins](control_modes.png)

![Frozen design margins](margins.png)

## FixedQ exception and proof

The failed comparator is the unchanged fixed-Q 105% case. Discovery used a Hermitian voltage-product outer relaxation, with 15 rational PSD directions. Verification reconstructs 45 rational linear inequalities from the saved case, including rigorous Taylor enclosures for the 0.02-radian phase, voltage bounds expanded by the validation tolerance, and allowances for AC-balance and fixed-Q residuals. Any physical AC state would satisfy these relaxed inequalities.

Nonnegative rational multipliers yield a strictly positive minimum contradiction over the voltage-product box. The exact positive gap is retained as a rational number; its decimal value is **{cert['positive_gap']:.9g}**. This is a normalized algebraic gap, not a power shortage. The verifier needs only Python's standard library and does not trust a solver infeasibility status. Thermal and generator-Q capability constraints are omitted from this outer relaxation, which enlarges the candidate set; proving even this set empty is sufficient.

The certificate excludes this fixed nominal-Q policy at 105% demand under the declared settings and tolerances. It does not exclude other reactive policies: droop, FreeQ and AVR have accepted states for the same equipment and demand. No remedies or retuning were used in the comparison.

Verify the proof independently:

```sh
python3 examples/m10_2_fixedq_certificate.py verify artifacts/m10_2_matched/cases/111-fixed_q-1.05.json artifacts/m10_2_matched/fixedq_certificate/certificate.json
```

Rebuild the closeout with Python and Matplotlib:

```sh
python3 examples/closeout_m10_2_matched.py artifacts/m10_2_matched
```

`CLOSEOUT.json` states the comparative decision separately from the failed all-feasible result. `comparison.csv`, `independent_replay.json`, `nominal_replay.json`, `protocol.json`, `cases/`, `attempts/`, and `fixedq_certificate/` retain traceable evidence. The milestone is complete for this finite synthetic base-case scope; public-network/control-policy expansion, transformer AVR, discrete recovery and dynamic behavior remain separate work. S2 is unchanged. The next milestone slice is M10.3.
'''
    (out/'CLOSEOUT.md').write_text(body)
    files=[Path(__file__),root/'examples/m10_2_fixedq_certificate.py',out/'protocol.json',out/'RESULTS.json',out/'fixedq_certificate/certificate.json',out/'fixedq_certificate/protocol.json',out/'CLOSEOUT.json']
    (out/'closeout_manifest.json').write_text(json.dumps({str(x.relative_to(root)):hashlib.sha256(x.read_bytes()).hexdigest() for x in files},indent=2)+'\n')
    print(json.dumps({k:decision[k] for k in ('status','original_all_feasible_gate_passed','feasible_groups','certified_infeasible_groups','fresh_opf_attempts')}))

if __name__=='__main__':closeout(Path(sys.argv[1]).resolve())
