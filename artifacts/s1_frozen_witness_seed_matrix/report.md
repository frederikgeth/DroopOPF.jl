# Frozen S1 same-case witness-seed matrix

Each unresolved direct frozen cell is rerun with unchanged model, smoothing, strict validation and one-reset budget, using a validated witness from the same network/load case. The seed contains the full physical decision: AC state plus tap, shunt, and droop settings. Same-backend seeds are preferred; cross-backend seeds transfer physical primals only, never duals. This does not replace the direct-start matrix.

| Direct cell | Direct status | Target backend | Witness | Seed compatibility | Result | Final status | Attempts |
|---|---|---|---|---|---|---|---:|
| public118-load1.0-madnlp-anchor | SLOW_PROGRESS | madnlp | public118-load1.0-ipopt-anchor | cross_backend_primal_no_duals | FAIL | SLOW_PROGRESS | 2 |
| public118-load1.0-madnlp-flat_high | LOCALLY_INFEASIBLE | madnlp | public118-load1.0-ipopt-anchor | cross_backend_primal_no_duals | FAIL | SLOW_PROGRESS | 2 |
| public118-load1.0-madnlp-flat_low | SLOW_PROGRESS | madnlp | public118-load1.0-ipopt-anchor | cross_backend_primal_no_duals | FAIL | SLOW_PROGRESS | 2 |
| public118-load1.05-ipopt-flat_high | ITERATION_LIMIT | ipopt | public118-load1.05-ipopt-anchor | same_backend_primal | FAIL | LOCALLY_SOLVED | 1 |
| public118-load1.05-ipopt-flat_low | ITERATION_LIMIT | ipopt | public118-load1.05-ipopt-anchor | same_backend_primal | FAIL | LOCALLY_SOLVED | 1 |
| public118-load1.05-madnlp-anchor | SLOW_PROGRESS | madnlp | public118-load1.05-madnlp-flat_low | same_backend_primal | PASS | LOCALLY_SOLVED | 1 |
| public118-load1.05-madnlp-flat_high | SLOW_PROGRESS | madnlp | public118-load1.05-madnlp-flat_low | same_backend_primal | PASS | LOCALLY_SOLVED | 1 |
| public300-load1.0-ipopt-flat_high | ITERATION_LIMIT | ipopt | public300-load1.0-ipopt-anchor | same_backend_primal | PASS | ALMOST_LOCALLY_SOLVED | 2 |
| public300-load1.0-ipopt-flat_low | ITERATION_LIMIT | ipopt | public300-load1.0-ipopt-anchor | same_backend_primal | PASS | ALMOST_LOCALLY_SOLVED | 2 |
| public300-load1.0-madnlp-flat_high | LOCALLY_SOLVED | madnlp | public300-load1.0-madnlp-anchor | same_backend_primal | PASS | LOCALLY_SOLVED | 1 |
| public300-load1.0-madnlp-flat_low | ITERATION_LIMIT | madnlp | public300-load1.0-madnlp-anchor | same_backend_primal | PASS | LOCALLY_SOLVED | 1 |
| public300-load1.05-madnlp-flat_high | SLOW_PROGRESS | madnlp | public300-load1.05-madnlp-anchor | same_backend_primal | PASS | LOCALLY_SOLVED | 2 |

Strict witness-seed passes: **7/12**. A failure remains solver-path evidence, not an infeasibility certificate.
