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

Validation: the package test suite passed 2319/2319 tests, the documentation
build passed, and `examples/m9_1_equipment_scopf.jl` completed with independently
valid preventive and corrective workflows.
