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
