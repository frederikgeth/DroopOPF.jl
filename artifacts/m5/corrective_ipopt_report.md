# SCOPF report: m5-fixed-transformer

- Valid: `true`; exact-curve feasible: `true`; encoded-model feasible: `true`
- Solver: Ipopt; termination: `LOCALLY_SOLVED`; primal: `FEASIBLE_POINT`
- Mode: `corrective`; encoding: `smooth`
- Base dispatch objective: 2.0713265779478334e-5
- Tolerances (p.u., reference angle in radians): `(power_tolerance = 1.0e-6, droop_tolerance = 1.0e-5, limit_tolerance = 1.0e-6, unavailable_tolerance = 1.0e-8, coupling_tolerance = 1.0e-6)`

| Scenario | AC residual | Exact droop residual | Encoded droop residual | Smooth/exact gap | Branch margin | Response violation | Failures |
|---|---:|---:|---:|---:|---:|---:|---|
| base | 5.9396931817445875e-15 | 8.014422459012849e-16 | 8.014422459012849e-16 | 1.1102230246251565e-16 | 1.6080896102008542 | 0.0 | none |
| transformer_out | 2.004146848477717e-12 | 8.604228440844963e-16 | 7.494005416219807e-16 | 1.1102230246251565e-16 | 1.68252923834164 | 0.0 | none |
| line_out | 7.909298216368654e-12 | 5.828670879282072e-16 | 6.938893903907228e-16 | 1.1102230246251565e-16 | 1.3663174223811034 | 0.0 | none |
| generator_out | 2.914335439641036e-15 | 3.885780586188048e-16 | 4.996003610813204e-16 | 1.1102230246251565e-16 | 1.496083490697604 | 0.0 | none |

Controls and network limits are checked independently in each scenario. Active-power response follows the declared policy; this report makes no dynamic or frequency-stability claim.