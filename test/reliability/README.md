# Reliability workloads

IEEE 118 and IEEE 300 are intentionally excluded from `test/runtests.jl`.
They are retained as explicit reliability workloads because their solve time,
initialization sensitivity, and solver outcomes are evidence—not unit-test
assertions.

Run the frozen exact-CCOpt lane with:

```sh
julia --project=. examples/s1_ccopt_policy_matrix.jl artifacts/s1_ccopt_frozen
```

The follow-up cross-seed, droop-only feasibility, and IEEE-300 continuation
commands are documented in `docs/src/s1_ccopt.md` and retain checkpointed
artifacts under `artifacts/s1_ccopt_*`.

The public-case test checks, when wanted, are run separately:

```sh
julia --project=. test/reliability/runtests.jl
```
