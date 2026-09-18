# M3 droop-slope search

M3 begins with a deliberately small, auditable problem: vary one positive
volt-var slope over a bounded candidate set and solve the complete M2
security-constrained AC OPF for every setting. This establishes the reference
surface that later in-model optimization must reproduce.

## Contract

`sweep_droop_slope(study, control_id, slopes)`:

- preserves the input study and changes only the selected control's slope;
- always includes and solves the declared reference slope;
- solves candidates outward from the reference and warm-starts from the nearest
  valid result;
- validates every candidate independently with `equilibrium_report`;
- records objective, worst voltage deviation, maximum branch loading, exact
  droop residual, validity, and solver termination status.

The slope uses the existing `VoltVarDroop` convention: per-unit voltage change
per unit reactive output. Candidate and reference slopes must be positive and
finite.

## Example

```julia
sweep = sweep_droop_slope(
    study,
    2,
    0.04:0.005:0.10;
    reference_slope = 0.075,
    smooth_epsilon = 1e-5,
)

best = best_droop_slope(sweep)
write_droop_slope_sweep("m3_slope_sweep.json", sweep)
write_droop_slope_sweep_plot("m3_slope_tradeoff.svg", sweep)
```

`best_droop_slope` selects the valid sampled point with the smallest M2 dispatch
objective. It is a parameter-search result, not a global optimality certificate.
The AC model is nonconvex, and the current objective may be weakly sensitive to
the droop setting, so voltage and loading diagnostics should be reviewed with
the objective.

## M2 reproduction gate

When the selected slope equals the slope already stored in the study, the sweep
reconstructs the same M2 problem. The test suite requires that reference point
to reproduce the independently valid M2 objective. This prevents the M3 search
layer from silently changing contingency policy or physical semantics.

## Next M3 slices

1. Add a bounded slope decision variable to the SCOPF formulation and compare
   the optimized result against a refined fixed-slope sweep.
2. Add voltage-reference and deadband parameters one at a time, preserving the
   same reproduction and independent-validation gates.
3. Evaluate chosen settings on held-out contingencies before accepting them.
4. Generalize the curve representation only after the scalar cases remain
   reproducible and interpretable.
