# S1 current decision report

**S1 is closed for the declared 14- and 500-bus sampled-demand study (2026-10-15).** The accepted scope uses Pmin=0, symmetric reactive limits, zero deadband, continuous equipment controls, and OPF-derived initializations. Direct failures and bounded recoveries remain visible. See the [S1 closeout](s1_closeout.md), [500-bus qualification](s1_500_results.md), and [free-droop comparison](s1_free_droop_results.md). Original-limit compatibility and broader operating envelopes remain explicitly qualified limitations.

## Final 14-bus decision

The selected reference is the 100%-demand joint loss-minimizing OPF with all three online transformer ratios within ±5% of source settings and available shunt bank 3 continuously adjustable. Calibrate five shifted-zero-Q curves with uniform 8% full-Q-span droop and no deadband, then freeze the curves, taps and shunt at that reference. Keep study Pmin=0 and symmetric Q bounds; original data remain separate.

The frozen design has verified points at **all five sampled demands (90/95/100/105/110%)** and **42/45 accepted solver attempts** over three OPF-anchor starts and three solvers. Ipopt and MadNLP each accept 15/15; CCOpt accepts 12/15, with three retained iteration limits at 90%. The separate free-equipment comparator accepts 45/45. No flat starts contribute to either score.

Wider ±10%-of-source or 0.9–1.1 references improve losses with equipment free but lose frozen-design witnesses at 90/95% and worsen frozen 110% losses. They are retained sensitivity results, not the selected closeout design. The final design has not been requalified under original generator limits; prior original-limit tests concern earlier designs. Thermal and voltage limits can remain binding.

## Completed evidence

Counts below describe each stage's own scope; reused cells are identified in the linked reports and must not be summed as unique solves.

| Stage | Evidence / outcome | Report |
|---|---|---|
| Source import and limits | Original OPF/SCOPF preserved; Pmin-zero/symmetric-Q study variants retained separately | [Historical experiment record](assets/s1_anchor_only/s1_history.md) |
| Droop and initialization diagnosis | Source/cost/loss anchors; corrected curves; no-deadband/deadband; feasibility and global escalation diagnostics | [Historical experiment record](assets/s1_anchor_only/s1_history.md) |
| Joint sensitivity | 1,080 cells; 702 physical witnesses / 688 accepted | [Sensitivity](assets/s1_anchor_only/joint_sensitivity_report.md) |
| Matched smoothing | 720 new + 360 reused cells; 701 physical / 689 accepted | [Matched comparison](assets/s1_anchor_only/matched_sensitivity_report.md) |
| 95/105% confirmation | 72/72 accepted | [Confirmation](assets/s1_anchor_only/confirmation_report.md) |
| Equipment-only families | 90 new + 30 reused; 120/120 accepted under dispatch deviation | [Equipment](assets/s1_anchor_only/equipment_report.md) |
| Slope design and frozen tests | 105/120 accepted design; 105/120 accepted frozen | [Droop design](assets/s1_anchor_only/droop_design_report.md) |
| Fixed-controller objective comparison | Dispatch 30/30, loss 26/30, cost 23/30 | [Objectives](assets/s1_anchor_only/objective_comparison_report.md) |
| Performance control families | 447/480 design cells including reused baseline; 347/420 frozen accepted | [Performance](assets/s1_anchor_only/performance_controls_report.md) |
| Original limits on earlier candidates | 30 source OPFs + 450 solves; 75/75 model/demand contracts feasible, 410/450 accepted | [Original limits](assets/s1_anchor_only/original_limits_report.md) |
| Joint loss references and tap bounds | 258 primary + 90 new-anchor solves; all 348 saved states replayed without discrepancies | [Final closeout](s1_14bus_closeout.md) |
| Selected frozen design | Serialized-case replay of 45 attempts; 42 accepted; five demand witnesses packaged | [Final closeout](s1_14bus_closeout.md) |

## Objectives and acceptance

A **reference-loss** OPF constructs a calibration point by minimizing total active losses, sum(Pg)−sum(Pd). A **reference-cost** OPF minimizes the source generator cost model. Either OPF can also supply an initialization without changing the calibrated controller. The downstream S1 objective is a separate choice: loss, generation cost, or historical squared dispatch deviation. The final design uses joint loss calibration and loss-objective evaluation.

A physically feasible point passes independent AC balance, voltage, generator P/Q, thermal, angle, equipment-policy and exact-droop checks. Solver acceptance additionally requires successful termination. The gate remains **feasible / certified infeasible / unresolved**; local infeasibility or iteration limits do not prove global infeasibility. Qualification is for sampled steady-state demand points, not continuous-range robustness, dynamic stability or N-1 security.

## Historical studies

<!-- S1_ZERO_DEADBAND_FOLLOWUP -->
## Zero-deadband numerical follow-up

The specialized constant-zero-deadband formulation removes the redundant voltage
hinges while retaining Q saturation. A separate S1 replay accepted **11/12 primary
attempts** (all six original light-load starts and five of six closeout-profile
failures); **12/12 combinations** passed after one historical-policy bounded
retry. The remaining primary failure is retained as `SLOW_PROGRESS` with an AC
power-balance violation. These follow-up counts do not replace the historical
campaign or profile scores above. The formulation passed **3,042/3,042 regression
checks**. See the [diagnosis, recovery and limitations](s1_zero_deadband.md).
<!-- /S1_ZERO_DEADBAND_FOLLOWUP -->

<!-- S1_CONTROL_FIGURES -->
## S1 14-bus free-control solution figures

The focused visual follow-up uses 15 saved, matched joint-anchor designs:
90/95/100/105/110% demand and Ipopt/MadNLP/CCOpt, with slopes, references,
all three taps and bank 3 free. All 15 points pass independent replay with zero
discrepancies; no new optimization was run. CCOpt freely designed the curves
in S1, unlike the fixed-curve S2 verification. Demand points are independent
redesigns, not a single frozen-controller qualification. Historical scores and
the closed S1 numerical scope are unchanged.

[All 12 operating/control comparison figures](s1_14bus_control_figures.md).
<!-- /S1_CONTROL_FIGURES -->
