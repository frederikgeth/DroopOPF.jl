# S1 NLPDiagnostics point-local pilot

Four direct epsilon-1e-6 reruns are analyzed read-only at their returned solver result. Findings are point-local numerical/structural evidence and never override the independent solver, policy, AC-physical, or exact-droop acceptance gates.

| Pilot | Status | Strict valid | Findings | Diagnostic error |
|---|---|---:|---:|---|
| `ipopt-gain` | ITERATION_LIMIT | false | 1689 | — |
| `ipopt-loss` | ITERATION_LIMIT | false | 1019 | — |
| `madnlp-gain` | SLOW_PROGRESS | false | 86 | — |
| `madnlp-loss` | LOCALLY_SOLVED | true | 903 | — |

Per-case Markdown and JSON files retain every diagnostic finding, its evidence basis, confidence, affected rows/variables, and suggested action.

## Solver-result-only comparison

| Pilot | Active-set LICQ | Row-scale spread | MFCQ witness |
|---|---|---|---|
| `ipopt-gain` | rank 621 / 634 selected rows | 1.69e7 | yes; 25 active inequalities |
| `ipopt-loss` | rank 575 / 587 selected rows | 1.58e7 | yes; 24 active inequalities |
| `madnlp-gain` | rank 309 / 345 selected rows | not emitted | yes; 71 active inequalities |
| `madnlp-loss` | rank 648 / 661 selected rows | 1.45e7 | yes; 25 active inequalities |

All four result points have active-set LICQ/MFCQ warnings, including the accepted `madnlp-loss` point. This is evidence of pervasive active-set geometry and scaling sensitivity, **not yet proof** that a particular droop or Q-limit row is causal. The next diagnostic should attach semantic row names and compare matching failed-direct and accepted-continuation states.
