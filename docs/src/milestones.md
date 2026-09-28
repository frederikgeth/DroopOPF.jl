# Milestones and S1 status

## Released implementation milestones

| Milestone | Status | Where to start |
|---|---|---|
| M1–M4 | Released | [Getting started](getting_started.md), [robustness](robustness.md), and [scale-up decision](scale_up_decision.md) |
| M5 — transformer physics | Implemented and validated | [data model](data_model.md#fixed-transformer-electrical-model-m52m54) |
| M6 — fixed shunts and simple banks | Implemented and validated | [data model](data_model.md#fixed-bus-shunts-m61) |
| M7 — continuous tap, bank, and joint droop design | Implemented and validated for the declared continuous base-case scope | [equipment optimization](equipment_optimization.md) |
| M8 — explicit reactive controls and AVR | Released for the declared base-case scope | [data model](data_model.md#explicit-reactive-control-modes) and [AVR qualification](https://github.com/frederikgeth/DroopOPF.jl/blob/main/artifacts/avr_ieee_qualification/README.md) |

M7 permits continuous tap ratios and simple-bank susceptances. Discrete tap
positions and switched-shunt selection remain intentionally out of scope.
M8 adds explicit base-case reactive-control semantics and AVR-aware joint
equipment design; coordinated preventive/corrective SCOPF policy remains M9.

## S1 — current reliability investigation

S1 is **active, not released as reliable**. It evaluates the M7 joint model on
the frozen public IEEE 118/300 matrix with solver/start/load stresses. The
underlying formulation, acceptance criteria, data provenance, and retained
failures are documented rather than hidden.

| Evidence | Current conclusion | Entry point |
|---|---|---|
| Frozen smooth direct starts | Ipopt 8/12 and MadNLP 4/12 pass the unchanged strict contract | [current S1 report](s1_summary.md#frozen-direct-start-scorecard) |
| Frozen exact direct starts | CCOpt 2/12 passes; rejected cells also fail status or AC balance, not only droop tolerance | [current S1 report](s1_summary.md#frozen-direct-start-scorecard) |
| Same-case witness diagnostics | 7/12 unresolved cells recover strictly; failures separate basin, residual-gate, and termination behavior | [current S1 report](s1_summary.md#same-case-witness-diagnostic) |
| Physically qualified AVR lane | Ipopt/MadNLP validate 24/24 staged cells; direct CCOpt validates 11/12 physically and the remaining point is cross-seed recoverable | [current S1 report](s1_summary.md#qualified-avr-lane) |

IEEE 118/300 are explicit reliability workloads, not unit tests. Their retained
commands and artifacts live under `artifacts/s1_ccopt_*`.

## Finding the evidence

- Formulation and validation contract: [S1 joint formulation](joint_formulation.md).
- Authoritative synthesis and gate decision: [current S1 report](s1_summary.md).
- Smooth-solver convergence history: [S1 convergence evidence](s1_evidence.md).
- Exact CCOpt, physical residuals, and reproduction commands:
  [S1 CCOpt pilot and frozen lane](s1_ccopt.md).
- Overall roadmap and outstanding gates: [ROADMAP.md](https://github.com/frederikgeth/DroopOPF.jl/blob/main/ROADMAP.md).
