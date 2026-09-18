# M3 droop optimization

M3 begins with a deliberately small, auditable problem: vary one positive
volt-var slope over a bounded candidate set and solve the complete M2
security-constrained AC OPF for every setting. This establishes the reference
surface that in-model optimization must reproduce.

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

## Bounded in-model design

`optimize_droop_parameters` promotes selected physical settings to variables
shared across the base case and every training contingency. Bounds omitted by
the caller fix that setting at its M2 value. Available settings are:

- positive slope;
- positive voltage reference;
- nonnegative lower and upper deadband widths.

The two widths may differ, providing an asymmetric deadband while preserving
the standard saturated `VoltVarDroop` family. The active/reactive dispatch
objective remains the M2 objective; no hidden design penalty is introduced.

```julia
design = optimize_droop_parameters(
    study,
    2;
    slope_bounds = (0.04, 0.10),
    v_ref_bounds = (0.995, 1.005),
    deadband_low_bounds = (0.005, 0.015),
    deadband_high_bounds = (0.005, 0.015),
    smooth_epsilon = 1e-5,
)
```

`with_droop_settings(study, design)` reconstructs an ordinary typed study.
`validate_droop_design(study, design)` independently replays every state against
that reconstructed exact PWL curve. A design is not accepted from solver status
alone.

## Held-out scenarios

`evaluate_held_out_contingencies` holds the optimized base dispatch fixed and
solves contingencies whose IDs were absent from training:

```julia
held_out = evaluate_held_out_contingencies(
    study,
    design,
    [Contingency(:line_33; branch_ids = [33])],
)
held_out.report.valid
```

The returned study, result, and report retain the normal M2 data and validation
contracts. `write_droop_design` and `read_droop_design` provide a versioned JSON
round trip for the optimized settings and training result.

## Acceptance gates

M3 requires all of the following:

1. fixed bounds at the reference reproduce the M2 objective;
2. slope-only optimization agrees with the minimum of the fixed-slope sweep;
3. generalized bounded settings satisfy every training scenario;
4. reconstructed exact curves pass independent replay;
5. at least one excluded contingency passes held-out evaluation;
6. the end-to-end workflow regenerates machine-readable and visual artifacts.

## Scope limit

M3 optimizes the identifiable physical parameters of the standard saturated
volt-var family. Reactive capability and reactive output at deadband remain
fixed. Arbitrary free-knot PWL topology optimization is intentionally deferred:
without a separate regularization and identifiability contract it can overfit a
small contingency set while producing non-unique, hard-to-interpret curves.
