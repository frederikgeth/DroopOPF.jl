# DroopOPF.jl v0.9.0 — M9 equipment-aware SCOPF

v0.9.0 releases coordinated continuous-equipment decisions in security-
constrained AC OPF. A `Study` can select transformer tap and simple-bank
controls, assign preventive or corrective timing, and retain shared automatic
reactive-control semantics across the base case and contingencies.

M9.1 shares preventive settings by default and permits explicitly declared
corrective settings. M9.2 adds per-device movement budgets relative to the saved
base setting; selected corrective devices omitted from an action map are frozen.
M9.3 compares an immediate equipment-frozen equilibrium with a later bounded-
recourse equilibrium. Both are steady-state assessments and make no transient,
switching-time, or action-count claim.

Every reported scenario is independently reconstructed from its saved tap and
shunt settings. Validation separately checks AC balance, operating limits,
reactive-control equilibrium, equipment availability, preventive coupling, and
corrective movement. Study/result schemas preserve older fixed-equipment data,
and paired assessments support JSON and Markdown reporting.

The bounded S2 public qualification is retained under `artifacts/s2_scopf`.
Its IEEE-118 expansion accepts 25/29 direct cells and 26/29 with a declared
bounded same-model warm retry across tap, shunt, joint,
multi-location, preventive, corrective, AVR, mixed-control, holdout, and +3%
load-stress cases. The frozen IEEE-118/300 scorecard reports direct, staged,
immediate, and settled results separately. IEEE-300 staged M9.1 remains open;
timeouts, slow progress, and physical-only results are retained and are not
infeasibility certificates.

The M9 release gate requires independent validation and synthetic regression
coverage for all three slices, accepted public witnesses at IEEE-118 and
IEEE-300 scale, retained bounded solver evidence, a passing package suite,
documentation, and a runnable example. It does not claim universal convergence,
full N-1 coverage, global optimality, discrete implementability, or transient
security. Broader reliability work continues in S2/M10, while S1 remains a
separate frozen base-case investigation.

Validation: the package test suite passed 2319/2319 tests, the documentation
build passed, and `examples/m9_1_equipment_scopf.jl` completed with independently
valid preventive and corrective workflows.
