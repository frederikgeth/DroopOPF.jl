# M10 IEEE contingency analysis

- Full eligible catalog complete: true.
- Candidates: 240; eligible and evaluated: 231; structurally excluded: 9.
- Classifications: Dict("accepted" => 67, "invalid" => 164).
- Solver statuses: Dict("LOCALLY_INFEASIBLE" => 163, "LOCALLY_SOLVED" => 67, "ALMOST_LOCALLY_SOLVED" => 1).
- Validation failures: Dict("branch_thermal" => 3, "active_power_response" => 6, "power_balance" => 164).
- Evaluation time: 97.843 s total; 0.258 s median; 0.996 s p95; 11.159 s maximum.

All eligible outages were evaluated before ranking. Excluded islanding outages are unsupported, not safe. Invalid and solver-limited outcomes are unresolved, not filtered failures.

Normalized violation is the largest independent residual-to-tolerance ratio across AC balance, availability, coupling, and operating-limit checks. It orders diagnostic attention; it is not a physical stability index.

## Unresolved outcomes

| Rank | Contingency | Device | Normalized violation |
|---:|---|---|---:|
| 1 | generator_30 | generator | 6.604848413726697e6 |
| 2 | generator_29 | generator | 4.728575317261686e6 |
| 3 | generator_37 | generator | 3.0107568922422444e6 |
| 4 | generator_28 | generator | 2.982940331137161e6 |
| 5 | generator_45 | generator | 2.9636140428051422e6 |
| 6 | generator_40 | generator | 2.7918585082684522e6 |
| 7 | generator_25 | generator | 2.44844214449361e6 |
| 8 | generator_5 | generator | 2.288878887453141e6 |
| 9 | generator_21 | generator | 1.9977054542522475e6 |
| 10 | generator_12 | generator | 1.851184070552395e6 |
| 11 | generator_26 | generator | 1.7776205225962372e6 |
| 12 | generator_11 | generator | 1.4023028599166875e6 |
| 13 | branch_8 | branch | 1.2089008461889396e6 |
| 14 | generator_46 | generator | 1.0951892231542554e6 |
| 15 | branch_96 | branch | 1.0886176637777379e6 |

## Accepted outcomes: lowest voltage headroom

| Rank | Contingency | Device | Voltage headroom (p.u.) |
|---:|---|---|---:|
| 1 | branch_35 | branch | 3.440242650754044e-7 |
| 2 | generator_15 | generator | 2.734683576477437e-6 |
| 3 | branch_15 | branch | 3.5319684434931276e-6 |
| 4 | generator_38 | generator | 3.945869528676482e-6 |
| 5 | branch_157 | branch | 4.802134697889926e-6 |
| 6 | generator_7 | generator | 5.8297130085538384e-6 |
| 7 | branch_42 | branch | 9.447661756478709e-6 |
| 8 | branch_78 | branch | 9.558798400810531e-6 |
| 9 | generator_17 | generator | 9.61314878766828e-6 |
| 10 | branch_180 | branch | 1.097211297440559e-5 |
| 11 | generator_52 | generator | 1.3353503380830745e-5 |
| 12 | generator_4 | generator | 1.3981458848455475e-5 |
| 13 | branch_80 | branch | 1.4242189005697625e-5 |
| 14 | generator_24 | generator | 1.613708696113214e-5 |
| 15 | branch_162 | branch | 1.628898797068068e-5 |

## Accepted outcomes: lowest thermal headroom

| Rank | Contingency | Device | Thermal headroom (p.u.) |
|---:|---|---|---:|
| 1 | branch_61 | branch | 0.035848897802488455 |
| 2 | branch_59 | branch | 0.06310530778288659 |
| 3 | branch_30 | branch | 0.0830402697016488 |
| 4 | branch_110 | branch | 0.09006257593862588 |
| 5 | branch_60 | branch | 0.09316276086928932 |
| 6 | branch_112 | branch | 0.09346534364627845 |
| 7 | branch_111 | branch | 0.1000539257678228 |
| 8 | generator_17 | generator | 0.10313514505574706 |
| 9 | branch_25 | branch | 0.10322533453740057 |
| 10 | generator_16 | generator | 0.10347306443631954 |
| 11 | branch_80 | branch | 0.10358696393655242 |
| 12 | branch_42 | branch | 0.10451234588267355 |
| 13 | branch_101 | branch | 0.10472476691395038 |
| 14 | branch_83 | branch | 0.10493149360531973 |
| 15 | branch_73 | branch | 0.10579060535255269 |

## Accepted outcomes: lowest reactive-power headroom

| Rank | Contingency | Device | Reactive headroom (p.u.) |
|---:|---|---|---:|
| 1 | branch_35 | branch | 1.7065888869599588e-5 |
| 2 | generator_15 | generator | 0.0001316427591992464 |
| 3 | branch_15 | branch | 0.0001695834571878163 |
| 4 | generator_38 | generator | 0.00018704885997142262 |
| 5 | branch_157 | branch | 0.00022864866232111258 |
| 6 | generator_7 | generator | 0.0002798240307242683 |
| 7 | branch_42 | branch | 0.00045156050561873107 |
| 8 | branch_78 | branch | 0.0004558582251489862 |
| 9 | generator_17 | generator | 0.0004852416298887219 |
| 10 | branch_180 | branch | 0.0005208628444524077 |
| 11 | generator_52 | generator | 0.0006322622532203559 |
| 12 | generator_4 | generator | 0.0006599958408746442 |
| 13 | branch_80 | branch | 0.0006773399406952707 |
| 14 | generator_24 | generator | 0.0007655066362731444 |
| 15 | branch_162 | branch | 0.0007678827381214781 |

## Accepted outcomes: lowest active-power headroom

| Rank | Contingency | Device | Active headroom (p.u.) |
|---:|---|---|---:|
| 1 | branch_146 | branch | -1.0799930949545455e-8 |
| 2 | generator_43 | generator | -1.0799921179582839e-8 |
| 3 | branch_73 | branch | -1.079991807095837e-8 |
| 4 | generator_54 | generator | -1.079991807095837e-8 |
| 5 | branch_115 | branch | -1.0799917848913765e-8 |
| 6 | branch_82 | branch | -1.0799917848913765e-8 |
| 7 | branch_161 | branch | -1.0799917404824555e-8 |
| 8 | generator_48 | generator | -1.0799914740289296e-8 |
| 9 | branch_152 | branch | -1.0799913852110876e-8 |
| 10 | generator_47 | generator | -1.0799911853709432e-8 |
| 11 | branch_77 | branch | -1.0799908523040358e-8 |
| 12 | branch_182 | branch | -1.0799908300995753e-8 |
| 13 | generator_44 | generator | -1.0799908078951148e-8 |
| 14 | generator_27 | generator | -1.0799907856906543e-8 |
| 15 | generator_32 | generator | -1.0799907856906543e-8 |

## Filtering baseline

A future screening method must be compared against all 231 completed exact evaluations. At minimum it must report recall for all 164 unresolved outcomes and separately account for the 9 unsupported islanding candidates. Accepted outcomes are not certified dynamically safe; they only pass this steady-state fixed-base formulation and its declared tolerances.
