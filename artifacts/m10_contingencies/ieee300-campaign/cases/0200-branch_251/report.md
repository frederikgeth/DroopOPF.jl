# SCOPF report: pglib_opf_case300_ieee

- Valid: `false`; exact-curve feasible: `false`; encoded-model feasible: `false`
- Solver: Ipopt; termination: `LOCALLY_INFEASIBLE`; primal: `INFEASIBLE_POINT`
- Mode: `preventive`; encoding: `smooth`
- Base dispatch objective: 101.63069005455563
- Tolerances (p.u., reference angle in radians): `(power_tolerance = 1.0e-6, droop_tolerance = 1.0e-5, limit_tolerance = 1.0e-6, unavailable_tolerance = 1.0e-8, coupling_tolerance = 1.0e-6)`

| Scenario | AC residual | Exact droop residual | Encoded droop residual | Smooth/exact gap | Branch margin | P-response violation | Equipment violation | Failures |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| base | 4.0362779785141356e-10 | 0.0 | 0.0 | 0.0 | -1.1274182143417022e-8 | 0.0 | 0.0 | none |
| branch_251 | 0.03256546473594568 | 0.0 | 0.0 | 0.0 | -0.016427749110898726 | 3.2178512740394502e-12 | 0.0 | power_balance, branch_thermal |

Controls and network limits are checked independently in each scenario. Active-power response follows the declared policy; this report makes no dynamic or frequency-stability claim.
