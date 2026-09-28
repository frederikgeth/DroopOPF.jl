# S1 incremental droop/shunt isolation

This diagnostic starts from the untouched PGLib import and adds controls cumulatively in deterministic frozen-overlay order. `droopN-fixed` adds N nominal droop equalities without design variables; `droopN-free` additionally frees their slopes. `shuntN-free` adds N initially disconnected synthetic banks with no droop attachments. The paired rows contain exactly one droop and one bank. Transformer ratios remain at source values. Every cell uses the frozen epsilon `1e-6`, exact-droop gate `1e-5`, anchor start, and one-reset policy.

Status: **complete** (16/16).

| Stage | Passed | Failed | Total |
|---|---:|---:|---:|
| selected5-fixed | 5 | 3 | 8 |
| selected5-free | 4 | 4 | 8 |

## Every cell

| Network | Load | Solver | Stage | Result | Reason |
|---:|---:|---|---|---|---|
| 300 | 1.0 | ipopt | selected5-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | selected5-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | selected5-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | selected5-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | selected5-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | selected5-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | selected5-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | selected5-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | selected5-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.02 | ipopt | selected5-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.02 | madnlp | selected5-fixed | FAIL | solver status ITERATION_LIMIT; physical failures: power_balance, droop |
| 300 | 1.02 | madnlp | selected5-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | ipopt | selected5-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | ipopt | selected5-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | madnlp | selected5-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | madnlp | selected5-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |

A failed nonlinear solve is path evidence, not an infeasibility certificate. The raw stage separates source-case difficulty; fixed-droop stages isolate adding controller equations; free-droop stages isolate parameter freedom; zero-droop shunt stages isolate shunt variables.
