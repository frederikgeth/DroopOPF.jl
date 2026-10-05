# IEEE-300 controller-count continuation

Each original fixed five-controller or controller-5-only model is solved from the same backend's strictly valid cumulative-six state. Only the initial state and removal of controller equalities differ from the frozen target; physical equations, limits, smoothing, strict gates, and one-reset budget are unchanged.

| Target model | Backend | Result | Final status | Attempts | Maximum balance residual | Maximum exact-droop residual |
|---|---|---|---|---:|---:|---:|
| controller_5_only | ipopt | PASS | LOCALLY_SOLVED | 1 | 1.2982470654065992e-9 | 1.9539925233402755e-14 |
| controller_5_only | madnlp | PASS | LOCALLY_SOLVED | 1 | 5.714961837099963e-11 | 3.730349362740526e-14 |
| cumulative_first_five | ipopt | PASS | LOCALLY_SOLVED | 1 | 2.537969834293108e-13 | 2.1316282072803006e-14 |
| cumulative_first_five | madnlp | PASS | LOCALLY_SOLVED | 1 | 2.2629609297553088e-10 | 3.375077994860476e-14 |

A pass demonstrates a reliable path from a stricter feasible model to the relaxed target for that backend. It does not replace the frozen direct-start outcome; both are retained.
