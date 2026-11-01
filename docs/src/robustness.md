# Robustness and diagnostics

Use repeated starts to test whether a nonconvex solve returns comparable,
independently valid operating points. Diagnose control breakpoints and binding
limits separately from objective agreement.

## Multi-start comparison

`solve_scopf_multistart` accepts a dictionary from a start name to the usual
scenario/state dictionary. An empty dictionary is a cold start. Every run is
solved and independently validated; invalid or divergent outcomes are retained.

```julia
starts = Dict(:cold => Dict(), :warm => previous_result.states)
comparison = solve_scopf_multistart(study, starts;
    smooth_epsilon=1e-5, objective_atol=1e-8, objective_rtol=1e-6)
```

The classification is one of:

- `:comparable`: at least two independently valid objectives agree within
  `atol + rtol * maximum(abs, objectives)`;
- `:divergent`: at least two valid objectives exceed that spread;
- `:insufficient_valid_runs`: exactly one run is independently valid;
- `:no_valid_runs`: no run passes validation with a finite objective.

`best_run` is selected only among independently valid runs. It is a convenience
for follow-on analysis, not evidence that divergent local solutions are
interchangeable. The JSON artifact records every labelled solver result,
validation report, valid-run set, objective range, and decision.

## Breakpoint and binding diagnostics

`scopf_diagnostics(study, result)` recomputes validation and returns a separate
`SCOPFDiagnostics` artifact. It is returned separately from the stable `SCOPFReport` schema.

For each active generator control and scenario it records the regulated
voltage, exact PWL regime, nearest breakpoint value and index, absolute voltage
distance, and near-breakpoint classification. Structured findings cover solver
failure, independent-validation failure, near-breakpoint operation, and bus,
branch, or generator limits within `binding_tolerance`.

The critical contingency is the non-base scenario with the smallest
independently recomputed margin across voltage, generator P/Q, and branch
thermal limits. This minimum-margin rule is a screening heuristic; it is not a
transient or voltage-stability ranking.

## droop design design-parameter starts

`optimize_droop_multistart` varies actual starting values for slope, voltage
reference, and both deadband widths inside the design NLP. Every named input,
optimized design, and exact-curve validation report is retained. The result
classifies objective agreement and separately reports component-wise final
parameter spread, since similar objective values do not prove that the design
parameters are identifiable.


The workflow writes `design_multistart.json` and `design_multistart.md`.

## Record performance reproducibly

`benchmark_scopf` records package/solver identity, model dimensions, elapsed time,
Julia allocations, objective, termination and validation. Measure compilation,
model construction, optimization and replay separately where possible. Process
peak memory is a lifetime high-water mark; it is not incremental model memory.

Keep all failed starts. Similar objective values can conceal different controller
settings, and neither multi-start agreement nor a small test case proves global
optimality or large-network scalability.
