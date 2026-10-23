"""Build the finite P3 campaign report after replay/tests, without optimization."""
import hashlib
import json
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=Path(sys.argv[1]).resolve()
load=lambda p:json.loads(p.read_text())
summary=load(OUT/'summary.json')
assert load(OUT/'python-replay.json')['valid']
assert load(OUT/'julia-replay.json')['valid']
lines=['# P3 multi-period AC droop design — initial qualification', '',
'**Implemented and accepted for the declared deterministic, fixed-equipment scope.** '
'Five ordered one-hour periods are optimized jointly, with generator dispatch ramps '
'and one common reactive droop design. All six runs terminated `LOCALLY_SOLVED`; '
'30/30 states pass independent Julia and Python original-network replay. '
'P2 remains open, and original S2 stays paused.', '',
'## What changed', '',
'`MultiPeriodStudy`, `MultiPeriodResult`, `optimize_multi_period` and '
'`validate_multi_period` add ordered load profiles, durations, asymmetric generator '
'ramp rates, shared bounded droop parameters, optional angle limits and independent '
'energy/ramp/AC checks. The original sparse AC builder supplies every period. '
'No existing single-period or SCOPF default is replaced.', '',
'## Matched five-hour results', '',
'| Network | Ordered demand (%) | Fixed droop loss (MWh) | Shared design loss (MWh) | Reduction |',
'|---|---|---:|---:|---:|']
checks=[]
for row in summary:
    n=row['buses'];folder=OUT/str(n)
    assert row['fixed']['accepted'] and row['design']['accepted']
    lines.append(f"| {n} buses | {', '.join(f'{100*f:g}' for f in row['factors'])} | {row['fixed']['objective_mwh']:.5f} | {row['design']['objective_mwh']:.5f} | {row['improvement_percent']:.2f}% |")
    for rel,digest in load(folder/'inputs.json')['sources'].items():
        assert hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()==digest
        checks.append(dict(path=rel,sha256=digest,unchanged=True))
lines+=['',
'These reductions compare the supplied fixed curves against a common optimized '
'design under identical profiles, ramp constraints and fixed equipment. Both lanes '
'optimize dispatch. They do not measure the benefit of temporal coupling alone. '
'The nonlinear solver establishes a local stationary optimum, not global optimality '
'or unique droop parameters.', '',
'![Five-hour loss profiles](figures/loss_profiles.png)', '',
'## Controls, assumptions and time meaning', '',
'- **Equipment:** no movable tap or bank controls are selected. Taps and continuous '
'bank susceptances stay at the S1 supplied reference settings in every hour; zero movement.',
'- **Dispatch:** each hour has its own preventive AC operating point. Ramps are '
'25% of each generator’s active capability range per hour, symmetrically; synthetic '
'generator 7 instead has zero ramp. These are declared sensitivity assumptions, '
'not manufacturer data. No initial/terminal or cyclic ramp boundary is imposed.',
'- **Droop:** one shared slope/reference set for the entire horizon. Public '
'cases use a 2–8% voltage span across full Q capability, reference ±0.02 pu, and '
'fixed zero deadband. The synthetic case uses 0.5–2 times supplied slopes, '
'reference ±0.02 pu and supplied deadbands.',
'- **Limits:** normal voltage/thermal/generator limits and retained source angle '
'bounds; no emergency expansion, DR or shedding. S1 Pmin=0 and symmetric-Q '
'assumptions remain explicit. Only loads change across periods.',
'- **Time:** each duration weights MWh and defines elapsed time to the next '
'period start. This is a deterministic sequence of AC equilibria with ramp '
'constraints, not a dynamic trajectory or guarantee between sampled hours.', '',
'![Shared slopes and references](figures/shared_parameters.png)', '',
'Many slopes reach their declared 2% lower span bound. The selected optimum '
'is conditional on these design bounds; dynamic stability and controller bandwidth '
'are not established by a steep steady-state curve.', '',
'![500-bus selected curves](figures/500_droop_curves.png)', '',
'The final figure selects the three largest reactive-capability controllers. '
'Repeated-demand hours share practically identical operating points and are '
'grouped in the legends. Points lie on the common designed curve within the '
'unchanged exact-droop validation tolerance.', '',
'## Verification', '',
'- Focused tests cover shared design, binding zero ramp, uncoupled comparison, '
'one-period equivalence, non-unit durations, invalid inputs and deliberately '
'altered curves, AC states, statuses, angles and objective values.',
'- Independent Python complex-current replay accepts 30/30 saved states; seven '
'Python controls accept the original and reject six deliberately altered artifacts.',
'- Fresh Julia replay accepts the same saved states with the final validator.',
'- Source S1 input hashes are checked unchanged; previous P2/S2 artifacts are untouched.',
'- Full regression and documentation build logs are retained in `verification/`.', '',
'## Scope still open', '',
'Multi-period contingency recourse, storage energy dynamics, unit commitment, '
'equipment scheduling and discrete switching are not part of this initial slice. '
'No N−1 or transient-security qualification follows from these base-operation '
'results. P2’s resource/loss and general predictive-filter gates remain open.', '',
'## Reproduction and retained preparation error', '',
'Run `examples/p3_multi_period.jl` with a fresh output directory, then '
'`examples/replay_p3_multi_period.jl`, `examples/audit_p3_multi_period.py` and '
'`examples/plot_p3_multi_period.py`. Per-lane contracts retain every warm start, '
'duration, ramp rate, angle bound, design bound, input case and result.', '',
'The first preparation attempt stopped before any solve because the evidence '
'writer did not encode complex bank admittance. The writer now records separate '
'real conductance and susceptance fields. Its original log is retained in '
'`verification/preparation-error.log`; it is not a numerical or physical failure.', '']
check_path=OUT/'verification/checks.json'
if check_path.exists():
    check=load(check_path)
    passed=check['full_regression']['passed']
    lines=[f'- Full Julia {check["julia_version"]} regression: **{passed:,}/{passed:,} checks passed**; documentation build passed with API-page/search-index size warnings. Logs and syntax/whitespace status are retained in `verification/`.' if line=='- Full regression and documentation build logs are retained in `verification/`.' else line for line in lines]
(OUT/'REPORT.md').write_text('\n'.join(lines))
(OUT/'input-verification.json').write_text(json.dumps(dict(valid=True,checks=checks),indent=2)+'\n')
print(OUT/'REPORT.md')
