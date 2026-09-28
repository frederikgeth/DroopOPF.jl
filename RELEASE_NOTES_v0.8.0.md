# DroopOPF.jl v0.8.0 — M8 reactive controls and AVR

v0.8.0 releases the M8 base-case reactive-control capability. Generators can
now be assigned `FreeQ`, `FixedQ`, AVR, or Volt–VAr operation with an explicit
regulated location. AVR supports generator-terminal, remote-bus, and identified
branch-terminal monitoring locations, Q-limit PV-to-PQ behavior, common-location
Q-range sharing, smooth Ipopt/MadNLP formulations, and exact CCOpt comparison.

Reactive assignments are persisted with legacy-compatible readers and may be
used in AVR-aware continuous tap, simple-bank, and joint-design workflows.
Every result is checked with independent physical validation rather than solver
status alone.

Qualification is retained under `artifacts/avr_ieee_qualification`. Staged
k1 → k2 → k3 continuation validates all 24 Ipopt/MadNLP joint stages across
IEEE-118 and IEEE-300 at loads 1.00 and 1.01. The exact CCOpt lane records
11/12 directly physically valid stages; its one direct IEEE-300 stressed-k3
failure is recovered by a smooth-witness cross-seed to a valid
`ALMOST_LOCALLY_SOLVED` exact point with maximum complementarity residual
`2.484e-8`. This is reported as basin-sensitive solver behavior, not a claim
of general exact-solver reliability.

S1's frozen synthetic-droop reliability gate remains open and is not rescored
by these separate AVR artifacts. M9—coordinated preventive/corrective SCOPF
equipment and reactive-control policy—is not included in this release.

Validation: the package test suite passed 2267/2267 tests after the M8 API and
joint-design changes, and the v0.8.0 documentation build passed. The release
qualification commands are documented in `examples/avr_ieee_qualification.jl`
and its artifact README.
