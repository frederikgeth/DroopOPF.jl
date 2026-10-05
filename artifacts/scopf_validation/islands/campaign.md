# Contingency pipeline: loaded-islands

- Routing complete: `true`
- Coverage complete: `true`
- Routes consistent: `true`
- Full AC coverage: `true`
- All outcomes accepted: `false`
- Screening audit passed: `true`
- Evaluation errors: `0`

| Rank | ID | Device | Route | Outcome | Classification | Margin | Discarded load | Source |
|---:|---|---|---|---|---|---:|---:|---|
| 1 | branch_30 | line | island_aware | island_evaluated | island_load_loss | 0.0006234681931621688 | 0.12 | island_aware_ac |
| 2 | branch_40 | line | island_aware | island_evaluated | island_load_loss | 0.0006664893276659978 | 0.12 | island_aware_ac |
| 3 | branch_20 | line | island_aware | island_evaluated | island_load_loss | 0.0006618111642389124 | 0.03 | island_aware_ac |
| 4 | branch_10 | transformer | island_aware | island_evaluated | island_load_loss | 0.0011599393477372821 | 0.03 | island_aware_ac |
| 5 | generator_2 | generator | exact | exact_evaluated | accepted | 0.07496556948267316 | 0.0 | exact_ac |
| 6 | generator_1 | generator | exact | exact_evaluated | accepted | 0.07497201361659102 | 0.0 | exact_ac |
| 7 | generator_3 | generator | exact | exact_evaluated | accepted | 0.07515979770316226 | 0.0 | exact_ac |

A screened-not-evaluated entry is a workload decision, not an AC-security certificate.

Connected outages use fixed-base preventive participation. Island-aware outcomes validate only the retained component, with independent OPF redispatch; discarded components are not balanced. Full AC coverage means each route was evaluated, not every island was validated. Discarded load is excluded demand, not a claim that its local service is physically impossible. Dynamic security is outside scope.

Fingerprint: `26a11567c916c0b8f68a95de7be4101a40251e4d466715c25c501c1f9b22395d`. Reused 7 checkpoints; executed 0 routes. Full input contract: campaign-inputs.json.
