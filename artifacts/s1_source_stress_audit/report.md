# Raw PGLib +5% stress audit

The original imported cases are tested without the S1 overlay. Both active and reactive loads are multiplied by `1.05`; source generator limits, fixed shunts and fixed transformer ratios are unchanged. The solver starts from the validated nominal raw-source solution and receives the same one-reset policy used by the frozen matrix.

| Network | Solver | Status | Strict valid |
|---:|---|---|---:|
| 118 | ipopt | LOCALLY_SOLVED | true |
| 118 | madnlp | LOCALLY_SOLVED | true |
| 300 | ipopt | LOCALLY_INFEASIBLE | false |
| 300 | madnlp | LOCALLY_INFEASIBLE | false |

A valid result is a local witness for the raw stressed DroopOPF import. An invalid result is solver/path evidence only and does not establish raw-case infeasibility.
