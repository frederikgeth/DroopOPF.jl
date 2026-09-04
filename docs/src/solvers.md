# Solver formulations

## Smooth nonlinear programming

`solve_opf` encodes the positive-part terms in the volt-var graph with stable
softplus functions based on `LogExpFunctions.log1pexp`. Ipopt is the default:

```julia
ipopt_result = solve_opf(case; smooth_epsilon = 1.0e-3)
```

MadNLP receives the same JuMP model and can be selected through the optimizer
factory:

```julia
using MadNLP
madnlp_result = solve_opf(
    case;
    optimizer_factory = MadNLP.Optimizer,
    smooth_epsilon = 1.0e-3,
)
```

The voltage smoothing width is in per-unit voltage. By default, reactive
smoothing is a relative fraction of each control's available reactive range;
`smooth_reactive_epsilon` can override it with an absolute per-unit width.

## Exact complementarity formulation

`solve_opf_complementarity` uses MathOptComplements and CCOpt. Each voltage
hinge is represented as a nonnegative complementarity pair. Reactive clipping
is represented by the KKT conditions for projection of the raw droop value
onto the control's reactive interval.

```julia
ccopt_result = solve_opf_complementarity(case)
```

The exact formulation has no smoothing parameter. CCOpt may report
`ALMOST_LOCALLY_SOLVED` after its homotopy; use the independent equilibrium
report and `complementarity_residual_max` to assess the result.

## Comparing solutions

Ipopt and MadNLP should usually agree closely because they solve the same
smoothed NLP. CCOpt solves the exact PWL graph, so compare physical residuals,
objectives, operating regimes, and state differences rather than expecting
bitwise equality. The reproducible comparison is:

```sh
julia --project=. examples/m1_solver_comparison.jl
```

See [Solver compatibility](https://github.com/frederikgeth/DroopOPF.jl/blob/main/SOLVER_COMPATIBILITY.md)
for recommended starting tolerances.
