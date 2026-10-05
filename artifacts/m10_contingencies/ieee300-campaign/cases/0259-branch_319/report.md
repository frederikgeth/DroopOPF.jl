# SCOPF report: pglib_opf_case300_ieee

- Valid: `false`; exact-curve feasible: `true`; encoded-model feasible: `true`
- Solver: Ipopt; termination: `ITERATION_LIMIT`; primal: `NEARLY_FEASIBLE_POINT`
- Mode: `preventive`; encoding: `smooth`
- Base dispatch objective: 101.63069005455563
- Tolerances (p.u., reference angle in radians): `(power_tolerance = 1.0e-6, droop_tolerance = 1.0e-5, limit_tolerance = 1.0e-6, unavailable_tolerance = 1.0e-8, coupling_tolerance = 1.0e-6)`

| Scenario | AC residual | Exact droop residual | Encoded droop residual | Smooth/exact gap | Branch margin | P-response violation | Equipment violation | Failures |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| base | 4.0362779785141356e-10 | 0.0 | 0.0 | 0.0 | -1.1274182143417022e-8 | 0.0 | 0.0 | none |
| branch_319 | 2.457472354500112e-7 | 0.0 | 0.0 | 0.0 | -6.948328312716967e-8 | 8.045612170555001e-8 | 0.0 | none |

Controls and network limits are checked independently in each scenario. Active-power response follows the declared policy; this report makes no dynamic or frequency-stability claim.
