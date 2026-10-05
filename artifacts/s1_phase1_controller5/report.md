# IEEE-300 controller-5 Phase-I restoration

This is a diagnostic elastic model, not an OPF acceptance path. It separately
minimizes active/reactive balance, voltage, generator P/Q, thermal, and
smooth-droop slacks. Every returned state is also checked by the unchanged
independent validator.

| Model | Start source | Original status | Phase-I status | Classification | Total slack objective | Maximum slack | Voltage-slack sum | Strictly valid |
|---|---|---|---|---|---:|---:|---:|---:|
| controller_5_only | ipopt | LOCALLY_INFEASIBLE | LOCALLY_SOLVED | positive_slack_local_result | 0.023131547079469027 | 0.018138720102287283 | 0.02313133543533534 | false |
| controller_5_only | madnlp | ITERATION_LIMIT | LOCALLY_SOLVED | positive_slack_local_result | 0.023131547079513533 | 0.018138720102331907 | 0.023131335435379846 | false |
| cumulative_first_five | ipopt | LOCALLY_INFEASIBLE | LOCALLY_SOLVED | positive_slack_local_result | 0.023224670758030464 | 0.018231850506671286 | 0.02322445838694621 | false |
| cumulative_first_five | madnlp | LOCALLY_INFEASIBLE | LOCALLY_SOLVED | positive_slack_local_result | 0.023224670758030305 | 0.018231850506671057 | 0.02322445838694605 | false |
| controller_5_only | known_ipopt_six_witness | LOCALLY_SOLVED | LOCALLY_SOLVED | restored_zero_slack | 2.658180007939221e-7 | 1.8181900019621116e-10 | 5.4545290075776656e-8 | true |
| cumulative_first_five | known_ipopt_six_witness | LOCALLY_SOLVED | LOCALLY_SOLVED | restored_zero_slack | 2.6654527363867594e-7 | 1.818189678787808e-10 | 5.4545290077556536e-8 | true |

Both failed-solver basins converge to the same positive-slack local point for
each reduced model. Nearly all material slack is assigned to two voltage-limit
violations; balance, generator-limit, thermal, and droop slacks remain near
numerical noise. Starting the identical Phase-I model from the known
cumulative-six feasible witness reaches a zero-maximum-slack, independently
valid point. Therefore the positive result is a local basin diagnosis, not a
minimum-violation or infeasibility certificate.

## Location of the voltage slack

The retained Phase-I states identify the same two upper-voltage violations for
both source backends:

| Model | Bus | Voltage | Upper limit | Violation |
|---|---:|---:|---:|---:|
| controller-5-only | 7130 | 1.0781387200 | 1.06 | 0.0181387200 |
| controller-5-only | 119 | 1.0649925579 | 1.06 | 0.0049925579 |
| cumulative first five | 7130 | 1.0782318504 | 1.06 | 0.0182318504 |
| cumulative first five | 119 | 1.0649925504 | 1.06 | 0.0049925504 |

Bus 119 is the regulated bus of controller 5/generator 11. Bus 7130 is a
single-branch generator spur connected to bus 130 and hosts generator 62; it is
not controlled by any of the first six overlay droops. Its larger violation
shows that this failed basin is not confined to the bus-117/119 neighborhood.
Bus 117's large fixed capacitive shunt remains relevant to reactive-balance
behavior seen in the original failed iterates, but it is not the dominant
Phase-I voltage slack.
