# Solver compatibility and agreement

DroopOPF exposes two mathematically related formulations of fixed droop curves:

- `solve_opf(case; optimizer_factory=Ipopt.Optimizer)` solves the smoothed NLP.
- `solve_opf(case; optimizer_factory=MadNLP.Optimizer)` solves the same smoothed NLP through MadNLP.
- `solve_opf_complementarity(case)` solves the exact PWL droop graph through CCOpt.

The smooth formulation uses `LogExpFunctions.log1pexp` for stable softplus
terms. The complementarity formulation represents each voltage hinge as
`z >= 0 ⟂ z - a >= 0`, then represents reactive clipping as the KKT system for
projection of the raw droop value onto `[Qmin, Qmax]`.

## What agreement means

`solve_opf` with the standard `MadNLP.Optimizer` factory uses exact variable
bounds (`bound_relax_factor=0`). The upstream relaxed-bound default reproduced
`SLOW_PROGRESS` under Linux Julia 1.10 package-test settings despite tiny primal
residuals; exact bounds restored native convergence at the same tolerance.
Explicit optimizer attributes override the default, and custom factories retain
their own configuration. The regression continues to require successful solver
termination as well as physical agreement.

The single-case CCOpt wrapper uses exact variable bounds and `1e-14` for both
relaxation floors so the upstream `1e-8` defaults do not obstruct convergence.
Caller-supplied optimizer attributes still override these defaults. No solver
success status is inferred from residuals: `SLOW_PROGRESS` remains a failure.
In addition to the routine checks below, the regression suite requires native
CCOpt convergence at `1e-10`, complementarity error below `1e-10`, power error
below `1e-9`, and exact-droop error below `1e-8` on the small compatibility case.

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

## M2 and M3 scope

| Capability | Ipopt | MadNLP | CCOpt |
|---|---|---|---|
| M2 fixed-curve SCOPF | smooth | smooth, warm-start recommended | exact complementarity |
| M3 bounded parameter design | smooth | smooth, warm-start recommended | unsupported |
| M3 reconstructed fixed curve | smooth re-solve available | smooth re-solve available | exact complementarity re-solve |

The regression matrix warm-starts MadNLP from validated Ipopt M2 states at the
`1e-5` smoothing width. This is part of the compatibility contract: a cold
MadNLP start is not guaranteed to select the same local solution. Ipopt and
MadNLP must both pass independent exact-curve validation and agree on objective
within tolerance; optimized settings are not required to be identical.

M3 parameter optimization rejects `CCOpt.Optimizer` because the design model
uses differentiable droop-parameter variables. CCOpt is used only after those
parameters have been fixed and reconstructed as an ordinary `VoltVarDroop`.
`validate_droop_design` performs solver-independent exact algebraic replay of
the optimized states. A separate CCOpt re-solve is accepted only when
`equilibrium_report` passes.
