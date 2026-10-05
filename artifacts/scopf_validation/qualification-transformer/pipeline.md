# Contingency pipeline: parallel-transformer

- Routing complete: `true`
- Coverage complete: `true`
- Routes consistent: `true`
- Full AC coverage: `true`
- All outcomes accepted: `true`
- Screening audit passed: `true`
- Evaluation errors: `0`

| Rank | ID | Device | Route | Outcome | Classification | Margin | Discarded load | Source |
|---:|---|---|---|---|---|---:|---:|---|
| 1 | branch_1 | line | exact | exact_evaluated | accepted | 0.08377768105084482 | 0.0 | exact_ac |
| 2 | branch_2 | transformer | exact | exact_evaluated | accepted | 0.08886216048691353 | 0.0 | exact_ac |
| 3 | generator_1 | generator | exact | exact_evaluated | accepted | 0.09196398810549056 | 0.0 | exact_ac |
| 4 | generator_2 | generator | exact | exact_evaluated | accepted | 0.09196398810549056 | 0.0 | exact_ac |

A screened-not-evaluated entry is a workload decision, not an AC-security certificate.

Connected outages use fixed-base preventive participation. Island-aware outcomes validate only the retained component, with independent OPF redispatch; discarded components are not balanced. Full AC coverage means each route was evaluated, not every island was validated. Discarded load is excluded demand, not a claim that its local service is physically impossible. Dynamic security is outside scope.