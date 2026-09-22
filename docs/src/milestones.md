# Milestones and S1 status

## Released implementation milestones

| Milestone | Status | Where to start |
|---|---|---|
| M1–M4 | Released | [Getting started](getting_started.md), [robustness](robustness.md), and [scale-up decision](scale_up_decision.md) |
| M5 — transformer physics | Implemented and validated | [data model](data_model.md#fixed-transformer-electrical-model-m52m54) |
| M6 — fixed shunts and simple banks | Implemented and validated | [data model](data_model.md#fixed-bus-shunts-m61) |
| M7 — continuous tap, bank, and joint droop design | Implemented and validated for the declared continuous base-case scope | [equipment optimization](equipment_optimization.md) |

M7 permits continuous tap ratios and simple-bank susceptances. Discrete tap
positions and switched-shunt selection remain intentionally out of scope.

## S1 — current reliability investigation

S1 is **active, not released as reliable**. It evaluates the M7 joint model on
the frozen public IEEE 118/300 matrix with solver/start/load stresses. The
underlying formulation, acceptance criteria, data provenance, and retained
failures are documented rather than hidden.

| Evidence | Current conclusion | Entry point |
|---|---|---|
| Ipopt and MadNLP | Frozen policy and restart evidence exists; reliability gate remains open | [bounded restart policy](s1_restart_policy.md) |
| CCOpt | Exact-PWL frozen lane completed; 2/12 direct cells accepted | [CCOpt frozen lane](s1_ccopt.md#frozen-s1-lane) |
| Case feasibility | IEEE 118 nominal/+5% and IEEE 300 nominal have validated local witnesses; IEEE 300 +5% remains unknown | [feasibility status](../../artifacts/s1_ccopt_frozen/FEASIBILITY_STATUS.md) |

IEEE 118/300 are explicit reliability workloads, not unit tests. Their retained
commands and artifacts live under `artifacts/s1_ccopt_*`.

## Finding the evidence

- Formulation and validation contract: [S1 joint formulation](joint_formulation.md).
- Smooth-solver convergence history: [S1 convergence evidence](s1_evidence.md).
- Exact CCOpt, physical residuals, and reproduction commands:
  [S1 CCOpt pilot and frozen lane](s1_ccopt.md).
- Overall roadmap and outstanding gates: [ROADMAP.md](../../ROADMAP.md).
