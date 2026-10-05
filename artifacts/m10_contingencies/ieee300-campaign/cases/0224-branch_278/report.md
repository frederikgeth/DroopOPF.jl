# SCOPF report: pglib_opf_case300_ieee

- Valid: `true`; exact-curve feasible: `true`; encoded-model feasible: `true`
- Solver: Ipopt; termination: `LOCALLY_SOLVED`; primal: `FEASIBLE_POINT`
- Mode: `preventive`; encoding: `smooth`
- Base dispatch objective: 101.63069005455563
- Tolerances (p.u., reference angle in radians): `(power_tolerance = 1.0e-6, droop_tolerance = 1.0e-5, limit_tolerance = 1.0e-6, unavailable_tolerance = 1.0e-8, coupling_tolerance = 1.0e-6)`

| Scenario | AC residual | Exact droop residual | Encoded droop residual | Smooth/exact gap | Branch margin | P-response violation | Equipment violation | Failures |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| base | 4.0362779785141356e-10 | 0.0 | 0.0 | 0.0 | -1.1274182143417022e-8 | 0.0 | 0.0 | none |
| branch_278 | 3.606281939738665e-11 | 0.0 | 0.0 | 0.0 | 3.725836872359167e-8 | 7.380013887015319e-9 | 0.0 | none |

Controls and network limits are checked independently in each scenario. Active-power response follows the declared policy; this report makes no dynamic or frequency-stability claim.
