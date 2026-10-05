# S1 matched direct-versus-continuation diagnostic

One formerly invalid frozen cell is replayed from the same flat-low start both directly at epsilon=1e-6 and through the fixed continuation schedule. Diagnostics are attached only to those two endpoint result points; intermediate stages are retained as solve evidence.

| Role | Status | Strict valid |
|---|---|---:|
| direct epsilon=1e-6 | ITERATION_LIMIT | false |
| continuation epsilon=0.01 | SLOW_PROGRESS | false |
| continuation epsilon=0.001 | LOCALLY_SOLVED | false |
| continuation epsilon=0.0001 | SLOW_PROGRESS | false |
| continuation epsilon=1.0e-5 | LOCALLY_SOLVED | false |
| continuation epsilon=1.0e-6 | LOCALLY_SOLVED | true |
| archived accepted continuation state, epsilon=1e-6 | SLOW_PROGRESS | false |

The raw NLPDiagnostics reports retain structural row and variable evidence. Interpret differences only alongside the independent exact-droop and AC-physical validation in `summary.json`.
