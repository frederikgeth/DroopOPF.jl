# Changelog

All notable changes to DroopOPF.jl are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and releases use [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- CCOpt parity for base-case continuous joint design: exact complementarity
  droop with the same tap-ratio, simple-bank, and bounded droop-parameter
  variables used by the Ipopt/MadNLP formulation, including independent replay,
  complementarity residuals, serialization, and a matched solver benchmark.
- Exact CCOpt encoding in the dedicated continuous tap and simple-bank design
  APIs, with the same physical replay and solver-residual metadata.
- An explicitly separate S1 CCOpt pilot with cumulative inner-iteration budgets,
  relaxation diagnostics, two-start synthetic and IEEE 118 evidence, and
  retained standard-accuracy exact-droop failures plus tighter follow-ups.
- A machine-checked IEEE 118/300 feasibility audit separating validated model
  witnesses from solver failures and clarifying that the +5% cases are fixed
  robustness stresses rather than loadability-boundary calculations.
- A resumable, per-attempt checkpointed CCOpt S1 control-family matrix and
  matched 12-cell frozen lane, including direct exact-droop audits, cross-seed,
  conditional droop-only feasibility, and IEEE-300 continuation evidence.

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

[Unreleased]: https://github.com/frederikgeth/DroopOPF.jl/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/frederikgeth/DroopOPF.jl/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/frederikgeth/DroopOPF.jl/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/frederikgeth/DroopOPF.jl/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/frederikgeth/DroopOPF.jl/releases/tag/v0.1.0
