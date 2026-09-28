# S1 three-solver direct-start scorecard

All lanes cover the same 12 public cells: IEEE 118/300, nominal/+5% demand, and anchor/flat-low/flat-high starts. Ipopt and MadNLP use the frozen smooth explicit-droop model with their one-reset policy. CCOpt uses the exact-complementarity model and a native one-solve budget; it is retained as a third solver family, not pooled as a like-for-like smooth-solver result.

| Solver | Formulation | Budget | Strict `1e-5` passes | Relaxed `1e-2` passes |
|---|---|---|---:|---:|
| Ipopt | smooth explicit droop | one reset; 2000 iterations / 120 s | 8/12 | 8/12 |
| MadNLP | smooth explicit droop | one reset; 2000 iterations / 120 s | 4/12 | 5/12 |
| CCOpt | exact complementarity | native direct; 1000 iterations / 60 s | 2/12 | 2/12 |

The `1e-2` column changes only exact-droop acceptance. Solver status, policy, AC balance, voltage, generator, and thermal gates remain mandatory. CCOpt does not gain a pass because every rejected CCOpt cell also fails solver or power-balance gates.
