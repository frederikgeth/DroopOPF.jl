# DroopOPF.jl

DroopOPF.jl is a Julia library for AC optimal power flow with generator
volt-var droop controls. It provides a common data model, smooth nonlinear
programming formulation, exact complementarity formulation, equilibrium
validation, and solver-comparison tooling.

!!! note "Current status"

    Version `0.3.0` delivers milestone M3: validated parameter sweeps, bounded
    standard-droop design, exact PWL replay, and held-out contingency checks.

    Version `0.4.0` adds M4 robustness, public-case regressions, timing,
    allocation and process peak RSS measurements, and the scale-up decision.

## Formulations

| Use case | Entry point |
|---|---|
| Smooth AC OPF with Ipopt | `solve_opf(case)` |
| Smooth AC OPF with MadNLP | `solve_opf(case; optimizer_factory = MadNLP.Optimizer)` |
| Exact PWL droop graph with CCOpt | `solve_opf_complementarity(case)` |
| Independent equilibrium checks | `equilibrium_report(case, result)` |
| Droop operating-point plot | `write_droop_plot(...)` |
| Validated M3 slope sweep | `sweep_droop_slope(...)` |
| Bounded M3 droop design | `optimize_droop_parameters(...)` |
| Named SCOPF multi-start comparison | `solve_scopf_multistart(...)` |
| Breakpoint and binding diagnostics | `scopf_diagnostics(...)` |
| Reproducible SCOPF measurements | `benchmark_scopf(...)` |

The smooth model uses stable softplus terms and generator-specific reactive
smoothing widths. The complementarity model encodes the voltage hinges and
reactive clipping directly as complementarity pairs.

## Where to begin

- [Getting started](getting_started.md) — install and solve a first case.
- [Data model](data_model.md) — construct networks, generators, and droops.
- [Solver formulations](solvers.md) — choose smooth or exact
  complementarity semantics.
- [Validation](validation.md) — check physical equilibrium and curve
  membership independently of the solver.
- [M3 droop optimization](droop_optimization.md) — compare fixed candidates,
  optimize bounded settings, and validate held-out scenarios.
- [M4 robustness](robustness.md) — compare starts and extract structured
  breakpoint, limit, and critical-scenario findings.
- [M4 scale-up decision](scale_up_decision.md) — inspect measured model-size,
  timing, and allocation evidence before choosing a scaling algorithm.
- [Examples](examples.md) — reproduce the M1 regime and solver studies.
- [API reference](api.md) — generated documentation for exported
  types and functions.

The project-level [architecture](https://github.com/frederikgeth/DroopOPF.jl/blob/main/ARCHITECTURE.md)
and [roadmap](https://github.com/frederikgeth/DroopOPF.jl/blob/main/ROADMAP.md)
provide the broader design context.
