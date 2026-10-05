# M10 pre-solve screening benchmark

- Method: within-device percentile of base AC branch loading or generator active-power share.
- Exact baseline: 231 eligible outages; 164 unresolved; 67 accepted.
- Evaluations required for 100% retrospective unresolved recall: 217/231.
- Maximum retrospective omissions at that recall: 14.

This heuristic uses only the validated base state and device data. It did not select the exact-enumeration baseline. Results are retrospective and do not authorize filtering in a new case.

| Evaluation budget | Evaluated | Unresolved captured | Unresolved omitted | Recall | Accepted omitted |
|---:|---:|---:|---:|---:|---:|
| 0.25 | 58 | 58 | 106 | 0.35365853658536583 | 67 |
| 0.5 | 116 | 93 | 71 | 0.5670731707317073 | 44 |
| 0.75 | 174 | 141 | 23 | 0.8597560975609756 | 34 |
| 0.9 | 208 | 162 | 2 | 0.9878048780487805 | 21 |
| 0.95 | 220 | 164 | 0 | 1.0 | 11 |
| 1.0 | 231 | 164 | 0 | 1.0 | 0 |

## Highest-priority outages

| Rank | Contingency | Device | Raw score | Percentile score | Exact class |
|---:|---|---|---:|---:|---|
| 1 | branch_116 | branch | 0.885155697170805 | 1.0 | invalid |
| 2 | generator_30 | generator | 0.1526716257110085 | 1.0 | invalid |
| 3 | branch_66 | branch | 0.8785309796783421 | 0.9943181818181818 | invalid |
| 4 | branch_67 | branch | 0.8785309796783421 | 0.9943181818181818 | invalid |
| 5 | branch_96 | branch | 0.8529835428837316 | 0.9829545454545454 | invalid |
| 6 | generator_29 | generator | 0.10719501807510329 | 0.9811320754716981 | invalid |
| 7 | branch_108 | branch | 0.7889402639082381 | 0.9772727272727273 | invalid |
| 8 | branch_33 | branch | 0.7758051425791134 | 0.9715909090909091 | invalid |
| 9 | branch_31 | branch | 0.7642703378091067 | 0.9659090909090909 | invalid |
| 10 | generator_45 | generator | 0.09167899681044792 | 0.9622641509433962 | invalid |
| 11 | branch_98 | branch | 0.7456326381010532 | 0.9602272727272727 | invalid |
| 12 | branch_99 | branch | 0.7456326381010532 | 0.9602272727272727 | invalid |
| 13 | branch_155 | branch | 0.7060403366834384 | 0.9488636363636364 | invalid |
| 14 | generator_40 | generator | 0.08990473781194729 | 0.9433962264150944 | invalid |
| 15 | branch_38 | branch | 0.6886350597339176 | 0.9431818181818182 | invalid |
| 16 | branch_21 | branch | 0.6789680076818128 | 0.9375 | invalid |
| 17 | branch_119 | branch | 0.6563235622948322 | 0.9318181818181818 | invalid |
| 18 | branch_41 | branch | 0.63759413966683 | 0.9261363636363636 | invalid |
| 19 | generator_5 | generator | 0.07631395092031727 | 0.9245283018867925 | invalid |
| 20 | branch_105 | branch | 0.6195205426127807 | 0.9204545454545454 | invalid |
| 21 | branch_106 | branch | 0.6092815445135433 | 0.9147727272727273 | invalid |
| 22 | branch_50 | branch | 0.6038042980709366 | 0.9090909090909091 | invalid |
| 23 | generator_37 | generator | 0.07572244728797452 | 0.9056603773584906 | invalid |
| 24 | branch_3 | branch | 0.5841701855725825 | 0.9034090909090909 | invalid |
| 25 | branch_139 | branch | 0.5741009423043771 | 0.8977272727272727 | invalid |

## Interpretation

A useful filter must set its threshold on separate training evidence and then demonstrate high recall on held-out exact evaluations. Any unresolved omission is a false negative. Structurally excluded islanding outages remain outside this heuristic and require an island-aware formulation; they cannot be labelled safe.
