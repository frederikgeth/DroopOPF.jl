# SCOPF report: m2-three-bus

- Valid: `true`; exact-curve feasible: `true`; encoded-model feasible: `true`
- Solver: Ipopt; termination: `LOCALLY_SOLVED`; primal: `FEASIBLE_POINT`
- Mode: `preventive`; encoding: `smooth`
- Base dispatch objective: 1.676309943232809e-5
- Tolerances (p.u., reference angle in radians): `(power_tolerance = 1.0e-6, droop_tolerance = 1.0e-5, limit_tolerance = 1.0e-6, unavailable_tolerance = 1.0e-8, coupling_tolerance = 1.0e-6)`

| Scenario | AC residual | Exact droop residual | Encoded droop residual | Smooth/exact gap | Branch margin | P-response violation | Equipment violation | Failures |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| base | 2.6645352591003757e-15 | 1.1657341758564144e-15 | 1.0547118733938987e-15 | 1.1102230246251565e-16 | 1.6860943472078245 | 0.0 | 0.0 | none |
| line_22 | 4.107825191113079e-15 | 3.608224830031759e-16 | 3.885780586188048e-16 | 1.1102230246251565e-16 | 1.36614721422354 | 4.185020385794047e-17 | 0.0 | none |
| generator_9 | 2.6922908347160046e-15 | 4.163336342344337e-16 | 3.0531133177191805e-16 | 1.1102230246251565e-16 | 1.581146216752789 | 0.0 | 0.0 | none |

Controls and network limits are checked independently in each scenario. Active-power response follows the declared policy; this report makes no dynamic or frequency-stability claim.
