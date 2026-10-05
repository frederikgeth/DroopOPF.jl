# Contingency pipeline: parallel-reactive

- Routing complete: `true`
- Coverage complete: `true`
- Routes consistent: `true`
- Full AC coverage: `true`
- All outcomes accepted: `false`
- Screening audit passed: `true`
- Evaluation errors: `0`

| Rank | ID | Device | Route | Outcome | Classification | Margin | Discarded load | Source |
|---:|---|---|---|---|---|---:|---:|---|
| 1 | generator_1 | generator | exact | exact_evaluated | invalid | -1.0830652596993673e-8 | 0.0 | exact_ac |
| 2 | generator_2 | generator | exact | exact_evaluated | invalid | -1.0830652596993673e-8 | 0.0 | exact_ac |
| 3 | branch_1 | line | exact | exact_evaluated | accepted | 0.03586575186579949 | 0.0 | exact_ac |
| 4 | branch_2 | transformer | exact | exact_evaluated | accepted | 0.03586575186579949 | 0.0 | exact_ac |

A screened-not-evaluated entry is a workload decision, not an AC-security certificate.

Connected outages use fixed-base preventive participation. Island-aware outcomes validate only the retained component, with independent OPF redispatch; discarded components are not balanced. Full AC coverage means each route was evaluated, not every island was validated. Discarded load is excluded demand, not a claim that its local service is physically impossible. Dynamic security is outside scope.