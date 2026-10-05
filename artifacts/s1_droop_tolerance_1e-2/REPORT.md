# Frozen S1 exact-droop tolerance sensitivity

This is a read-only re-score of the retained frozen results. It does not rerun
the solvers, modify the frozen `1e-5` acceptance decision, or change any
equipment equation. The hypothetical decision changes only the independent
exact-droop tolerance from `1e-5` pu to `1e-2` pu. Solver convergence, policy,
power-balance, voltage, thermal, and generator-limit gates remain unchanged.

The raw maximum exact-droop mismatch is retained even when it is below the
hypothetical tolerance.

| Solver | Frozen accepted (`1e-5`) | Hypothetical accepted (`1e-2`) | Change |
|---|---:|---:|---:|
| Ipopt | 8/12 | 8/12 | 0 |
| MadNLP | 4/12 | 5/12 | +1 |
| CCOpt | 2/12 | 2/12 | 0 |
| **Total** | **14/36** | **15/36** | **+1** |

## Decision-changing case

| Case | Solver status | Other gates | Raw exact-droop mismatch | Frozen `1e-5` | Hypothetical `1e-2` |
|---|---|---|---:|---:|---:|
| `public300-load1.0-madnlp-flat_high` | `LOCALLY_SOLVED` | solver and policy pass; droop is the only physical failure | `3.203462609908253e-5` pu | fail | pass |

## Why the other failures remain failures

- Ipopt's four rejected cells terminate at the iteration limit and also have
  power-balance failures. Relaxing only exact droop does not change them.
- All ten rejected CCOpt cells have exact-droop mismatches above `1e-2` pu and
  also fail solver convergence and power balance. The two closest are the
  stressed IEEE-118 flat starts at `0.0105315432` and `0.0113163673` pu.
- MadNLP has several physically acceptable iterates that remain rejected by
  their native termination status. A physical-tolerance change must not be
  used to override the solver gate.

## Interpretation

The looser threshold changes only one decision and therefore does not address
the dominant frozen-test failure mode, which is numerical termination (often
with power-balance error), not a marginal exact-droop mismatch. Also, `1e-2`
pu is 1000 times the frozen criterion; on a 100 MVA base it permits a 1 Mvar
controller mismatch. It is best reported as a sensitivity result rather than
used to replace the engineering acceptance criterion.
