# DroopOPF.jl

DroopOPF.jl is a Julia library for AC optimal power flow with generator
volt-var droop controls. It provides a common data model, smooth nonlinear
programming formulation, exact complementarity formulation, equilibrium
validation, and solver-comparison tooling.

!!! note "Current status"

    Version `0.1.0` delivers milestone M1: AC OPF with static generator
    volt-var droops. Security-constrained OPF is planned for M2, followed by
    droop-curve optimization in M3.

## Formulations

| Use case | Entry point |
|---|---|
| Smooth AC OPF with Ipopt | `solve_opf(case)` |
| Smooth AC OPF with MadNLP | `solve_opf(case; optimizer_factory = MadNLP.Optimizer)` |
| Exact PWL droop graph with CCOpt | `solve_opf_complementarity(case)` |
| Independent equilibrium checks | `equilibrium_report(case, result)` |
| Droop operating-point plot | `write_droop_plot(...)` |

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
- [Examples](examples.md) — reproduce the M1 regime and solver studies.
- [API reference](api.md) — generated documentation for exported
  types and functions.

The project-level [architecture](https://github.com/frederikgeth/DroopOPF.jl/blob/main/ARCHITECTURE.md)
and [roadmap](https://github.com/frederikgeth/DroopOPF.jl/blob/main/ROADMAP.md)
provide the broader design context.
