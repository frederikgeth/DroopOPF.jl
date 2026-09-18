# SCOPF report: m5-fixed-transformer

- Valid: `false`; exact-curve feasible: `false`; encoded-model feasible: `false`
- Solver: CCOpt; termination: `SLOW_PROGRESS`; primal: `UNKNOWN_RESULT_STATUS`
- Mode: `preventive`; encoding: `complementarity`
- Base dispatch objective: 2.069266101292766e-5
- Tolerances (p.u., reference angle in radians): `(power_tolerance = 1.0e-6, droop_tolerance = 1.0e-5, limit_tolerance = 1.0e-6, unavailable_tolerance = 1.0e-8, coupling_tolerance = 1.0e-6)`

| Scenario | AC residual | Exact droop residual | Encoded droop residual | Smooth/exact gap | Branch margin | Response violation | Failures |
|---|---:|---:|---:|---:|---:|---:|---|
| base | 5.113964807179627e-15 | 0.0003548715881198858 | 0.0003548715881198858 | 0.0 | 1.6080774895459888 | 0.0 | droop |
| transformer_out | 1.8596235662471372e-15 | 3.5520424874826984e-5 | 3.5520424874826984e-5 | 0.0 | 1.6853602224385182 | 6.033585089881832e-17 | droop |
| line_out | 2.400857290751901e-15 | 4.5933467971853714e-5 | 4.5933467971853714e-5 | 0.0 | 1.3663146470165113 | 3.707971429900425e-17 | droop |
| generator_out | 4.829470157119431e-15 | 1.763982987795787e-5 | 1.763982987795787e-5 | 0.0 | 1.4960833558321363 | 0.0 | droop |

Controls and network limits are checked independently in each scenario. Active-power response follows the declared policy; this report makes no dynamic or frequency-stability claim.