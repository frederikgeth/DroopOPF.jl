# CCOpt frozen droop-only feasibility ladder

Taps and shunts are fixed to an admissible source design and exact PWL droop parameters are optimized. **Accepted** means a validated conditional witness and therefore a solution of the full joint problem. **Unknown** is not evidence of infeasibility.

| Target / fixed source | Status | Accepted | Does this establish a full-joint local witness? | Exact droop max |
|---|---|---:|---|---:|
| public118-load1.0-ccopt-anchor-droop-only-from-public118-baseline-design | LOCALLY_SOLVED | true | yes | 4.3117227871425357e-8 |
| public118-load1.0-ccopt-anchor-droop-only-from-public118-load1.0-ccopt-flat_high | LOCALLY_SOLVED | true | yes | 5.441994926941307e-6 |
| public118-load1.0-ccopt-anchor-droop-only-from-public118-load1.05-ccopt-anchor | ITERATION_LIMIT | false | no — unknown | 0.005780144015890165 |
| public118-load1.0-ccopt-flat_low-droop-only-from-public118-baseline-design | LOCALLY_SOLVED | true | yes | 4.3117227871425357e-8 |
| public118-load1.0-ccopt-flat_low-droop-only-from-public118-load1.0-ccopt-flat_high | LOCALLY_SOLVED | true | yes | 5.441994926941307e-6 |
| public118-load1.0-ccopt-flat_low-droop-only-from-public118-load1.05-ccopt-anchor | ITERATION_LIMIT | false | no — unknown | 0.005780144015890165 |
| public118-load1.05-ccopt-flat_low-droop-only-from-public118-baseline-design | LOCALLY_SOLVED | false | no — unknown | 0.00016799462613804536 |
| public118-load1.05-ccopt-flat_low-droop-only-from-public118-load1.0-ccopt-flat_high | ITERATION_LIMIT | false | no — unknown | 0.07213621485790961 |
| public118-load1.05-ccopt-flat_low-droop-only-from-public118-load1.05-ccopt-anchor | ITERATION_LIMIT | false | no — unknown | 0.010202797917747197 |
| public118-load1.05-ccopt-flat_high-droop-only-from-public118-baseline-design | LOCALLY_SOLVED | false | no — unknown | 0.00016799462613804536 |
| public118-load1.05-ccopt-flat_high-droop-only-from-public118-load1.0-ccopt-flat_high | ITERATION_LIMIT | false | no — unknown | 0.07213621485790961 |
| public118-load1.05-ccopt-flat_high-droop-only-from-public118-load1.05-ccopt-anchor | ITERATION_LIMIT | false | no — unknown | 0.010202797917747197 |
| public300-load1.0-ccopt-anchor-droop-only-from-public300-baseline-design | LOCALLY_SOLVED | true | yes | 2.7783658929081412e-8 |
| public300-load1.0-ccopt-flat_low-droop-only-from-public300-baseline-design | LOCALLY_SOLVED | true | yes | 2.7783658929081412e-8 |
| public300-load1.0-ccopt-flat_high-droop-only-from-public300-baseline-design | LOCALLY_SOLVED | true | yes | 2.7783658929081412e-8 |
| public300-load1.05-ccopt-anchor-droop-only-from-public300-baseline-design | ITERATION_LIMIT | false | no — unknown | 3.407936477940416 |
| public300-load1.05-ccopt-flat_low-droop-only-from-public300-baseline-design | ITERATION_LIMIT | false | no — unknown | 3.407936477940416 |
| public300-load1.05-ccopt-flat_high-droop-only-from-public300-baseline-design | ITERATION_LIMIT | false | no — unknown | 3.407936477940416 |
