# M7 exact-droop solver comparison

Acceptance: **PASS**. Ipopt and MadNLP use the same smoothed droop width (1e-5); CCOpt uses the exact fixed PWL droop graph. All three optimize identical continuous tap and simple-bank bounds, objective and physical model from two declared starts. Every attempt is retained; selection uses the lowest objective among independently valid outcomes.

| Solver | Run | Encoding | Status | Valid | Objective | Tap 11 | Bank 201 B | Exact droop residual | Complementarity | Seconds |
|---|---:|---|---|---|---:|---:|---:|---:|---:|---:|
| ipopt | 1 | smooth | LOCALLY_SOLVED | true | 2.1830840598066285e-5 | 1.002401314717557 | 4.454692019892765e-5 | 4.996003610813204e-16 | nothing | 2.372766542 |
| ipopt | 2 | smooth | LOCALLY_SOLVED | true | 2.183090639703312e-5 | 1.002401295929627 | 4.5607880944589275e-5 | 6.522560269672795e-16 | nothing | 0.00414775 |
| madnlp | 1 | smooth | LOCALLY_SOLVED | true | 2.1830552577094453e-5 | 1.0024013969691845 | 3.9902136202624556e-5 | 9.575673587391975e-16 | nothing | 8.077596875 |
| madnlp | 2 | smooth | LOCALLY_SOLVED | true | 2.18305529411351e-5 | 1.0024013968652108 | 3.990800768291687e-5 | 4.85722573273506e-16 | nothing | 0.002942208 |
| ccopt | 1 | complementarity | LOCALLY_SOLVED | true | 2.1828145127217313e-5 | 1.0024021944096198 | 1.5484517571947895e-6 | 1.9694850809937048e-7 | 4.547933493356092e-11 | 23.290566917 |
| ccopt | 2 | complementarity | LOCALLY_SOLVED | true | 2.1828145127383847e-5 | 1.0024021944094872 | 1.5484550807390627e-6 | 1.9694842492978815e-7 | 4.547933539376351e-11 | 0.01035225 |

| Solver | Selected run | Valid starts | Objective delta from Ipopt | Objective spread | Tap spread | Shunt-B spread |
|---|---:|---:|---:|---:|---:|---:|
| ipopt | 1 | 2/2 | 0.0 | 6.579896683392948e-11 | 1.8787930100572225e-8 | 1.0609607456616224e-6 |
| madnlp | 1 | 2/2 | -2.880209718322162e-10 | 3.6404064577286524e-13 | 1.0397371852377546e-10 | 5.8714802923128776e-9 |
| ccopt | 1 | 2/2 | -2.6954708489716696e-9 | 1.6653345369377348e-16 | 1.325606291402437e-13 | 3.323544273180299e-12 |

This is a local continuous comparison, not a discrete tap/shunt result or a global-optimality claim. Every result is replayed against reconstructed physical equipment and the exact droop curve.
