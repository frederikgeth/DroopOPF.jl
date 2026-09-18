# SCOPF report: m5-fixed-transformer

- Valid: `true`; exact-curve feasible: `true`; encoded-model feasible: `true`
- Solver: MadNLP; termination: `LOCALLY_SOLVED`; primal: `FEASIBLE_POINT`
- Mode: `preventive`; encoding: `smooth`
- Base dispatch objective: 2.0713265779478056e-5
- Tolerances (p.u., reference angle in radians): `(power_tolerance = 1.0e-6, droop_tolerance = 1.0e-5, limit_tolerance = 1.0e-6, unavailable_tolerance = 1.0e-8, coupling_tolerance = 1.0e-6)`

| Scenario | AC residual | Exact droop residual | Encoded droop residual | Smooth/exact gap | Branch margin | Response violation | Failures |
|---|---:|---:|---:|---:|---:|---:|---|
| base | 1.5237811012980274e-14 | 7.216449660063518e-16 | 7.216449660063518e-16 | 1.1102230246251565e-16 | 1.608089610270549 | 0.0 | none |
| transformer_out | 4.4603210014315664e-14 | 6.938893903907228e-16 | 5.828670879282072e-16 | 1.1102230246251565e-16 | 1.6853606368259106 | 3.577867169202165e-18 | none |
| line_out | 2.4369395390522186e-14 | 1.5265566588595902e-16 | 2.636779683484747e-16 | 1.1102230246251565e-16 | 1.3663145765720843 | 5.5294310796760726e-17 | none |
| generator_out | 1.915134717478395e-15 | 9.159339953157541e-16 | 8.049116928532385e-16 | 1.1102230246251565e-16 | 1.4960834906976035 | 0.0 | none |

Controls and network limits are checked independently in each scenario. Active-power response follows the declared policy; this report makes no dynamic or frequency-stability claim.