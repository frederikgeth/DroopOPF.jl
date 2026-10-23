"""Consolidate completed M10 regression, replay and performance evidence."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys

ROOT=Path(__file__).resolve().parents[1]

def report(out):
    regression=json.loads((out/'regression/regression.json').read_text())
    assert regression['status']=='PASS' and regression['failures']==regression['errors']==0
    protocol=json.loads((out/'regression/regression_protocol.json').read_text())
    profile=json.loads((out/'profile/summary.json').read_text())
    reproducibility=json.loads((out/'reproducibility.json').read_text())
    assert profile['status']==reproducibility['status']=='PASS'
    assert profile['accepted_attempts']==32 and profile['measured_attempts']==24
    assert reproducibility['m10_2_original_all_feasible_gate_passed'] is False
    verified_hashes=0
    for manifest in (protocol['hashes'],json.loads((out/'profile/protocol.json').read_text())['hashes']):
        for name,expected in manifest.items():
            assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==expected,('source changed during run',name)
            verified_hashes+=1
    inventory=json.loads((out/'test_inventory.json').read_text())
    for file in inventory['explicitly_included_test_files']:assert (ROOT/file).is_file()
    records=json.loads((out/'profile/attempts.json').read_text())
    assert len(records)==32 and all(r['accepted'] for r in records)
    # Preserve the checkpoint prose before replacing it with the final state.
    doc=ROOT/'docs/src/m10_3_closeout.md'
    archived=out/'checkpoint_report.md'
    if not archived.exists():shutil.copyfile(doc,archived)
    state=dict(status='READY_FOR_DOCUMENTATION_CHECK',date='2026-10-18',
        declared_scope='M10 comparative evidence, regression/reproducibility and bounded performance review; S2 excluded',
        regression=regression,reproducibility=reproducibility,
        profile=dict(status=profile['status'],accepted_attempts=32,warmups=8,measured_attempts=24,
            independent_replay_discrepancies=0,environment=profile['environment']),
        current_code_hashes_verified=verified_hashes,
        original_m10_2_all_feasible_gate_passed=False,
        m10_2_comparative_decision='54 feasible groups and one independently certified infeasible comparator',
        release_published=False,S2='paused; unchanged',
        limitations=['Finite synthetic matched/control-mode study; no general security guarantee',
            'Sourced physics comparison uses independent equations; MATPOWER itself not executed',
            'Current timing is small-network fixed-equipment known-witness OPF, not a solver ranking',
            'Large-case performance remains historical S1 evidence',
            'Transformer AVR, discrete recovery and dynamic validation remain outside declared closeout scope'])
    (out/'RESULTS.json').write_text(json.dumps(state,indent=2)+'\n')
    elapsed=regression['elapsed_seconds'];minutes=int(elapsed//60);seconds=elapsed%60
    lines=['# M10.3 reproducibility and performance closeout','',
        f'The declared M10.3 numerical gates passed: **{regression["passes"]:,} regression assertions**, zero failures/errors, reproducible M10.1/M10.2 evidence and **32 accepted serial profile runs**. The comparative closeout preserves M10.2\'s failed all-feasible gate and its certified negative fixed-Q comparator. Final documentation verification is recorded in the closeout status.','',
        '## Acceptance evidence','','| Check | Current result |','|---|---|',
        f'| Full retained regression | {regression["passes"]:,} passed, {regression["failures"]} failed, {regression["errors"]} errors, {regression["broken"]} broken; {minutes}m {seconds:.1f}s |',
        f'| Reproducibility source/code/environment hashes | {reproducibility["hash_checks"]} checks passed |',
        f'| Regression/profile current source hashes | {verified_hashes} checks passed |',
        '| M10.1 independent scalar replay | 414/414 passed |',
        '| M10.2 nominal design replay | 16/16 passed |',
        '| M10.2 operating-state replay | 108 accepted states and two expected rejected states reproduced; zero discrepancies |',
        '| M10.2 numerical report | Regenerated exactly, preserving its failed all-feasible gate |',
        '| Fixed-Q 105% certificate | Exact rational proof verified without a solver |',
        '| Corruption/proof negative controls | Six passed |',
        '| Current serial base-case profile | 32/32 accepted: eight warmups and 24 measured repetitions |','',
        '## Regression scope and control configuration','',
        'The run executes canonical `test/runtests.jl` in full mode, including core, extended numerical policies and the trailing joint-zero-deadband tests. The user explicitly confirmed the existing synthetic SCOPF configurations and necessary retries. This confirmation does not authorize a new public-network campaign.','',
        'Selected controls are tap 11 in [0.95,1.05] and continuous bank-201 susceptance B in [0,0.06] pu; the droop-security fixture uses [0.99,1.01] and [0,0.04]. Fixed-equipment fixtures remain included. Timing covers preventive/shared and corrective/per-scenario lanes. Corrective movement is either governed by absolute equipment bounds alone or by |delta tap| <=0.005 and |delta B| <=0.01 pu, as declared by each fixture.','',
        'Expected iteration/time-limit outcomes are retained by negative policy tests; a passing assertion checks their handling rather than requiring every solver attempt to succeed. The suite retains AC/droop equations and derivatives, smooth/complementarity equivalence, transformer/shunt physics and design, reactive-mode/AVR semantics, SCOPF coupling and movement budgets, paired response stages, contingency routing/ranking/filtering, checkpoint identity/replay, schema migration, corrupt-output rejection and extended initialization/solver policies. Public-network studies remain example-level evidence. The direct-include inventory and exact Julia/dependency/source hashes are retained with the regression result.','',
        '## Serial performance profile','',
        'The new profile uses the synthetic three-bus fixture and eight previously selected nominal designs. Equipment and curves are frozen; every model has ten variables and 33 constraints including variable bounds. One warmup per design precedes three measured repetitions. Execution is serial with one Julia and one BLAS thread, using Ipopt.jl 1.16.0 on Julia 1.12.4, Apple M1/aarch64. These are known-witness measurements, not a solver ranking or large-system forecast.','',
        '| Source design T/S/D | Build ms | Solve ms | Extract ms | Validate ms | Julia allocated MiB |','|---|---:|---:|---:|---:|---:|']
    for s in profile['statistics']:
        vals=[s[k]*1000 for k in ('build_seconds','solve_seconds','extraction_seconds','validation_seconds')]
        lines.append(f'| {s["tag"]} | {vals[0]:.3f} | {vals[1]:.3f} | {vals[2]:.3f} | {vals[3]:.3f} | {s["julia_allocated_mib"]:.3f} |')
    lines+=['','![Profile phases](m10_3_closeout/phases.png)','',
        'Build includes setup/model construction; solve covers optimization; extraction ends at result construction; independent physical validation is timed separately. Report serialization, disk I/O and process/package startup are excluded. Julia allocation figures cover optimizer build/solve/extraction only, excluding native allocations and later validation. Phase medians need not sum to a median end-to-end time. Timing spread does not establish a performance improvement or regression threshold.','',
        'Larger-system timing remains the historical [S1 closeout](s1_closeout.md): 96 primary combinations, six backend warmups and six bounded retries, with all combinations accepted after recovery. Its original code/environment, budgets, failures and known-witness limitations stay attached to those results. No large-case performance campaign was rerun for this closeout.','',
        '## Milestone decision and practical limits','',
        '[M10.1](m10_1_reference.md) supplies sourced terminal/shunt physics comparisons with explicit tolerances; MATPOWER itself was not executed. [M10.2](m10_2_matched.md) supplies matched nominal design and held-out control-mode comparisons with identical frozen equipment. It retains 54 feasible groups and one certified infeasible fixed-Q comparator; its original all-feasible protocol remains failed. M10.3 provides the current regression, reproduction and performance review.','',
        'Together these support closure of the declared comparative-evidence milestone after the documentation check. They do not expand public-network security qualification, close S2, validate continuous demand ranges, establish global optimality, or qualify transformer AVR, discrete equipment recovery or dynamic behavior. No release or tag is published by this closeout. The [functionality inventory](m10_audit.md) explains implemented capabilities, meanings and validation limits.','',
        '## Reproduction and retained records','',
        'After confirming the regression SCOPF fixture configuration, use a fresh regression output directory:','',
        '```sh','DROOPOPF_TEST_SUITE=full JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=. examples/m10_3_regression.jl artifacts/m10_3_closeout/regression confirmed-fixtures','python3 examples/verify_m10_reproducibility.py artifacts/m10_3_closeout','python3 examples/report_m10_3_profile.py artifacts/m10_3_closeout/profile','python3 examples/report_m10_3_closeout.py artifacts/m10_3_closeout','```','',
        'The Python report/reproduction tools require Matplotlib. The profile can be regenerated in a fresh directory with `examples/m10_3_profile.jl`. Repository directory `artifacts/m10_3_closeout` retains run protocols, full regression log/counts, source/environment hashes, independent replay, numerical report reproduction, state/timing records, CSV and final status. Historical snapshots retain their original scores.']
    text='\n'.join(lines)+'\n';doc.write_text(text)
    (out/'REPORT.md').write_text(text.replace('(m10_3_closeout/phases.png)','(profile/phases.png)').replace('(s1_closeout.md)','(../../docs/src/s1_closeout.md)').replace('(m10_1_reference.md)','(../../docs/src/m10_1_reference.md)').replace('(m10_2_matched.md)','(../../docs/src/m10_2_matched.md)').replace('(m10_audit.md)','(../../docs/src/m10_audit.md)'))
    print(json.dumps(dict(regression_passes=regression['passes'],regression_seconds=elapsed,status=state['status'],hashes_verified=verified_hashes)))

if __name__=='__main__':report(Path(sys.argv[1]).resolve())
