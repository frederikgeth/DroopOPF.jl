# M10 IEEE contingency analysis

- Full eligible catalog complete: true.
- Candidates: 480; eligible and evaluated: 391; structurally excluded: 89.
- Classifications: Dict("accepted" => 9, "invalid" => 381, "physical_only" => 1).
- Solver statuses: Dict("LOCALLY_INFEASIBLE" => 380, "ITERATION_LIMIT" => 2, "LOCALLY_SOLVED" => 7, "ALMOST_LOCALLY_SOLVED" => 2).
- Validation failures: Dict("branch_thermal" => 249, "active_power_response" => 15, "power_balance" => 376).
- Evaluation time: 732.096 s total; 1.353 s median; 3.451 s p95; 35.782 s maximum.

All eligible outages were evaluated before ranking. Excluded islanding outages are unsupported, not safe. Invalid and solver-limited outcomes are unresolved, not filtered failures.

Normalized violation is the largest independent residual-to-tolerance ratio across AC balance, availability, coupling, and operating-limit checks. It orders diagnostic attention; it is not a physical stability index.

## Unresolved outcomes

| Rank | Contingency | Device | Normalized violation |
|---:|---|---|---:|
| 1 | generator_11 | generator | 1.4798085627396028e7 |
| 2 | generator_28 | generator | 1.2838007587614037e7 |
| 3 | branch_205 | branch | 1.164750170684527e7 |
| 4 | generator_63 | generator | 1.13239335222857e7 |
| 5 | generator_29 | generator | 8.13785721632819e6 |
| 6 | generator_6 | generator | 8.054742581191909e6 |
| 7 | generator_43 | generator | 6.907948984199708e6 |
| 8 | branch_181 | branch | 6.700663040393634e6 |
| 9 | generator_48 | generator | 6.634060830733874e6 |
| 10 | generator_31 | generator | 6.2370829600908775e6 |
| 11 | generator_62 | generator | 5.942111711845723e6 |
| 12 | generator_40 | generator | 5.702355658240674e6 |
| 13 | branch_375 | branch | 4.846986857397018e6 |
| 14 | generator_59 | generator | 4.695363982220488e6 |
| 15 | generator_42 | generator | 4.41515768969299e6 |

## Accepted outcomes: lowest voltage headroom

| Rank | Contingency | Device | Voltage headroom (p.u.) |
|---:|---|---|---:|
| 1 | branch_285 | branch | 1.1235643304630116e-8 |
| 2 | branch_313 | branch | 1.7668478458077175e-8 |
| 3 | branch_278 | branch | 6.875976499287617e-8 |
| 4 | branch_183 | branch | 7.992584838412142e-8 |
| 5 | branch_329 | branch | 8.51067171181441e-8 |
| 6 | branch_339 | branch | 1.0196032829146162e-7 |
| 7 | branch_372 | branch | 1.4683296334361273e-7 |
| 8 | branch_335 | branch | 6.885664761702159e-7 |
| 9 | branch_345 | branch | 1.1424964523332193e-6 |

## Accepted outcomes: lowest thermal headroom

| Rank | Contingency | Device | Thermal headroom (p.u.) |
|---:|---|---|---:|
| 1 | branch_313 | branch | 8.621639291384042e-9 |
| 2 | branch_285 | branch | 9.757021413037137e-9 |
| 3 | branch_278 | branch | 3.725836872359167e-8 |
| 4 | branch_329 | branch | 4.9606695307069515e-8 |
| 5 | branch_339 | branch | 5.7288474186734106e-8 |
| 6 | branch_183 | branch | 1.208222855098029e-7 |
| 7 | branch_335 | branch | 4.1074077739011727e-7 |
| 8 | branch_372 | branch | 9.159693938887159e-7 |
| 9 | branch_345 | branch | 1.941608424593788e-6 |

## Accepted outcomes: lowest reactive-power headroom

| Rank | Contingency | Device | Reactive headroom (p.u.) |
|---:|---|---|---:|
| 1 | branch_285 | branch | 2.1609623188090232e-7 |
| 2 | branch_313 | branch | 4.805175257693861e-7 |
| 3 | branch_183 | branch | 6.605786700975003e-7 |
| 4 | branch_372 | branch | 8.438012285560959e-7 |
| 5 | branch_329 | branch | 1.8616517106773145e-6 |
| 6 | branch_278 | branch | 3.168629371441689e-6 |
| 7 | branch_339 | branch | 4.5581862788135474e-6 |
| 8 | branch_345 | branch | 7.803707958720096e-6 |
| 9 | branch_335 | branch | 2.092082986032695e-5 |

## Accepted outcomes: lowest active-power headroom

| Rank | Contingency | Device | Active headroom (p.u.) |
|---:|---|---|---:|
| 1 | branch_278 | branch | -3.2102204894357556e-8 |
| 2 | branch_339 | branch | -3.210057197833294e-8 |
| 3 | branch_335 | branch | -3.210028909350626e-8 |
| 4 | branch_285 | branch | -3.2100099911502866e-8 |
| 5 | branch_345 | branch | -3.209991739083762e-8 |
| 6 | branch_313 | branch | -3.2099806812624365e-8 |
| 7 | branch_329 | branch | -3.2097825730659224e-8 |
| 8 | branch_183 | branch | -3.17120689707906e-8 |
| 9 | branch_372 | branch | -3.17120689707906e-8 |

## Filtering baseline

A future screening method must be compared against all 391 completed exact evaluations. At minimum it must report recall for all 382 unresolved outcomes and separately account for the 89 unsupported islanding candidates. Accepted outcomes are not certified dynamically safe; they only pass this steady-state fixed-base formulation and its declared tolerances.
