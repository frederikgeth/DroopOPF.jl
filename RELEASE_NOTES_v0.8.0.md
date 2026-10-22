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

Validation: the package test suite passed 2267/2267 tests after the M8 API and
joint-design changes, and the v0.8.0 documentation build passed.
