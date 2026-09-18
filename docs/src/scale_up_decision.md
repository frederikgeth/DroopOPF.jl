# M4 scale-up decision

## Decision

Do not begin a P2 scaling algorithm yet. M4 finds no performance bottleneck at
the validated reference scale. Scenario replication is the largest measured
increment, but the current evidence is too small to choose contingency
screening, constraint generation, parallel evaluation, ExaModels, or
distributed decomposition.

This is a decision to preserve the existing formulation, not a claim that it
will scale indefinitely.

## Evidence

Run on Julia 1.12.4, DroopOPF 0.4.0, and Ipopt with one excluded warm-up and
three measured samples per fresh process. Raw JSON/Markdown is retained in
`m4_validation/benchmarks`:

| Study | Scenarios | Variables | Constraints | Median time | Allocations/sample | Process peak RSS |
|---|---:|---:|---:|---:|---:|---:|
| PGLib case 3 | 1 | 12 | 36 | 0.00308 s | 687,856 B | 946,094,080 B |
| PGLib case 5 | 1 | 20 | 62 | 0.00652 s | 1,341,008 B | 954,433,536 B |
| M2 full enumeration | 3 | 32 | 97 | 0.01372 s | 1,900,128 B | 924,794,880 B |

Every measured solve independently validated and returned the same objective
across its three samples. The benchmark includes model construction,
optimization, and result extraction. Allocation counts are Julia allocations,
and differ from process peak resident memory. Peak RSS includes startup,
compilation, warm-up, solves and validation, including native allocations.
These process peaks are dominated by the Julia runtime and compilation at this
scale and do not measure incremental solver memory.

The PGLib fixtures are pinned to PGLib-OPF v23.07 with machine-readable source,
license, retrieval date, and local-transformation metadata. PGLib-OPF is curated
by the IEEE PES Task Force, distributes its cases in MATPOWER format, and
licenses the data under CC BY 4.0. See the
[upstream repository](https://github.com/power-grid-lib/pglib-opf/tree/v23.07)
and local `test/data/pglib/provenance.json`.

## Interpretation

The three-scenario M2 model is roughly 2.1 times slower than the five-bus base
case in this run. That observation is consistent with scenario replication but
does not isolate a solver, formulation, memory, or contingency-enumeration
bottleneck. Three tiny data points cannot support a scaling law.

Consequently:

- retain full enumeration and the current JuMP formulation for validated small
  studies;
- retain warm starts and MadNLP as compatibility options, not claimed
  performance remedies;
- do not implement a P2 algorithm merely because one is available;
- before crossing the scale-up gate, add a separate medium-case experiment with
  increasing contingency counts and profile build time versus solver time.

## Reproduction

```sh
julia --project=. examples/m4_benchmark_workflow.jl /tmp/droopopf-m4-benchmark
```

The workflow writes JSON and Markdown per study plus the copied PGLib provenance
record. Timing values above are evidence from one machine and should not be used
as portable performance promises.
