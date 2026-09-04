# Changelog

All notable changes to DroopOPF.jl are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and releases use [Semantic Versioning](https://semver.org/).

## [Unreleased]

Development continues toward M2: security-constrained AC OPF.

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

[Unreleased]: https://github.com/frederikgeth/DroopOPF.jl/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/frederikgeth/DroopOPF.jl/releases/tag/v0.1.0
