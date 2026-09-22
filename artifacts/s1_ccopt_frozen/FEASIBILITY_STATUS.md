# Frozen S1 case-level feasibility status

The three starts for a given bus count and load factor are different
initializations of the **same** physical optimization problem. A validated
solution from any start, or from the droop-only restricted problem, establishes
a local feasible witness for that shared case. It does not establish global
feasibility or global optimality.

| Physical case | Direct frozen witness | Droop-only witness with fixed admissible taps/shunts | Case-level status |
|---|---|---|---|
| IEEE 118, nominal load | flat-high | anchor and flat-low | **Yes — validated local witness** |
| IEEE 118, +5% load | anchor | none additional; flat starts remain unvalidated | **Yes — validated local witness** |
| IEEE 300, nominal load | none | anchor, flat-low, and flat-high | **Yes — validated local witness** |
| IEEE 300, +5% load | none | none | **Unknown** |

For IEEE 118 +5%, the two failed flat-start runs and droop-only retries do not
contradict the accepted anchor solution; they demonstrate initialization and
termination sensitivity. For IEEE 300 +5%, all retained direct and
anchor-fixed-tap/shunt droop-only attempts reached the iteration limit, so this
remains an algorithmic unknown rather than evidence of infeasibility.

The validated IEEE 300 nominal droop-only witness also fails to continue at the
first 1% step (load factor 1.01): `ITERATION_LIMIT` with a direct exact-droop
residual of `2.368e-1` pu. This rejects that continuation path, not the
existence of a 1.01 or 1.05 solution.

Evidence: [frozen report](report.md) and
[droop-only feasibility ladder](../s1_ccopt_droop_feasibility/report.md).
The continuation record is [here](../s1_ccopt_300_continuation/report.md).
