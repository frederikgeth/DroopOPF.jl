"""Render the bounded recovery and update S1 follow-up documentation; no solves."""
from pathlib import Path
import hashlib
import json
from s1_zero_deadband_reporting import append_followup
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/s1_zero_deadband/recovery'
s = json.loads((OUT / 'summary.json').read_text())
r = s['attempt']; before = s['primary_diagnosis']; after = s['recovery_diagnosis']
for path, expected in s['code_hashes'].items():
    assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == expected
for path_key, hash_key in [('source_attempt','source_sha256'),('seed_path','seed_sha256')]:
    assert hashlib.sha256((ROOT / r[path_key]).read_bytes()).hexdigest() == r[hash_key]
assert r['accepted'] == (r['solver_success'] and r['point_pass'])
b = before['point_checks']['physical']; a = after['point_checks']['physical']
old = json.loads((ROOT / r['source_attempt']).read_text())
lines = ['# S1 zero-deadband specialization: diagnosis and bounded recovery', '',
         'The S1 base-case study remains closed for its declared 14/500-bus, Pmin-zero, symmetric-Q, sampled-demand scope. This numerical follow-up implements the simplification deferred by the historical 500-bus failure analysis. It does not requalify original-Q limits, change the selected frozen 8% baseline, or establish N-1 security.', '',
         '## Formulation and equivalence', '',
         'For fixed zero lower/upper deadband widths, `max(Vref−V,0)−max(V−Vref,0) = Vref−V`. The exact model uses `Qraw = Qref + (Vref−V)/m`, retaining the existing Q-projection complementarity conditions. Each controller loses two voltage-hinge pairs and four auxiliary variables. The 51-controller 500-bus cases remove 102 pairs and 204 variables. This also applies when slopes and voltage references are free but widths stay fixed at zero. Positive or variable widths retain the general formulation.', '',
         'The smooth model uses the algebraically equivalent affine raw response, retaining Q-saturation smoothing. Exact projection witnesses and smooth values, gradients and Hessians were checked at the reference, both saturation knees and tails, with nonzero Q reference and multiple slopes. Mixed deadbands, exact-zero detection and solver diagnostics are covered. Full core/extended regression: **3,042/3,042 passed**; this is the formulation verification run saved in `artifacts/s1_zero_deadband/regression.log`, separate from the historical 2,876-check closeout run.', '',
         '## Expanded replay', '',
         '**11/12 primary attempts accepted:** all six original 90%/95% cost/loss/joint-OPF starts and five of six failed closeout-profile primaries. Saved starts, control policies, physical constraints, objectives, tolerances and 1,000-iteration/60-second budgets were preserved. All solves ran serially. Direct acceptance is not changed by a later retry.', '',
         'The 95% cost-start result has 26.577050 MW loss; loss/joint starts have 26.567590 MW, close to the historical best recovered 26.567588 MW. Numerical convergence does not imply selection of the best local equilibrium or global optimality. Timings in the expanded report are descriptive: the first new solve includes compilation, whereas the historical profile was warmed.', '',
         '## Remaining primary failure', '',
         f"The nominal 500-bus free-droop+taps+shunts design stopped with `SLOW_PROGRESS`. The largest physical imbalance was reactive balance at bus {before['worst_balance_buses'][0]['bus']}: {b['power_balance_max']:.9g} pu ({b['power_balance_max']*100:.9g} MVAr on the 100-MVA base). It exceeds the unchanged 1e-6 pu acceptance tolerance. Exact-droop residual was {b['droop_residual_max']:.9g} pu and design/equipment policies passed. Thus elimination of the voltage hinges does not remove every numerical stopping failure.", '',
         '## One bounded recovery', '',
         'Reused the original seed and control-policy settings from the historical conditioned retry: 51 independent slopes (2–8% full-Q span) and references (±0.02 pu), all 131 transformer taps within source-relative ±5%, and 11 continuous banks within their saved bank-specific bounds. This is base-case S1; controls have no inter-scenario timing. No additional movement budget or physical bound was introduced. The primary already used barrier 1e-6 and bound push/fraction 1e-8. The single retry changes only the initial barrier to 1e-8 and budgets to 3,000 iterations/120 native solver seconds, matching the previously declared S1 recovery policy.', '',
         '| Metric | Primary | Conditioned retry |', '|---|---:|---:|',
         f"| Native termination | SLOW_PROGRESS | {r['solver_status']} |",
         f"| Independent physical checks | Fail | {'Pass' if r['point_pass'] else 'Fail'} |",
         f"| Maximum AC balance residual pu | {b['power_balance_max']:.9g} | {a['power_balance_max']:.9g} |",
         f"| Exact-droop residual pu | {b['droop_residual_max']:.9g} | {a['droop_residual_max']:.9g} |",
         f"| Loss MW (primary rejected) | {json.loads((ROOT/'artifacts/s1_zero_deadband/expanded/attempts/profile-design-droop_tap_shunt-1.0-ccopt.json').read_text())['loss_mw']:.9f} | {r['loss_mw']:.9f} |",
         f"| Inner iterations | {before['ccopt_diagnostics']['inner_iterations']} | {r['ccopt_diagnostics']['inner_iterations']} |", '',
         f"**Direct score remains 11/12; accepted combinations after recovery: {s['accepted_combinations_after_recovery']}/12.** The historical conditioned witness had {old['loss_mw']:.9f} MW loss; the new retry differs by {r['loss_mw']-old['loss_mw']:+.9g} MW. Rejected primary points remain failures. No local failure is an infeasibility certificate. The degenerate one-bus free-slope test still reaches CCOpt’s iteration limit despite independent physical feasibility.", '',
         '## Independent replay', '',
         'A separate Python standard-library audit reconstructed the curves from saved settings and recomputed complex AC branch flows, nodal balances, exact droop, generator/voltage/thermal/angle limits, and equipment/design bounds for all **13 saved points** (12 primaries plus the retry). It confirmed 12 physical witnesses and the retained primary failure, with **zero classification discrepancies**. Maximum branch-component replay difference is below 1.2e-11 MW/MVAr. Evidence: `artifacts/s1_zero_deadband/expanded/independent_audit.json`.', '',
         '## Evidence and reproduction', '',
         'The original numerical attempts, cases, contracts and witnesses remain unchanged. S1 documentation and report generators now link this follow-up separately from historical scorecards. Machine-readable expanded comparisons, recovery diagnosis, saved joint designs and source/seed hashes are under `artifacts/s1_zero_deadband/`. The expanded primary report is `artifacts/s1_zero_deadband/expanded/REPORT.md`; the recovery summary is `artifacts/s1_zero_deadband/recovery/summary.json`.', '',
         '```sh', 'julia --project=. examples/s1_zero_deadband_expanded.jl',
         'python3 examples/report_s1_zero_deadband_expanded.py',
         'julia --project=. examples/s1_zero_deadband_recovery.jl',
         'python3 examples/audit_s1_zero_deadband.py',
         'python3 examples/report_s1_zero_deadband_recovery.py', '```', '']
text='\n'.join(lines)
(OUT/'REPORT.md').write_text(text)
(ROOT/'docs/src/s1_zero_deadband.md').write_text(text)
for relative, doc in [('docs/src/s1_summary.md',True),('docs/src/s1_closeout.md',True),
    ('docs/src/s1_500_results.md',True),('docs/src/s1_free_droop_results.md',True),
    ('artifacts/s1_closeout/REPORT.md',False),('artifacts/s1_arpae500/REPORT.md',False),
    ('artifacts/s1_free_droop/REPORT.md',False),('artifacts/s1_zero_deadband/REPORT.md',False)]:
    append_followup(ROOT/relative, doc=doc)
(OUT/'validation.json').write_text(json.dumps(dict(direct_acceptance=11,primary_attempts=12,
    recovered_combinations=s['accepted_combinations_after_recovery'],bounded_retries=1,
    recovery_accepted=r['accepted'],source_and_seed_hashes_verified=True,code_hashes_verified=True),indent=2)+'\n')
print('S1 follow-up reports updated; direct 11/12; recovered',s['accepted_combinations_after_recovery'],'/12')
