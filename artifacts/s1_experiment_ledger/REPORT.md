# S1 frozen-test experiment ledger

This is the compact index of the retained S1 evidence as of 2026-09-23. It
separates *paired frozen-matrix experiments* from recovery/diagnostic work, so
an extra solve, transferred seed, or looser diagnostic threshold is never
mistaken for a replacement frozen acceptance decision.

The machine-readable [`contract-ledger.json`](contract-ledger.json) freezes the
24-cell baseline contract and records, for every cell, its strict decision,
residuals, final status, retained iterate and diagnostics, seed lineage, and
same-case feasibility witnesses. Its source-file hashes make silent replacement
of the underlying policy summaries or feasibility audit detectable. Generate it
with `examples/s1_frozen_contract_ledger.jl`; the generator rejects an altered
solver, network, load, start, cell-count, or retained-iterate contract.

Legend: `I` = Ipopt; `M` = MadNLP; `C` = CCOpt; `B` = frozen explicit
baseline; `N` = bounds-normalized coordinates; `IQ` = implied attached-Q
bounds; `RQ` = reduced-space droop-Q; `EC` = epsilon continuation; `XS` =
accepted-state cross-seed. `+/-` means gains/losses against B. All strict
acceptance figures use the unchanged exact-droop tolerance of `1e-5` pu.

## Frozen matrix and paired changes

The common smooth baseline has 24 cells: 2 solvers × IEEE 118/300 ×
nominal/+5% load × anchor/flat-low/flat-high. It uses epsilon `1e-6`, physical
coordinates, the same controllers/objective, and a one-reset policy with a
2000-iteration/120-second total budget (at most 1000/60 per attempt).

| ID | What changed | Warm-start / starting-point rule | Strict result | What it says | Evidence |
|---|---|---|---|---|---|
| B | Explicit smooth droop-Q baseline | Declared anchor, flat-low, or flat-high; one compatible multiplier-reset retry | I 8/12; M 4/12 | Reference decision; 12/24 total | `s1_policy_{ipopt,madnlp}` |
| RST | One-reset policy | Finite compatible iterate from attempt 1; zeroed solver-specific dual starts | I 7→8/12 (+1); M 4→4/12 | One Ipopt recovery; not a general solution | `s1_restart_policy` |
| N | Normalize free controls to `[0,1]` | Same declared physical starts; no cross-mode seed | I 7/12 (+2/-3); M 1/12 (+1/-4) | Mixed and worse total coverage | `s1_normalization` |
| IQ | Remove only Q bounds implied by bounded smooth droop | Same starts and budget; formulation-specific restart context | I 7/12 (+0/-1); M 3/12 (+3/-4) | Removes parallel active row but is not reliable | `s1_implied_q` |
| RQ | Eliminate attached generator-Q variable/equality | Same starts and budget; no seed across formulation | I 4/12 (+0/-4); M 8/12 (+5/-1) | Strong backend dependence; not promoted | `s1_reduced_q` |
| REL | Fixed-settings → release taps/banks → full joint solve | Only independently valid preparation state transfers; shared 2000/120 budget | I 7/12 (+1/-2); M 3/12 (+1/-2) | Staging loses more than it gains | `s1_staged` |
| LOAD | Nominal → +2.5% → +5% demand | Valid prior-load state/settings only; shared budget | I 3/6 (+1/-2); M 2/6 (+0/-1) | Does not improve stressed slice | `s1_staged` |
| EC | Six epsilons: `1e-2…1e-7` | Latest solver- and policy-valid stage; failed stage not propagated | I 8/12 (+1/-1); M 10/12 (+7/-1); 18/24 union | Promising MadNLP recovery, but six budgets/cell and no-loss fails | `s1_epsilon_sensitivity` |
| XS | Seed unresolved EC cells from one compatible EC success at epsilon `1e-6` | Same solver, bus count, and load only; source state plus physical settings | 1/6 recovered | Shared-basin recovery, not independent-start reliability | `s1_epsilon_cross_seed` |
| TOL | Re-score retained results at `1e-2` droop tolerance | No solves; solver/policy/other physical gates unchanged | I 8/12; M 5/12; C 2/12 | Only one added M case; raw mismatch retained | `s1_droop_tolerance_1e-2` |

## Per-cell strict acceptance map

`✓` is strict acceptance in that column; `–` is not accepted. EC means at
least one stage accepted, not that every epsilon did. The frozen baseline is B.

| Case/start | I-B | I-N | I-IQ | I-RQ | I-EC | M-B | M-N | M-IQ | M-RQ | M-EC |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 118 / 1.00 / anchor | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | ✓ | ✓ | ✓ |
| 118 / 1.00 / low | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | ✓ | ✓ | ✓ |
| 118 / 1.00 / high | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | ✓ | ✓ | ✓ |
| 118 / 1.05 / anchor | ✓ | – | – | – | ✓ | – | – | – | – | ✓ |
| 118 / 1.05 / low | – | – | – | – | – | ✓ | – | – | ✓ | ✓ |
| 118 / 1.05 / high | – | – | – | – | – | – | – | – | – | ✓ |
| 300 / 1.00 / anchor | ✓ | – | ✓ | ✓ | ✓ | ✓ | – | – | ✓ | ✓ |
| 300 / 1.00 / low | – | ✓ | – | – | – | – | – | – | ✓ | ✓ |
| 300 / 1.00 / high | – | ✓ | – | – | ✓ | – | – | – | ✓ | – |
| 300 / 1.05 / anchor | ✓ | ✓ | ✓ | – | – | ✓ | – | – | ✓ | – |
| 300 / 1.05 / low | ✓ | ✓ | ✓ | – | ✓ | ✓ | – | – | – | ✓ |
| 300 / 1.05 / high | ✓ | – | ✓ | – | ✓ | – | – | – | – | ✓ |

## Epsilon and accepted-state recovery detail

| Epsilon | Solver-valid | Strict-valid | `1e-2` diagnostic valid | Mean seconds |
|---:|---:|---:|---:|---:|
| `1e-2` | 15/24 | 0/24 | 0/24 | 8.271 |
| `1e-3` | 18/24 | 0/24 | 0/24 | 3.593 |
| `1e-4` | 18/24 | 1/24 | 9/24 | 2.166 |
| `1e-5` | 19/24 | 7/24 | 19/24 | 3.996 |
| `1e-6` | 10/24 | 9/24 | 10/24 | 4.140 |
| `1e-7` | 8/24 | 8/24 | 8/24 | 11.066 |

Cross-seed outcomes: M 300/1.00/high recovered; I 118/1.05/low and high
both converged but remained droop-only failures at `1.427e-5` pu; I 300/1.00
low and I 300/1.05 anchor hit iteration limits; M 300/1.05 anchor ended
`SLOW_PROGRESS` with `1.062e-5` pu mismatch.

## Other retained solution-finding and diagnostic evidence

| ID | Scope / method | Start or warm-start treatment | Result | Evidence |
|---|---|---|---|---|
| XSM | Cross-solver physical seed | Start MadNLP from each of 8 independently valid Ipopt states/settings; never transfer Ipopt duals | 5/8 valid; +4/-2 against direct M on that subset | `s1_ipopt_to_madnlp` |
| REF | Exact-droop refinement | Six converged, droop-only normalized failures; one extra `epsilon=1e-7` solve from physical state/settings | 2/6 validate; excluded from frozen count | `s1_normalization_refinement` |
| PR | Small bound-push and simple epsilon/load continuation | Prior solver-converged, policy-valid state/settings can seed next step | Mixed: clean 300/M path; frequent 118/Ipopt stalls | `s1_public_recovery` |
| FEAS | Feasibility audit | Recompute/validate witnesses rather than infer from failure | Witnesses exist for all nominal groups and stated stressed groups | `s1_feasibility_audit` |
| KKT | Physical-coordinate KKT/rank diagnostic | Re-evaluates retained direct points; no solve/formulation change | Reproduces 10 frozen outcomes; identifies saturated droop/Q-bound parallelism | `s1_kkt` |
| SCALE | Scaling/derivative probes | Diagnostic only; no acceptance relaxation | Scaling and conditioning evidence retained; no default change | `s1_scaling_probe`, `s1_convergence`, `s1_exact_hessian` |
| WS | Multi-start / seed-layout experiments | Primal values and nonlinear/bound multipliers with compatibility checks | Seed provenance and selection policy retained; not a frozen-formulation change | `s1_warmstarts`, `s1_equal_budget` |
| EXT | Synthetic and public extension/robustness probes | Fixed, flat-low, flat-high, continuation and polish variants | 35/35 synthetic attempts; public recovery remains mixed | `s1_extension` |
| CC-P | CCOpt pilot/placement/polish | Exact complementarity; varied starts, placements, tolerances, and tighter follow-ups | Pilot plus placement evidence; not smooth-matrix replacement | `s1_ccopt_{pilot,placement,polish,matrix}` |
| CC-F | CCOpt frozen lane | Same 12 public cells, native one-solve profile, exact complementarity | 2/12; 10 failures remain evidence | `s1_ccopt_frozen` |
| CC-X | CCOpt cross-seed/feasibility/load continuation | Accepted 118 seed only within 118; staged 300/load studies separately | Local witnesses where successful; failures are not infeasibility claims | `s1_ccopt_droop_feasibility`, `s1_ccopt_300_continuation` |
| NLD | NLPDiagnostics point-local and matched replay | Read-only result-point analysis; matched direct versus fixed epsilon continuation from the same flat-low start | Both endpoints are rank-deficient; continuation reaches strict validity without removing deficiency, supporting basin/path sensitivity | `s1_nlpdiagnostics_pilot`, `s1_nlpdiagnostics_matched_continuation` |
| FAM | Full smooth control-family isolation | All 8 fixed/single/pair/joint combinations; all controls in selected families; same 24 cells and one-reset budget per family | Complete 192/192; fixed 13, D 14, T 13, S 16, TS 10, TD 15, SD 15, joint 12 of 24 | `s1_smooth_control_family_matrix` |
| RAW | Untouched PGLib stress qualification | No droop overlay, synthetic bank or adjustable tap; raw nominal source state and 1% continuation | 118 raw +5% validates with both solvers; 300 validates to 1.04, both fail at 1.05 with all major limits binding at 1.04 | `s1_source_stress_audit`, `s1_raw_load_continuation` |

## Reading rules

Existing-shunt qualification (`artifacts/s1_existing_shunts`): 14 available
nonzero-B source shunts per network are represented as continuous
G(alpha)=alpha*G0, B(alpha)=alpha*B0 devices, 0<=alpha<=1, initially at 1.
Selection is an assumed benchmark capability; source records do not establish
switchability. Nominal admittance error is zero for both networks, original
anchors validate, and intermediate admittance replay passes. The eight nominal
anchor-start fixed/shunt-only solves yield 6/8 strict passes: Ipopt passes both
families on both networks, MadNLP passes both on IEEE-300 and has droop-only
validation misses on IEEE-118 (1.93e-5 and 2.06e-5 pu). This is a qualification
pilot, not a replacement full frozen matrix. Pure-conductance/unavailable
shunts remain fixed; discrete switching and AVR behavior are deferred.

Existing-shunt full-family follow-up (`artifacts/s1_existing_shunt_family_matrix`):
the continuous-envelope assumption was run for all eight fixed/single/pair/joint
families, both solvers, both networks, three starts, and nominal/1.03 loads.
The matrix is complete (192/192). Strict/diagnostic-`1e-2` totals are 99/123.
Strict family totals out of 24 are: fixed 12, D 16, T 15, S 14, TS 7, TD 12,
SD 17, and joint 6. The diagnostic counts are 13, 16, 19, 15, 17, 13, 17,
and 13 respectively. At IEEE-300/1.03, both backends find strict tap-only
witnesses (2/3 starts each), whereas fixed, droop-only, and shunt-only produce
none. Tap+shunt succeeds for MadNLP (2/3 strict, 3/3 diagnostic), and joint
succeeds for Ipopt (2/3 strict). This supports tap-led recovery and strong
family/backend/start interactions; it does not certify infeasibility of failed
families.
Within-cell multiplier-reset warm starts were used in 85/192 cells and recovered
24; 61 remained unresolved. No accepted result was propagated between cells or
declared starts. The near-limit matrix used 36 within-cell resets, recovering 12.

The separate `artifacts/s1_existing_shunt_near_limit` matrix is complete
(96/96) at 1.05 and remains an unqualified challenge, not part of the main
totals. It yields 45 strict and 56 diagnostic passes. On IEEE-300, fixed,
droop-only, shunt-only, and shunt+droop have no strict witnesses, while tap-only
has 4/6 across backends, tap+droop 4/6, tap+shunt 3/6, and joint 1/6. Thus taps
are present in every successful IEEE-300/1.05 family, but richer families are
not monotonically easier for the solvers.

1. A lower objective, low smooth residual, or `LOCALLY_SOLVED` status alone is
   never an accepted result; solver, policy, AC physical, and exact-droop gates
   all apply.
2. Warm starts transfer only the declared compatible primal state/settings.
   Dual transfers are solver/formulation-specific and explicitly recorded.
3. Gains are informative only when their paired experiment also preserves every
   baseline success under a comparable total budget. No listed change meets
   that S1 promotion rule yet.
4. Every detailed attempt, status, residual, seed lineage, and physical failure
   remains in the named artifact directory; this ledger is the navigation map,
   not a lossy replacement for those records.
