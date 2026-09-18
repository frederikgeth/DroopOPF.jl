# Changelog

All notable changes to DroopOPF.jl are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and releases use [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Exact reference-versus-optimized droop visualization with explicit training,
  held-out, and unavailable-control scenario annotations.

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

[Unreleased]: https://github.com/frederikgeth/DroopOPF.jl/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/frederikgeth/DroopOPF.jl/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/frederikgeth/DroopOPF.jl/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/frederikgeth/DroopOPF.jl/releases/tag/v0.1.0
