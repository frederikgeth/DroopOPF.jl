# S1 feasibility and stress interpretation

The retained public evidence is audited before solver failures are interpreted.
Both imported IEEE 118 and IEEE 300 base cases have independently validated
local equilibria in DroopOPF. The nominal and +5% synthetic-control overlays
also each have at least one fully validated witness:

| Group | Direct attempts | Validated witnesses |
|---|---:|---:|
| IEEE 118 baseline | 1 | 1 |
| IEEE 118 nominal controls | 6 | 3 |
| IEEE 118 +5% demand | 6 | 2 |
| IEEE 300 baseline | 1 | 1 |
| IEEE 300 nominal controls | 6 | 1 |
| IEEE 300 +5% demand | 6 | 2 |

Accordingly, a failed solver/start attempt in one of these exact groups is not
evidence that the case is infeasible: another attempt supplies a validated
witness for the same formulation and loading. Such failures expose numerical
convergence, initialization, backend or physical-acceptance sensitivity.

The +5% stress multiplies both active and reactive demand while keeping the
network, generator bounds and synthetic control envelopes unchanged. It reduces
operating margin and can change active bounds and droop regimes. It is not a
loadability search and does not identify a maximum feasible loading factor.

These witnesses apply to DroopOPF's imported-network, dispatch-deviation model.
They do not prove global optimality or uniqueness, reproduce the source PGLib
generation-cost objective, or enforce source branch-angle limits that are not
part of the implemented optimization model.

Reproduce the audit with:

```sh
julia --project=. examples/s1_feasibility_audit.jl \
  artifacts/s1_public_controls/summary.json artifacts/s1_feasibility_audit
```
