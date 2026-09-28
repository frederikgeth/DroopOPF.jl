# Witness-seed exact-droop tolerance re-score

This is a read-only re-score of the retained full-decision witness-seed matrix. Only exact-droop tolerance changes from `1e-5` to `0.01` pu; solver, policy, balance, voltage, generator-limit, and thermal gates remain mandatory. No solver run or frozen artifact is modified.

| Direct cell | Solver | Strict witness-seed | Relaxed witness-seed | Final status | Raw exact-droop mismatch |
|---|---|---:|---:|---|---:|
| public118-load1.0-madnlp-anchor | madnlp | false | false | SLOW_PROGRESS | 1.8096635301390052e-14 |
| public118-load1.0-madnlp-flat_high | madnlp | false | false | SLOW_PROGRESS | 1.8096635301390052e-14 |
| public118-load1.0-madnlp-flat_low | madnlp | false | false | SLOW_PROGRESS | 1.8096635301390052e-14 |
| public118-load1.05-ipopt-flat_high | ipopt | false | true | LOCALLY_SOLVED | 1.1220379539905734e-5 |
| public118-load1.05-ipopt-flat_low | ipopt | false | true | LOCALLY_SOLVED | 1.1220379539905734e-5 |
| public118-load1.05-madnlp-anchor | madnlp | true | true | LOCALLY_SOLVED | 2.5329082807834524e-6 |
| public118-load1.05-madnlp-flat_high | madnlp | true | true | LOCALLY_SOLVED | 2.5329082807834524e-6 |
| public300-load1.0-ipopt-flat_high | ipopt | true | true | ALMOST_LOCALLY_SOLVED | 1.6229522836752608e-8 |
| public300-load1.0-ipopt-flat_low | ipopt | true | true | ALMOST_LOCALLY_SOLVED | 1.6229522836752608e-8 |
| public300-load1.0-madnlp-flat_high | madnlp | true | true | LOCALLY_SOLVED | 2.930988785010413e-14 |
| public300-load1.0-madnlp-flat_low | madnlp | true | true | LOCALLY_SOLVED | 2.930988785010413e-14 |
| public300-load1.05-madnlp-flat_high | madnlp | true | true | LOCALLY_SOLVED | 4.4614590011260447e-7 |

Strict passes: **7/12**. Relaxed passes: **9/12**.
