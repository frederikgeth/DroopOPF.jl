# Raw PGLib load continuation

Untouched PGLib IEEE-300 case: no droop overlay, synthetic bank, or adjustable transformer ratio. An accepted factor warm-starts only the next factor. A failed factor terminates that solver's path, so this is a conservative verified path rather than a loadability limit.

| Solver | Load multiplier | Status | Strict valid |
|---|---:|---|---:|
| ipopt | 1.0 | LOCALLY_SOLVED | true |
| ipopt | 1.01 | LOCALLY_SOLVED | true |
| ipopt | 1.02 | LOCALLY_SOLVED | true |
| ipopt | 1.03 | LOCALLY_SOLVED | true |
| ipopt | 1.04 | LOCALLY_SOLVED | true |
| ipopt | 1.05 | LOCALLY_INFEASIBLE | false |
| madnlp | 1.0 | LOCALLY_SOLVED | true |
| madnlp | 1.01 | LOCALLY_SOLVED | true |
| madnlp | 1.02 | LOCALLY_SOLVED | true |
| madnlp | 1.03 | LOCALLY_SOLVED | true |
| madnlp | 1.04 | LOCALLY_SOLVED | true |
| madnlp | 1.05 | LOCALLY_INFEASIBLE | false |
