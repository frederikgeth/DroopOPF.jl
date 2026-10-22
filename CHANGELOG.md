# Changelog

## Unreleased — limit-aware automatic active response

- Replace fixed proportional preventive response with exact bounded weighted
  requests, allowing unsaturated participants to supply the remainder.
- Default to nonzero effective active-capability-range weights; preserve explicit
  weights and enforce attached droop capability and response movement limits.
- Update independent replay, response predictor and campaign policy fingerprints.
- Study v10/result v5 explicitly tag the response model; historical coupled
  preventive files cannot silently acquire the replacement semantics.
- Preserve historical P2 evidence; new-policy qualification remains pending.


All notable changes to DroopOPF.jl are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and releases use [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Expanded 105% zero-shedding connected-outage qualification with Ipopt, equivalent direct-relief equations, implied-Q-bound cleanup, and incremental shared-demand recovery with independent original-network validation.

- Capped 500-bus continuation through 106.25%, a validated common-controller five-demand feasibility witness, and independent Ipopt/MadNLP/CCOpt joint optimization attempts with bounded recoveries and original-network/reduction replay. The preceding 105% connected-security controller remains retained.

- Targeted 500-bus CCOpt stage diagnostics and independent emergency-policy design qualification at 105%, with exact network reduction, original-network outage replay, joint necessary-condition audits and parameter/operating figures. The 110% emergency target and CCOpt remain unresolved; original normal-limit results retain their separate scope.

- 500-bus solver and independent-demand qualification with 51 free slopes and
  references shared across outages. Ipopt recovers 100% connected-outage
  qualification; Ipopt and MadNLP each qualify independent 90% and 95% designs.
  Added demand-matched S1 initialization, reserve-start QPs, contingency
  addition, guarded near-point recovery, full-network replay and all-generator
  curve/control plots. CCOpt and original normal-limit 105% remain unqualified after bounded retries;
  the original 110% certificate and overall S2 open status are retained.

- Free-droop 500-bus continuation study with exact active response, independent
  original-network checks, equivalent droop-only scaling, accepted-anchor
  recovery and staged resource polishing. Reports include all 51 droop curves,
  equipment/operating values and a separately audited DR-first allocation
  witness. Native feasibility and minimum-resource claims remain distinct.

- 500-bus expanded-master demand continuation with independently audited
  exact-policy points and bounded active-response diagnostic/restoration runs.
  Relaxed response is never accepted as an original-model recovery; corrective
  tap/shunt bounds, original branch ratings and full-network checks are retained.
  Reports distinguish local failures, policy diagnostics and qualified coverage.

- Exact zero-injection network-reduction study adapters for the 500-bus S2
  investigation, including full and partial reductions, original branch terminal
  ratings and voltage/angle constraints, per-outage reconstruction, independent
  full-network acceptance checks, matched compact comparisons and audit guards.
  Original physical infeasibility and islanding classifications are unchanged.

- 500-bus bottleneck and demand-boundary investigation under confirmed emergency
  voltage/110% Rate A caps, 1% DR and 10 MW contingency shedding. Added
  feasibility-first hard models, demand continuation, exact necessary-condition
  upper samples, shared-controller sampled feasibility, connected-outage
  checkpoints, bounded dispatch recovery, island-budget proofs and reporting.
  Local failures remain distinct from certificates; full 500-bus S2 stays open.
  No physical remedies or release publication are included.

- Confirmed-control 500-bus S2 pilot, bounded CCOpt recovery records,
  independent topology/AC/droop/equipment/reserve audits and documentation
  figures. Ipopt and MadNLP passed the three-outage pilot; reserve-aware MadNLP
  recovery then qualified all 389 connected outages at nominal demand,
  with 390 independently replayed unique states. The required 110%/G60 case
  has a verified rational active-loss infeasibility certificate, including
  acceptance-tolerance robustness; the five-demand target cannot pass under
  the original normal-limit, full-demand policy.
  Held-out checks were deferred and CCOpt remains unqualified. The 171 loaded islands without generation
  preclude an all-loads-served full N-1 claim.

- Frozen nominal-controller 14-bus S2 demand qualification: 9/15 combinations
  pass at 100/105/110%; 90/95% remain unqualified after bounded retries.
  Conditional line 7–8/G5-trip retained-network validation and 546 independent
  state/projection checks preserve the original nominal scorecard.

- Embedded all 18 S2 operating/controller figures in documentation, plus 12
  S1 14-bus all-free-control solver-comparison figures using 15 independently
  replayed saved designs; S1 numerical scope and historical scores unchanged.

- S1 closed for the declared 14/500-bus sampled base-case scope; original-limit
  and security limitations remain separate. Pending release notes are in
  `RELEASE_NOTES_UNRELEASED.md`.
- Qualified the user-confirmed native 14-bus S2 nominal-demand study for all
  24 connected eligible outages: 9/9 solver runs and 157 independent state
  replays passed. One islanding outage remains excluded; no full N-1 claim.

- Exact constant-zero-deadband droop specialization removes redundant voltage
  hinges while retaining reactive saturation, with smooth derivative-equivalence
  checks and S1 diagnosis/replay reports: 11/12 primary passes and 12/12 after
  one historical-policy bounded retry; full regression 3,042/3,042.

- Complementary S1 free-droop studies for the selected 14- and 500-bus cases,
  with independent slope/reference bounds, per-demand design and frozen-candidate
  checks, retained failures, same-model solver recovery, and independent replay.

- S1 14-bus closeout with a hashed frozen joint loss-reference case, five demand
  witnesses, retained solver failures, serialized-case replay and generated reports.
  Added the staged 500-bus qualification plan; broader S1 scaling remains open.

- Default selected tap and shunt timing to corrective, allowing independent
  scenario settings within declared equipment bounds; preventive sharing is
  now explicit, while legacy schema migrations preserve their prior policy.
- Multi-controller smooth droop design through the SCOPF builder, preserving
  preventive/corrective equipment and active-response policies.
- Bounded contingency-addition driver with deterministic selection, complete
  iteration evidence, exact final AC audits, and separate eligible/full-N-1 flags.
- Small full-enumeration reference, actual-droop discovery/held-out filtering
  qualification, bounded public-network runners, and reproducible reports/plots.
- Opt-in sparse balance expressions for controlled smooth OPF/SCOPF, included
  in resumable campaign fingerprints; legacy controlled-case defaults remain.

### Fixed

- Preserve Study equipment and response policies when replacing droop settings,
  sweeping slopes, and evaluating held-out contingencies.
- Reconstruct island generator initial values within strict domains when an
  independently validated base has only tolerance-sized bound overshoots.

### Qualification

- The frozen filter missed five discovery and seven held-out outages under
  actual droop response. Screening remains a heuristic; exhaustive final audits
  are mandatory in the new design driver. Public solver failures are retained
  separately from small-network feature acceptance.

## [0.9.0] - 2026-09-29

### Added

### Fixed

- Preserve nonfinite SCOPF tap and shunt settings across JSON evidence
  round-trips as `NaN`/`null`, allowing failed-stage reports to be reloaded and
  independently assessed instead of crashing on `Float64(nothing)`.

## [0.8.0] - 2026-09-28

### Added

## [0.4.0] - 2026-09-18

### Added

- Exact reference-versus-optimized droop visualization with explicit training,
  held-out, and unavailable-control scenario annotations.
- M2/M3 solver-compatibility regressions for warm-started MadNLP and CCOpt
  fixed-curve validation, with explicit rejection of CCOpt as an M3 optimizer.
- Named SCOPF multi-start experiments that retain every run and classify valid
  objective agreement without silently selecting an invalid solution.
- Machine-readable droop-breakpoint distances and structured findings for
  solver/validation failure, binding limits, and the minimum-margin contingency.
- M3 parameter multi-start comparison with retained initial settings, exact-curve
  validation, objective agreement, and component-wise optimized-setting spread.
- Pinned PGLib-OPF v23.07 case 3 and case 5 regressions with CC BY 4.0
  provenance, serialization, and independent validation.
- Reproducible SCOPF measurement reports covering environment, actual JuMP
  model size, elapsed time, allocations, objective, termination, and validity.
- Process peak RSS in bytes, with fresh-process benchmark runs and explicit
  lifetime scope including compilation, warm-up, and validation.

## [0.3.0] - 2026-09-18

### Added

- Reference-anchored M3 fixed-slope sweeps through the validated M2 SCOPF.
- Per-candidate objective, voltage-deviation, branch-loading, exact-droop, and
  solver-status diagnostics with versioned JSON round trips.
- A self-contained SVG trade-off plot and reproducible M3 example workflow.
- Bounded in-model optimization of slope, voltage reference, and asymmetric
  deadband widths shared across base and training-contingency equations.
- Exact-curve reconstruction and independent training/held-out validation for
  optimized designs, including versioned design JSON and visual artifacts.

## [0.2.0] - 2026-09-18

### Added

- M2 full-enumeration SCOPF with line and generator outage overlays.
- Explicit preventive participation and bounded corrective redispatch policies.
- Smooth Ipopt/MadNLP and exact CCOpt scenario formulations using the existing AC builders.
- Independent per-scenario physics, exact/encoded droop, availability, and response checks.
- Fixed-base contingency evaluation, scenario warm starts, and epsilon continuation.
- Versioned JSON study/result save/load, JSON/Markdown reports, and an M2 workflow example.
- M2 SVG validation plots for droop points, bus voltages, branch loading,
  generator dispatch, and residual-to-tolerance ratios.
- Regressions for binding security constraints, infeasible response policies, and corrupted results.

### Fixed

- Initialize both branch-flow ends to zero for unavailable branches.

## [0.1.0] - 2026-09-04

First public M1 milestone release.

### Added

- Typed AC network, generator, load, and generator-control data model.
- Piecewise-linear volt-var droop curves with deadband and reactive limits.
- Smooth AC OPF formulation for Ipopt and MadNLP.
- Stable softplus evaluation through `LogExpFunctions.log1pexp`.
- Generator-specific reactive smoothing scaling with absolute-width override.
- Exact complementarity droop formulation through CCOpt and
  MathOptComplements.
- Independent AC equilibrium and exact droop-curve validation.
- Droop operating-point extraction and self-contained SVG plotting.
- Three-solver comparison example covering deadband, proportional, and
  saturation regimes.
- MATPOWER case loading and droop-control attachment helpers.
- Architecture, roadmap, solver-compatibility, and test-case study documents.
- Unit and integration smoke tests for Ipopt, MadNLP, and CCOpt.

### Notes

- M1 supports one static volt-var control attachment per generator.
- AC OPF remains a nonconvex local optimization problem; solver agreement is
  assessed using physical residuals, objective values, and droop regimes.
- Security constraints and droop-curve optimization are planned for M2 and M3.

[Unreleased]: https://github.com/frederikgeth/DroopOPF.jl/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/frederikgeth/DroopOPF.jl/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/frederikgeth/DroopOPF.jl/compare/v0.7.0...v0.8.0
[0.4.0]: https://github.com/frederikgeth/DroopOPF.jl/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/frederikgeth/DroopOPF.jl/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/frederikgeth/DroopOPF.jl/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/frederikgeth/DroopOPF.jl/releases/tag/v0.1.0

<!-- S2_MULTIDEMAND -->
## S2 14-bus shared multi-demand follow-up

**1 accepted shared design; 27/27 frozen solver–demand combinations accepted.** Shared slopes/references are trained on five demands and all 24 connected outages; the selected accepted controller is frozen at five training and four held-out demands for Ipopt, MadNLP and CCOpt. Independent replay: 1050 connected-state records and 42 conditional G5-trip projections, zero discrepancies. Corrective tap/continuous-bank bounds remain unchanged. This sampled steady-state result makes no continuous-envelope or general islanding claim. S1 remains closed; no release has been published.
<!-- /S2_MULTIDEMAND -->

<!-- S2_SOLVER_DESIGNS -->
## Independent MadNLP and CCOpt shared-design follow-up

Accepted free multi-demand designs: **ipopt, madnlp**. The new backends optimize their own shared slopes/references from the accepted Ipopt full witness; accepted designs are independently replayed and compared with Ipopt. See the [solver design comparison](docs/src/s2_14bus_solver_designs.md). Original campaign scores, rejected attempts and S1 closure remain unchanged.
<!-- /S2_SOLVER_DESIGNS -->





<!-- S2_CCOPT_RECOVERY -->
## Targeted CCOpt convergence recovery

**CCOpt recovered an accepted free multi-demand design.** The recovery starts from the accepted MadNLP full primal witness and tests proportional/scheduled relaxation without changing the physical contract. See the [CCOpt recovery report](docs/src/s2_14bus_ccopt_recovery.md) for diagnostics, updated curves and held-out outcomes. Historical attempts and S1 closure remain unchanged.
<!-- /S2_CCOPT_RECOVERY -->

<!-- S2_14BUS_REVIEW -->
## 14-bus S2 review decision

The declared sampled 14-bus scope is closed. See the [14-bus review](docs/src/s2_14bus_review.md). Broader S2 remains open; S1 remains closed.
<!-- /S2_14BUS_REVIEW -->

<!-- S2_CURRENT_ACCEPTED -->
## Consolidated S2 14-bus accepted results

The [main S2 14-bus report](docs/src/s2_14bus.md) and [complete gallery](docs/src/s2_14bus_figures.md) now lead with accepted free Ipopt, MadNLP and recovered CCOpt multi-demand designs. Fourteen current figures cover 675 connected-state records and 27 conditional projections; all pass independent replay. The original 18 nominal-campaign figures and failed attempts remain historical. No numerical optimisation was run for consolidation; S1 and the declared sampled 14-bus scope remain closed, while broader S2 remains open.
<!-- /S2_CURRENT_ACCEPTED -->
