# Solver compatibility and agreement

DroopOPF exposes two mathematically related formulations of M1:

- `solve_opf(case; optimizer_factory=Ipopt.Optimizer)` solves the smoothed NLP.
- `solve_opf(case; optimizer_factory=MadNLP.Optimizer)` solves the same smoothed NLP through MadNLP.
- `solve_opf_complementarity(case)` solves the exact PWL droop graph through CCOpt.

The smooth formulation uses `LogExpFunctions.log1pexp` for stable softplus
terms. The complementarity formulation represents each voltage hinge as
`z >= 0 ⟂ z - a >= 0`, then represents reactive clipping as the KKT system for
projection of the raw droop value onto `[Qmin, Qmax]`.

## What agreement means

Ipopt and MadNLP should generally agree very closely because they receive the
same smooth NLP, objective, bounds, and constraints. CCOpt solves a different
numerical problem: its complementarity homotopy follows the exact PWL graph,
while the smooth solvers follow an approximation. Agreement should therefore
be assessed on physical residuals and operating regimes, not only on the last
digits of the objective.

For the small M1 regression case, the following practical checks are suitable:

| Check | Routine test threshold | Interpretation |
|---|---:|---|
| AC power-balance residual | `1e-5` pu | Physical equilibrium check |
| Exact droop residual | `5e-4` pu | Generator operating point on curve |
| CCOpt complementarity product | `1e-5` pu² | Complementarity feasibility |
| Ipopt/MadNLP state difference | `1e-6` pu | Same smoothed NLP |
| Cross-formulation voltage difference | `1e-4` pu | Same operating regime/solution |
| Cross-formulation reactive-power difference | `1e-4` pu | Same physical dispatch |

These are starting points, not universal guarantees. For larger networks,
poorly scaled data, near-degenerate breakpoints, or a looser CCOpt homotopy,
use per-unit tolerances relative to the relevant generator capability and
report both absolute and scaled residuals. A cross-solver comparison should
also require matching `droop_regime` values for each attached generator.

Run the reproducible comparison with:

```sh
julia --project=. examples/m1_solver_comparison.jl
```

It prints solver status, objective, AC/droop/complementarity residuals, and
each operating point's exact curve error. It also writes
`m1_solver_comparison.svg`.
