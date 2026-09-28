# S1 incremental droop/shunt isolation

This diagnostic starts from the untouched PGLib import and adds controls cumulatively in deterministic frozen-overlay order. `droopN-fixed` adds N nominal droop equalities without design variables; `droopN-free` additionally frees their slopes. `shuntN-free` adds N initially disconnected synthetic banks with no droop attachments. The paired rows contain exactly one droop and one bank. Transformer ratios remain at source values. Every cell uses the frozen epsilon `1e-6`, exact-droop gate `1e-5`, anchor start, and one-reset policy.

Status: **complete** (320/320).

| Stage | Passed | Failed | Total |
|---|---:|---:|---:|
| droop1-fixed | 12 | 0 | 12 |
| droop1-fixed-shunt1-free | 12 | 0 | 12 |
| droop1-free | 12 | 0 | 12 |
| droop1-free-shunt1-free | 12 | 0 | 12 |
| droop16-fixed | 4 | 8 | 12 |
| droop16-free | 7 | 5 | 12 |
| droop2-fixed | 12 | 0 | 12 |
| droop2-free | 12 | 0 | 12 |
| droop32-fixed | 5 | 7 | 12 |
| droop32-free | 8 | 4 | 12 |
| droop35-fixed | 2 | 6 | 8 |
| droop35-free | 3 | 5 | 8 |
| droop37-fixed | 3 | 1 | 4 |
| droop37-free | 3 | 1 | 4 |
| droop4-fixed | 12 | 0 | 12 |
| droop4-free | 12 | 0 | 12 |
| droop5-fixed | 4 | 4 | 8 |
| droop5-free | 4 | 4 | 8 |
| droop6-fixed | 6 | 2 | 8 |
| droop6-free | 6 | 2 | 8 |
| droop7-fixed | 5 | 3 | 8 |
| droop7-free | 5 | 3 | 8 |
| droop8-fixed | 8 | 4 | 12 |
| droop8-free | 9 | 3 | 12 |
| raw | 12 | 0 | 12 |
| shunt1-free | 12 | 0 | 12 |
| shunt12-free | 4 | 0 | 4 |
| shunt16-free | 8 | 0 | 8 |
| shunt2-free | 12 | 0 | 12 |
| shunt32-free | 8 | 0 | 8 |
| shunt4-free | 12 | 0 | 12 |
| shunt8-free | 12 | 0 | 12 |

## Every cell

| Network | Load | Solver | Stage | Result | Reason |
|---:|---:|---|---|---|---|
| 118 | 1.0 | ipopt | droop1-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | droop1-fixed-shunt1-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | droop1-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | droop1-free-shunt1-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | droop16-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | droop16-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | droop2-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | droop2-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | droop32-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | droop32-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | droop37-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | droop37-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | droop4-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | droop4-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | droop8-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | droop8-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | raw | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | shunt1-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | shunt12-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | shunt2-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | shunt4-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | ipopt | shunt8-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | droop1-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | droop1-fixed-shunt1-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | droop1-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | droop1-free-shunt1-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | droop16-fixed | FAIL | solver status SLOW_PROGRESS; physical checks unavailable or within tolerance |
| 118 | 1.0 | madnlp | droop16-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | droop2-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | droop2-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | droop32-fixed | FAIL | solver status SLOW_PROGRESS; physical checks unavailable or within tolerance |
| 118 | 1.0 | madnlp | droop32-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | droop37-fixed | FAIL | solver accepted iterate, but physical failures: droop |
| 118 | 1.0 | madnlp | droop37-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | droop4-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | droop4-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | droop8-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | droop8-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | raw | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | shunt1-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | shunt12-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | shunt2-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | shunt4-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.0 | madnlp | shunt8-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | droop1-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | droop1-fixed-shunt1-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | droop1-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | droop1-free-shunt1-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | droop16-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | droop16-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | droop2-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | droop2-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | droop32-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | droop32-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | droop37-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | droop37-free | FAIL | solver accepted iterate, but physical failures: droop |
| 118 | 1.05 | ipopt | droop4-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | droop4-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | droop8-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | droop8-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | raw | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | shunt1-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | shunt12-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | shunt2-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | shunt4-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | ipopt | shunt8-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | droop1-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | droop1-fixed-shunt1-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | droop1-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | droop1-free-shunt1-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | droop16-fixed | FAIL | solver status SLOW_PROGRESS; physical checks unavailable or within tolerance |
| 118 | 1.05 | madnlp | droop16-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | droop2-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | droop2-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | droop32-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | droop32-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | droop37-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | droop37-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | droop4-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | droop4-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | droop8-fixed | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | droop8-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | raw | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | shunt1-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | shunt12-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | shunt2-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | shunt4-free | PASS | passed all solver, policy and physical gates |
| 118 | 1.05 | madnlp | shunt8-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop1-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop1-fixed-shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop1-free-shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop16-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop16-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop2-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop2-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop32-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop32-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop35-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop35-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop4-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop4-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop5-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop5-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop6-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop6-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop7-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop7-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop8-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | droop8-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | raw | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | shunt16-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | shunt2-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | shunt32-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | shunt4-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | ipopt | shunt8-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop1-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop1-fixed-shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop1-free-shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop16-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop16-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop2-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop2-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop32-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop32-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop35-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop35-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop4-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop4-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop5-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop5-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop6-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop6-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop7-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop7-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop8-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | droop8-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | raw | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | shunt16-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | shunt2-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | shunt32-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | shunt4-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.0 | madnlp | shunt8-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop1-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop1-fixed-shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop1-free-shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop16-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.01 | ipopt | droop16-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop2-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop2-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop32-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance, droop |
| 300 | 1.01 | ipopt | droop32-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop35-fixed | FAIL | solver status ITERATION_LIMIT; physical failures: droop, power_balance |
| 300 | 1.01 | ipopt | droop35-free | FAIL | solver status ITERATION_LIMIT; physical failures: droop, power_balance |
| 300 | 1.01 | ipopt | droop4-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop4-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop5-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop5-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop6-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop6-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop7-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop7-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop8-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | droop8-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | raw | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | shunt16-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | shunt2-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | shunt32-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | shunt4-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | ipopt | shunt8-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | droop1-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | droop1-fixed-shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | droop1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | droop1-free-shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | droop16-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.01 | madnlp | droop16-free | FAIL | solver status ITERATION_LIMIT; physical failures: power_balance, droop |
| 300 | 1.01 | madnlp | droop2-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | droop2-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | droop32-fixed | FAIL | solver status ITERATION_LIMIT; physical failures: power_balance, droop |
| 300 | 1.01 | madnlp | droop32-free | FAIL | solver status ITERATION_LIMIT; physical failures: power_balance, droop |
| 300 | 1.01 | madnlp | droop35-fixed | FAIL | solver status ITERATION_LIMIT; physical failures: power_balance, droop |
| 300 | 1.01 | madnlp | droop35-free | FAIL | solver status ITERATION_LIMIT; physical failures: power_balance, droop |
| 300 | 1.01 | madnlp | droop4-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | droop4-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | droop5-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | droop5-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | droop6-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | droop6-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | droop7-fixed | FAIL | solver status ITERATION_LIMIT; physical failures: power_balance |
| 300 | 1.01 | madnlp | droop7-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | droop8-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.01 | madnlp | droop8-free | FAIL | solver status ITERATION_LIMIT; physical failures: power_balance, droop |
| 300 | 1.01 | madnlp | raw | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | shunt16-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | shunt2-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | shunt32-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | shunt4-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.01 | madnlp | shunt8-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | droop1-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | droop1-fixed-shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | droop1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | droop1-free-shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | droop16-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.02 | ipopt | droop16-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.02 | ipopt | droop2-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | droop2-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | droop32-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance, droop |
| 300 | 1.02 | ipopt | droop32-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | droop35-fixed | FAIL | solver accepted iterate, but physical failures: droop |
| 300 | 1.02 | ipopt | droop35-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | droop4-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | droop4-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | droop5-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.02 | ipopt | droop5-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.02 | ipopt | droop6-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | droop6-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | droop7-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | droop7-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | droop8-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | droop8-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | raw | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | shunt16-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | shunt2-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | shunt32-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | shunt4-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | ipopt | shunt8-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | droop1-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | droop1-fixed-shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | droop1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | droop1-free-shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | droop16-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.02 | madnlp | droop16-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.02 | madnlp | droop2-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | droop2-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | droop32-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance, droop |
| 300 | 1.02 | madnlp | droop32-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance, droop |
| 300 | 1.02 | madnlp | droop35-fixed | FAIL | solver status ITERATION_LIMIT; physical failures: power_balance, droop |
| 300 | 1.02 | madnlp | droop35-free | FAIL | solver status NUMERICAL_ERROR; physical failures: power_balance, droop |
| 300 | 1.02 | madnlp | droop4-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | droop4-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | droop5-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.02 | madnlp | droop5-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.02 | madnlp | droop6-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | droop6-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | droop7-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | droop7-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.02 | madnlp | droop8-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.02 | madnlp | droop8-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | raw | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | shunt16-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | shunt2-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | shunt32-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | shunt4-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.02 | madnlp | shunt8-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | ipopt | droop1-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | ipopt | droop1-fixed-shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | ipopt | droop1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | ipopt | droop1-free-shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | ipopt | droop16-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | ipopt | droop16-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | ipopt | droop2-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | ipopt | droop2-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | ipopt | droop32-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | ipopt | droop32-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | ipopt | droop35-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance, droop |
| 300 | 1.03 | ipopt | droop35-free | FAIL | solver status ITERATION_LIMIT; physical failures: power_balance, droop |
| 300 | 1.03 | ipopt | droop4-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | ipopt | droop4-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | ipopt | droop5-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | ipopt | droop5-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | ipopt | droop6-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | ipopt | droop6-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | ipopt | droop7-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | ipopt | droop7-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | ipopt | droop8-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | ipopt | droop8-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | ipopt | raw | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | ipopt | shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | ipopt | shunt16-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | ipopt | shunt2-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | ipopt | shunt32-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | ipopt | shunt4-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | ipopt | shunt8-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | madnlp | droop1-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | madnlp | droop1-fixed-shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | madnlp | droop1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | madnlp | droop1-free-shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | madnlp | droop16-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | madnlp | droop16-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | madnlp | droop2-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | madnlp | droop2-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | madnlp | droop32-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | madnlp | droop32-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | madnlp | droop35-fixed | FAIL | solver status NUMERICAL_ERROR; physical failures: power_balance, droop |
| 300 | 1.03 | madnlp | droop35-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance, droop |
| 300 | 1.03 | madnlp | droop4-fixed | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | madnlp | droop4-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | madnlp | droop5-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | madnlp | droop5-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | madnlp | droop6-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | madnlp | droop6-free | FAIL | solver status ITERATION_LIMIT; physical failures: power_balance, droop |
| 300 | 1.03 | madnlp | droop7-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | madnlp | droop7-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | madnlp | droop8-fixed | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | madnlp | droop8-free | FAIL | solver status LOCALLY_INFEASIBLE; physical failures: power_balance |
| 300 | 1.03 | madnlp | raw | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | madnlp | shunt1-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | madnlp | shunt16-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | madnlp | shunt2-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | madnlp | shunt32-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | madnlp | shunt4-free | PASS | passed all solver, policy and physical gates |
| 300 | 1.03 | madnlp | shunt8-free | PASS | passed all solver, policy and physical gates |

A failed nonlinear solve is path evidence, not an infeasibility certificate. The raw stage separates source-case difficulty; fixed-droop stages isolate adding controller equations; free-droop stages isolate parameter freedom; zero-droop shunt stages isolate shunt variables.
