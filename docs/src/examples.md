# Examples

## Volt-var regimes

The M1 regime case deliberately places three generators in different regions
of their curves:

```sh
julia --project=. examples/m1_regime_case_study.jl
```

It reports the exact curve value and residual for each operating point and
writes `m1_regime_case_study.svg`.

## Three-solver comparison

The solver comparison runs Ipopt, MadNLP, and CCOpt on the same case:

```sh
julia --project=. examples/m1_solver_comparison.jl
```

It prints solver status, objective, AC residual, exact droop residual,
complementarity residual, and per-generator curve errors. It writes
`m1_solver_comparison.svg` with colour-coded droop curves and distinct markers
for each solver.

![M1 solver comparison](https://raw.githubusercontent.com/frederikgeth/DroopOPF.jl/main/m1_solver_comparison.png)

The generated figure is intended as a regression artifact as well as a visual
explanation of the deadband, proportional, and saturation encodings.

## M2 scenario validation

The M2 workflow solves the base case, a line outage, and a generator outage,
using distinct generator droop coefficients of 0.05 and 0.075 pu voltage per
unit reactive output. The workflow uses a `1e-5` smoothing width for this
heterogeneous fixture, then writes numerical reports and a five-figure
visual-validation bundle:

```sh
julia --project=. examples/m2_workflow.jl /tmp/droopopf-m2
```

The figures compare scenario droop operating points, bus voltages, branch
loading, generator dispatch, and independently recomputed residuals against
their tolerances. See [Security-constrained AC OPF](scopf.md#visual-validation)
for the plot semantics and individual writer functions.
