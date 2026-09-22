# S1 feasibility and stress audit

Every audited group has an independently validated witness: **true**. These are local feasibility witnesses for DroopOPF's model, not global-optimality certificates or reproduction of the source PGLib objective.

| Group | Attempts | Validated witnesses | Numerical/iteration failures | Converged but rejected | Feasibility established |
|---|---:|---:|---:|---:|---:|
| public118_baseline | 1 | 1 | 0 | 0 | true |
| public118_load1.0 | 6 | 3 | 3 | 0 | true |
| public118_load1.05 | 6 | 2 | 3 | 1 | true |
| public300_baseline | 1 | 1 | 0 | 0 | true |
| public300_load1.0 | 6 | 1 | 5 | 0 | true |
| public300_load1.05 | 6 | 2 | 4 | 0 | true |

The +5% cases scale both active and reactive demand while retaining the same network, generator bounds and synthetic controller envelopes. They test numerical robustness under reduced operating margin and changed active sets. Because both stressed networks have validated witnesses, failed attempts expose start/backend/formulation sensitivity at that stress point; they do not establish physical infeasibility. The audit does not locate a loadability boundary.
