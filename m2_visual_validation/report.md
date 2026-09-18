# SCOPF report: m2-three-bus

- Valid: `true`; exact-curve feasible: `true`; encoded-model feasible: `true`
- Solver: Ipopt; termination: `LOCALLY_SOLVED`; primal: `FEASIBLE_POINT`
- Mode: `preventive`; encoding: `smooth`
- Base dispatch objective: 1.676309943232809e-5
- Tolerances (p.u., reference angle in radians): `(power_tolerance = 1.0e-6, droop_tolerance = 1.0e-5, limit_tolerance = 1.0e-6, unavailable_tolerance = 1.0e-8, coupling_tolerance = 1.0e-6)`

| Scenario | AC residual | Exact droop residual | Encoded droop residual | Smooth/exact gap | Branch margin | Response violation | Failures |
|---|---:|---:|---:|---:|---:|---:|---|
| base | 3.372302437298913e-15 | 1.1657341758564144e-15 | 1.0547118733938987e-15 | 1.1102230246251565e-16 | 1.6860943472078247 | 0.0 | none |
| line_22 | 3.649858193455202e-15 | 3.608224830031759e-16 | 3.885780586188048e-16 | 1.1102230246251565e-16 | 1.36614721422354 | 4.185020385794047e-17 | none |
| generator_9 | 3.191891195797325e-15 | 4.163336342344337e-16 | 3.0531133177191805e-16 | 1.1102230246251565e-16 | 1.5811462167527892 | 0.0 | none |

Controls and network limits are checked independently in each scenario. Active-power response follows the declared policy; this report makes no dynamic or frequency-stability claim.
