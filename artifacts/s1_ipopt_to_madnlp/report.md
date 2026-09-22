# S1 cross-solver physical warm start

This experiment starts MadNLP from every independently validated Ipopt solution
in the frozen explicit-formulation matrix. Each transfer includes the AC state
and the optimized tap, shunt and droop settings. It deliberately excludes Ipopt
multipliers: those are solver-specific and are not a safe cross-backend initial
condition. The target uses the unchanged one-reset policy, 2,000 total-iteration
budget, smoothing, objective and independent physical validator.

| Case | Ipopt objective | Direct MadNLP | MadNLP from Ipopt | Warm-start objective | Result change |
|---|---:|---|---|---:|---|
| IEEE 118, 1.00, anchor | 7.594008 | invalid | invalid (`SLOW_PROGRESS`) | — | unchanged |
| IEEE 118, 1.00, flat-low | 7.594017 | invalid | valid | 8.208292 | gained |
| IEEE 118, 1.00, flat-high | 7.593235 | invalid | valid | 8.187539 | gained |
| IEEE 118, 1.05, anchor | 11.387428 | invalid | valid after reset | 12.107705 | gained |
| IEEE 300, 1.00, anchor | 89.226044 | valid, 96.329781 | invalid (`SLOW_PROGRESS`) | — | lost |
| IEEE 300, 1.05, anchor | 140.953331 | valid, 149.055741 | valid | 148.705047 | retained; lower MadNLP objective |
| IEEE 300, 1.05, flat-low | 140.954185 | valid, 148.855557 | invalid (`ITERATION_LIMIT`) | — | lost |
| IEEE 300, 1.05, flat-high | 140.954185 | invalid | valid | 148.709739 | gained |

MadNLP therefore accepts 5/8 warm-started cases, compared with 3/8 direct
MadNLP solves on the same Ipopt-accepted subset. It gains four cases and loses
two, with one retained case. The transfer improves solver coverage but does not
recover the Ipopt local objective: all five valid MadNLP outcomes remain higher
than their Ipopt source objectives.

For the nominal IEEE 118 anchor and nominal IEEE 300 anchor, the final points
have small physical residuals but MadNLP returns `SLOW_PROGRESS`; they remain
invalid under the existing native-plus-physical acceptance rule. This separates
physical feasibility from solver convergence and shows that a physical primal
warm start alone is not enough to reproduce an Ipopt local solution in MadNLP.

Machine-readable per-attempt results are in `comparison.json`, `summary.json`
and the individual policy records in this directory.
