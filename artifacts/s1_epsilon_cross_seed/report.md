# S1 epsilon accepted-state cross-seed recovery

Each unresolved continuation cell receives one deterministic strict-valid source with the same solver, network size, and load factor. The recovery solve uses `epsilon=1e-6`. This tests reusable basin information; it does not preserve independent starts or the frozen solve budget.

| Target | Source | Source epsilon | Status | Strict valid | Raw mismatch (pu) |
|---|---|---:|---|---:|---:|
| `public118-load1.05-ipopt-flat_high` | `public118-load1.05-ipopt-anchor` | 1.0e-7 | LOCALLY_SOLVED | false | 1.4269644872721976e-5 |
| `public118-load1.05-ipopt-flat_low` | `public118-load1.05-ipopt-anchor` | 1.0e-7 | LOCALLY_SOLVED | false | 1.4269644872721976e-5 |
| `public300-load1.0-ipopt-flat_low` | `public300-load1.0-ipopt-anchor` | 1.0e-6 | ITERATION_LIMIT | false | 1.1545393516914213 |
| `public300-load1.0-madnlp-flat_high` | `public300-load1.0-madnlp-anchor` | 1.0e-7 | LOCALLY_SOLVED | true | 1.5987211554602254e-14 |
| `public300-load1.05-ipopt-anchor` | `public300-load1.05-ipopt-flat_high` | 1.0e-6 | ITERATION_LIMIT | false | 1.373714162609276 |
| `public300-load1.05-madnlp-anchor` | `public300-load1.05-madnlp-flat_low` | 1.0e-5 | SLOW_PROGRESS | false | 1.0621976282654266e-5 |

Recovered **1/6** previously unresolved continuation cells.
