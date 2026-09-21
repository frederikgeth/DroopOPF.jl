# Scaling decision after the first connected experiment

**S1 remains open.** Do not yet claim scalable, reliably converged joint optimization. AVR (M8/M9.3) and complex-bank optimization remain deferred.

The revised experiment uses epsilon=1e-6, zero bound relaxation, Ipopt adaptive barrier updates and solved heterogeneous fixed-case starts. It changes numerical settings only; objectives, bounds and physical acceptance tolerances are preserved. This combined variant does not isolate which change caused improvement. Baseline attempts are retained in ../scaling_initial.

| Buses | Droops / taps / banks | Joint solver status | Physical and policy valid | Solve seconds |
|---|---|---|---|---:|
| 3 | 2 / 1 / 2 | LOCALLY_SOLVED | True / True | 0.016641583293676376 |
| 12 | 8 / 4 / 8 | ITERATION_LIMIT | True / True | 1.5991900004446507 |
| 48 | 32 / 16 / 32 | ALMOST_LOCALLY_SOLVED | True / True | 3.5678286645561457 |
| 96 | 64 / 32 / 64 | ITERATION_LIMIT | True / True | 7.759050289168954 |

The 12- and 96-bus joint runs hit the iteration limit despite physically feasible points. The 48-bus result is ALMOST_LOCALLY_SOLVED, not a global-optimality certificate. Model construction is small relative to joint solver time at the larger sizes in this experiment. The first measured small-case build may still include instrumentation compilation; do not use it for a scaling slope. Peak RSS is a shared-process lifetime measurement.

Next: diagnose optimality/convergence, numerical scaling and weakly identified simultaneous droop parameters; compare matched starts and solver configurations before changing formulations. Then add pinned public medium cases, diverse load stress and contingency scaling. Keep exact physical validation tolerances unchanged. Continuous bank feasibility does not establish legal switching positions.
