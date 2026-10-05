# M10 pre-solve screening benchmark

- Method: within-device percentile of base AC branch loading or generator active-power share.
- Exact baseline: 391 eligible outages; 382 unresolved; 9 accepted.
- Evaluations required for 100% retrospective unresolved recall: 391/391.
- Maximum retrospective omissions at that recall: 0.

This heuristic uses only the validated base state and device data. It did not select the exact-enumeration baseline. Results are retrospective and do not authorize filtering in a new case.

| Evaluation budget | Evaluated | Unresolved captured | Unresolved omitted | Recall | Accepted omitted |
|---:|---:|---:|---:|---:|---:|
| 0.25 | 98 | 98 | 284 | 0.25654450261780104 | 9 |
| 0.5 | 196 | 196 | 186 | 0.5130890052356021 | 9 |
| 0.75 | 294 | 290 | 92 | 0.7591623036649214 | 5 |
| 0.9 | 352 | 344 | 38 | 0.900523560209424 | 1 |
| 0.95 | 372 | 364 | 18 | 0.9528795811518325 | 1 |
| 1.0 | 391 | 382 | 0 | 1.0 | 0 |

## Highest-priority outages

| Rank | Contingency | Device | Raw score | Percentile score | Exact class |
|---:|---|---|---:|---:|---|
| 1 | branch_251 | branch | 1.0000000155100979 | 1.0 | invalid |
| 2 | generator_11 | generator | 0.0628951833597856 | 1.0 | invalid |
| 3 | branch_223 | branch | 1.0000000062142824 | 0.9968847352024922 | invalid |
| 4 | branch_190 | branch | 1.0000000016287978 | 0.9937694704049844 | invalid |
| 5 | branch_178 | branch | 0.930493354586844 | 0.9906542056074766 | invalid |
| 6 | branch_182 | branch | 0.9277435361985487 | 0.9875389408099688 | invalid |
| 7 | generator_28 | generator | 0.059638153010427644 | 0.9852941176470589 | invalid |
| 8 | branch_268 | branch | 0.8390307842961496 | 0.9844236760124611 | invalid |
| 9 | branch_189 | branch | 0.8022804808415033 | 0.9813084112149533 | invalid |
| 10 | branch_181 | branch | 0.7930933019705244 | 0.9781931464174455 | invalid |
| 11 | branch_112 | branch | 0.7915810577671566 | 0.9750778816199377 | invalid |
| 12 | branch_211 | branch | 0.7375534610574359 | 0.9719626168224299 | invalid |
| 13 | generator_31 | generator | 0.05331820526077292 | 0.9705882352941176 | invalid |
| 14 | branch_309 | branch | 0.7255929525291036 | 0.9688473520249221 | invalid |
| 15 | branch_252 | branch | 0.7233342715678592 | 0.9657320872274143 | invalid |
| 16 | branch_249 | branch | 0.7229080598357408 | 0.9626168224299065 | invalid |
| 17 | branch_116 | branch | 0.7027149566995218 | 0.9595015576323987 | invalid |
| 18 | branch_222 | branch | 0.6907640003655828 | 0.956386292834891 | invalid |
| 19 | generator_63 | generator | 0.04997456549899168 | 0.9558823529411765 | invalid |
| 20 | branch_193 | branch | 0.6692099127251825 | 0.9532710280373832 | invalid |
| 21 | branch_233 | branch | 0.6637862965622945 | 0.9501557632398754 | invalid |
| 22 | branch_213 | branch | 0.6630854043218329 | 0.9470404984423676 | invalid |
| 23 | branch_327 | branch | 0.6276013375983446 | 0.9439252336448598 | invalid |
| 24 | generator_29 | generator | 0.04212593778794501 | 0.9411764705882353 | invalid |
| 25 | branch_115 | branch | 0.6205123853005281 | 0.940809968847352 | invalid |

## Interpretation

A useful filter must set its threshold on separate training evidence and then demonstrate high recall on held-out exact evaluations. Any unresolved omission is a false negative. Structurally excluded islanding outages remain outside this heuristic and require an island-aware formulation; they cannot be labelled safe.
