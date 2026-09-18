# DroopOPF.jl v0.4.0 — M4 robustness and benchmark gate

M4 adds named M2 state and M3 droop-parameter multi-start experiments, retaining
inputs, independent validation reports, objective agreement and parameter
spread. Structured diagnostics identify breakpoint proximity, binding limits,
solver/validation failures and the minimum-margin contingency.

Two pinned PGLib-OPF v23.07 cases exercise loading, droop attachment, solving,
serialization and validation. Their attribution and modeling differences are
documented; these regressions do not reproduce the economic PGLib objective.

Benchmark reports record model size, elapsed time, Julia allocations and OS
process peak RSS. Each reference study runs in a fresh process. RSS includes
compilation and warm-up; it is not incremental solver memory. Raw evidence is
included in `m4_validation/benchmarks`.

The scale-up decision retains full enumeration: these small cases do not
establish a bottleneck that justifies a P2 scaling algorithm. Multi-start
objective agreement also does not establish unique optimized parameters.

Validation: 338/338 local tests passed and the v0.4.0 documentation built.
M1–M3 solver compatibility remains covered by the suite.

Reproduce from the checkout:

```sh
julia --project=. examples/m4_robustness_workflow.jl /tmp/droopopf-m4
julia --project=. examples/m4_design_multistart.jl /tmp/droopopf-m4-design
julia --project=. examples/m4_benchmark_workflow.jl /tmp/droopopf-m4-benchmark
```
