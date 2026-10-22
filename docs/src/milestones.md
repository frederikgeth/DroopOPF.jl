# Milestones and S1 status

## Released implementation milestones

| Milestone | Status | Where to start |
|---|---|---|
| M1–M4 | Released | [Getting started](getting_started.md), [robustness](robustness.md), and [scale-up decision](scale_up_decision.md) |
| M5 — transformer physics | Implemented and validated | [data model](data_model.md#fixed-transformer-electrical-model-m52m54) |
| M6 — fixed shunts and simple banks | Implemented and validated | [data model](data_model.md#fixed-bus-shunts-m61) |
| M7 — continuous tap, bank, and joint droop design | Implemented and validated for the declared continuous base-case scope | [equipment optimization](equipment_optimization.md) |
| M8 — explicit reactive controls and AVR | Released for the declared base-case scope | [data model](data_model.md#explicit-reactive-control-modes) |
| M9.1 — explicit SCOPF equipment timing | Released in v0.9.0; synthetic qualification complete | [SCOPF policy](scopf.md#equipment-and-reactive-control-timing-m91) |
| M9.2 — corrective-action movement budgets | Implemented and synthetically validated | Per-device allowed-action maps and independent delta checks |
| M9.3 — paired immediate/settled assessment | Implemented and synthetically validated | Fixed-base equipment replay and paired margin reporting |
| M10 — general N-1 catalog, evaluation, ranking, and screening evidence | Implemented and synthetically unit-tested; IEEE reliability baselines retained separately | [M10 contingency assessment](scopf.md#m10-contingency-catalog-and-baseline-assessment) |
| S2 — equipment-aware SCOPF public qualification | Native 14-bus nominal-demand study qualified all 24 connected eligible outages; one islanding outage excluded | [S2 qualification and coverage gap](s2_14bus.md) |

M7 permits continuous tap ratios and simple-bank susceptances. Discrete tap
positions and switched-shunt selection remain intentionally out of scope.
M8 adds explicit reactive-control semantics and AVR-aware joint equipment
design. M9.1 now applies those semantics across SCOPF scenarios, with taps and
shunts corrective by default and preventive sharing explicitly selectable.
Independent replay reconstructs each scenario's reported equipment. Public-case
qualification, discrete actions, and response-time evidence remain outside this
completed synthetic slice.
These and other deferred capabilities are maintained in the single
[future-work register](future_work.md), rather than repeated as milestone-local
task lists.

## M10 evidence closeout

The contingency-assessment implementation is present, with synthetic and finite small-network qualification. The original M10 comparative-evidence gate is complete for its declared scope: [M10.1 sourced equipment physics](m10_1_reference.md) is complete for its declared equation-reference scope; [M10.2 matched comparisons](m10_2_matched.md) are complete for the declared synthetic base-case scope, retaining a certified negative fixed-Q comparator and the failed all-feasible gate. [M10.3 reproducibility and performance closeout](m10_3_closeout.md) passed the current 3,042-assertion full regression and retained scoped replay/timing evidence. See the [implementation and validation audit](m10_audit.md) for functionality meanings, evidence and remaining qualification limits. S2 is a separate qualification scope.

## S1 — current qualification status

**S1 is closed for the declared 14- and 500-bus sampled-demand study (2026-10-15).** The accepted scope uses Pmin=0, symmetric reactive limits, zero deadband, continuous equipment controls, and OPF-derived initializations. Direct failures and bounded recoveries remain visible. See the [S1 closeout](s1_closeout.md), [500-bus qualification](s1_500_results.md), and [free-droop comparison](s1_free_droop_results.md). Original-limit compatibility and broader operating envelopes remain explicitly qualified limitations.

## Finding the evidence

The completed S1 visual follow-up adds [14-bus free-control figures](s1_14bus_control_figures.md)
for 15 independently replayed saved designs, without changing historical scores
or reopening the numerical scope. S2 has a [complete figure gallery](s2_14bus_figures.md).

The [S2 frozen-demand follow-up](s2_14bus_followup.md) qualifies the selected
nominal curves at 100/105/110% demand under the declared conditional G5-trip
response for line 7–8; 90/95% remain unqualified after bounded retries.
The original nominal scorecard and exclusions remain historical records.

<!-- S2_MULTIDEMAND -->
## Shared multi-demand design follow-up

**1 accepted shared design; 27/27 frozen solver–demand combinations accepted.** The new campaign shares one controller across five demand training points and 24 connected outages, with four additional held-out demands and corrective equipment within the confirmed bounds. See the [multi-demand report](s2_14bus_multidemand.md). Historical scores and S1 closure are unchanged.
<!-- /S2_MULTIDEMAND -->

<!-- S2_SOLVER_DESIGNS -->
## Independent MadNLP and CCOpt shared-design follow-up

Accepted free multi-demand designs: **ipopt, madnlp**. The new backends optimize their own shared slopes/references from the accepted Ipopt full witness; accepted designs are independently replayed and compared with Ipopt. See the [solver design comparison](s2_14bus_solver_designs.md). Original campaign scores, rejected attempts and S1 closure remain unchanged.
<!-- /S2_SOLVER_DESIGNS -->





<!-- S2_CCOPT_RECOVERY -->
## Targeted CCOpt convergence recovery

**CCOpt recovered an accepted free multi-demand design.** The recovery starts from the accepted MadNLP full primal witness and tests proportional/scheduled relaxation without changing the physical contract. See the [CCOpt recovery report](s2_14bus_ccopt_recovery.md) for diagnostics, updated curves and held-out outcomes. Historical attempts and S1 closure remain unchanged.
<!-- /S2_CCOPT_RECOVERY -->

<!-- S2_14BUS_REVIEW -->
## 14-bus S2 review decision

The declared sampled 14-bus scope is closed. See the [14-bus review](s2_14bus_review.md). Broader S2 remains open; S1 remains closed.
<!-- /S2_14BUS_REVIEW -->
