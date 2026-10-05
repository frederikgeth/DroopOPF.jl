# SCOPF report: pglib_opf_case118_ieee

- Valid: `false`; exact-curve feasible: `false`; encoded-model feasible: `false`
- Solver: Ipopt; termination: `LOCALLY_INFEASIBLE`; primal: `INFEASIBLE_POINT`
- Mode: `preventive`; encoding: `smooth`
- Base dispatch objective: 7.621127020827637
- Tolerances (p.u., reference angle in radians): `(power_tolerance = 1.0e-6, droop_tolerance = 1.0e-5, limit_tolerance = 1.0e-6, unavailable_tolerance = 1.0e-8, coupling_tolerance = 1.0e-6)`

| Scenario | AC residual | Exact droop residual | Encoded droop residual | Smooth/exact gap | Branch margin | P-response violation | Equipment violation | Failures |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| base | 3.624897326748311e-9 | 0.0 | 0.0 | 0.0 | 0.10810742808627549 | 0.0 | 0.0 | none |
| branch_70 | 0.018159973851821665 | 0.0 | 0.0 | 0.0 | 0.09802356383068012 | 1.1490165590866772e-11 | 0.0 | power_balance |

Controls and network limits are checked independently in each scenario. Active-power response follows the declared policy; this report makes no dynamic or frequency-stability claim.
