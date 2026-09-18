# SCOPF report: m5-fixed-transformer

- Valid: `true`; exact-curve feasible: `true`; encoded-model feasible: `true`
- Solver: Ipopt; termination: `LOCALLY_SOLVED`; primal: `FEASIBLE_POINT`
- Mode: `preventive`; encoding: `smooth`
- Base dispatch objective: 2.0713265779449498e-5
- Tolerances (p.u., reference angle in radians): `(power_tolerance = 1.0e-6, droop_tolerance = 1.0e-5, limit_tolerance = 1.0e-6, unavailable_tolerance = 1.0e-8, coupling_tolerance = 1.0e-6)`

| Scenario | AC residual | Exact droop residual | Encoded droop residual | Smooth/exact gap | Branch margin | Response violation | Failures |
|---|---:|---:|---:|---:|---:|---:|---|
| base | 1.7569279364693102e-14 | 8.326672684688674e-16 | 7.216449660063518e-16 | 1.1102230246251565e-16 | 1.6080896102705526 | 0.0 | none |
| transformer_out | 4.526934382909076e-14 | 5.134781488891349e-16 | 6.245004513516506e-16 | 1.1102230246251565e-16 | 1.6853606368259184 | 2.585822181377928e-17 | none |
| line_out | 2.5104918144336352e-14 | 7.632783294297951e-16 | 6.522560269672795e-16 | 1.1102230246251565e-16 | 1.3663145765720834 | 7.15573433840433e-18 | none |
| generator_out | 4.9682480351975755e-15 | 3.885780586188048e-16 | 4.996003610813204e-16 | 1.1102230246251565e-16 | 1.4960834906976046 | 0.0 | none |

Controls and network limits are checked independently in each scenario. Active-power response follows the declared policy; this report makes no dynamic or frequency-stability claim.