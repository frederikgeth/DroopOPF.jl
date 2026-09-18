# M4 robustness and diagnostics

M4 asks a narrower question than scale-up: are the existing small-system M2
and M3 workflows repeatable and diagnostically useful? The implemented
milestone provides named SCOPF and M3 design-parameter multi-start experiments,
structured operating diagnostics, public-case regressions, reproducible
measurements, and an explicit scale-up decision.

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
`SCOPFDiagnostics` artifact. Keeping it separate avoids changing the stable M2
`SCOPFReport` schema.

For each active generator control and scenario it records the regulated
voltage, exact PWL regime, nearest breakpoint value and index, absolute voltage
distance, and near-breakpoint classification. Structured findings cover solver
failure, independent-validation failure, near-breakpoint operation, and bus,
branch, or generator limits within `binding_tolerance`.

The critical contingency is the non-base scenario with the smallest
independently recomputed margin across voltage, generator P/Q, and branch
thermal limits. This minimum-margin rule is a screening heuristic; it is not a
transient or voltage-stability ranking.

## M3 design-parameter starts

`optimize_droop_multistart` varies actual starting values for slope, voltage
reference, and both deadband widths inside the design NLP. Every named input,
optimized design, and exact-curve validation report is retained. The result
classifies objective agreement and separately reports component-wise final
parameter spread, since similar objective values do not prove that the design
parameters are identifiable.

```sh
julia --project=. examples/m4_design_multistart.jl /tmp/droopopf-m4-design
```

The workflow writes `design_multistart.json` and `design_multistart.md`.

## Reproducible workflow

```sh
julia --project=. examples/m4_robustness_workflow.jl /tmp/droopopf-m4
```

The workflow compares cold, converged, low-voltage, and high-voltage starts and
writes `multistart.json`, `multistart.md`, `diagnostics.json`, and
`diagnostics.md`. It perturbs only initial guesses, not study data or tolerances.

## Public regressions and measurements

PGLib-OPF v23.07 case 3 and case 5 are pinned under `test/data/pglib` with
machine-readable CC BY 4.0 provenance. Both run through the normal MATPOWER
adapter, control attachment, solver, serialization, and independent validation
path. `benchmark_scopf` records Julia/package/solver identity, structural case
size, actual JuMP variable and constraint counts, elapsed time, Julia
allocations, termination, objective, and validation status.
Peak process RSS is recorded separately in bytes using `Sys.maxrss()`. The
workflow runs each study in a fresh Julia process. RSS includes compilation,
warm-up and validation; it is a lifetime high-water mark, not incremental solve
memory or a quantity to subtract between samples.

These are PGLib-derived droop regressions, not reproductions of the published
economic OPF benchmarks. DroopOPF uses its schedule-deviation objective and adds
one droop controller; the adapter does not enforce MATPOWER angle-difference
bounds or use generator costs. The selected cases have no bus shunts or
non-unity transformer taps. Source tables and these modeling differences must
be distinguished when interpreting results.

```sh
julia --project=. examples/m4_benchmark_workflow.jl /tmp/droopopf-m4-benchmark
```

See the [M4 scale-up decision](scale_up_decision.md) for the measured evidence
and the decision not to select a P2 scaling algorithm from tiny-case data.
