# SCOPF report: m5-fixed-transformer

- Valid: `true`; exact-curve feasible: `true`; encoded-model feasible: `true`
- Solver: CCOpt; termination: `LOCALLY_SOLVED`; primal: `FEASIBLE_POINT`
- Mode: `preventive`; encoding: `complementarity`
- Base dispatch objective: 2.0713207578543225e-5
- Tolerances (p.u., reference angle in radians): `(power_tolerance = 1.0e-6, droop_tolerance = 1.0e-5, limit_tolerance = 1.0e-6, unavailable_tolerance = 1.0e-8, coupling_tolerance = 1.0e-6)`

| Scenario | AC residual | Exact droop residual | Encoded droop residual | Smooth/exact gap | Branch margin | Response violation | Failures |
|---|---:|---:|---:|---:|---:|---:|---|
| base | 7.074306418441978e-12 | 1.0534934386727257e-6 | 1.0534934386727257e-6 | 0.0 | 1.608089575732989 | 0.0 | none |
| transformer_out | 6.650235917504688e-14 | 1.61545700233523e-7 | 1.61545700233523e-7 | 0.0 | 1.6853606351542822 | 3.344763702117781e-17 | none |
| line_out | 1.6869838859179254e-13 | 2.089835404589513e-7 | 2.089835404589513e-7 | 0.0 | 1.3663145768926395 | 1.2576745200831851e-17 | none |
| generator_out | 2.142730437526552e-14 | 8.019721495222676e-8 | 8.019721495222676e-8 | 0.0 | 1.4960834900844704 | 0.0 | none |

Controls and network limits are checked independently in each scenario. Active-power response follows the declared policy; this report makes no dynamic or frequency-stability claim.