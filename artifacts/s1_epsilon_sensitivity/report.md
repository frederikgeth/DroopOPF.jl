# S1 smooth-droop epsilon sensitivity

This is an experimental continuation/sensitivity study outside the frozen S1 acceptance counts. The fixed schedule is `0.01 → 0.001 → 0.0001 → 1.0e-5 → 1.0e-6 → 1.0e-7`. Each stage is warm-started from the latest solver- and policy-valid stage; a failed stage is retained and the scan continues from the last accepted warm start. Every stage keeps its raw exact-droop mismatch.

The strict column uses the unchanged `1e-5` physical droop tolerance. The `1e-2` column is diagnostic only and does not overwrite the frozen decision. Each stage has its own 1000-iteration/60-second allowance, so a gain here is a continuation result, not an equal-budget frozen improvement.

| Cell | Strict-valid epsilons | Diagnostic `1e-2` epsilons | Best raw mismatch (pu) | Frozen valid | Continuation changes strict result? |
|---|---|---|---:|---:|---:|
| `public118-load1.0-ipopt-anchor` | `1.0e-6` | `1.0e-5, 1.0e-6` | 3.918233654198744e-10 | true | false |
| `public118-load1.0-ipopt-flat_high` | `1.0e-6, 1.0e-7` | `1.0e-5, 1.0e-6, 1.0e-7` | 2.1881754186381386e-9 | true | false |
| `public118-load1.0-ipopt-flat_low` | `1.0e-6` | `1.0e-5, 1.0e-6` | 3.3951533667808675e-9 | true | false |
| `public118-load1.0-madnlp-anchor` | `1.0e-5, 1.0e-7` | `0.0001, 1.0e-5, 1.0e-7` | 2.348121697082206e-14 | false | true |
| `public118-load1.0-madnlp-flat_high` | `1.0e-7` | `0.0001, 1.0e-6, 1.0e-7` | 2.1877575026585383e-7 | false | true |
| `public118-load1.0-madnlp-flat_low` | `1.0e-6, 1.0e-7` | `1.0e-5, 1.0e-6, 1.0e-7` | 5.348046427933184e-7 | false | true |
| `public118-load1.05-ipopt-anchor` | `1.0e-7` | `1.0e-7` | 7.89687185920318e-8 | true | false |
| `public118-load1.05-ipopt-flat_high` | `—` | `1.0e-5` | 1.7622133922451377e-5 | false | false |
| `public118-load1.05-ipopt-flat_low` | `—` | `1.0e-5` | 0.0001591090477994772 | false | false |
| `public118-load1.05-madnlp-anchor` | `1.0e-5` | `0.0001, 1.0e-5` | 3.8191672047105385e-14 | false | true |
| `public118-load1.05-madnlp-flat_high` | `1.0e-5, 1.0e-7` | `1.0e-5, 1.0e-7` | 1.6486811915683575e-14 | false | true |
| `public118-load1.05-madnlp-flat_low` | `1.0e-6` | `0.0001, 1.0e-5, 1.0e-6` | 2.532908278451984e-6 | true | false |
| `public300-load1.0-ipopt-anchor` | `1.0e-5, 1.0e-6` | `0.0001, 1.0e-5, 1.0e-6` | 4.231990935466001e-8 | true | false |
| `public300-load1.0-ipopt-flat_high` | `1.0e-5` | `0.0001, 1.0e-5` | 7.1449892669051e-8 | false | true |
| `public300-load1.0-ipopt-flat_low` | `—` | `0.0001, 1.0e-5` | 4.152795476652926e-5 | false | false |
| `public300-load1.0-madnlp-anchor` | `1.0e-5, 1.0e-6, 1.0e-7` | `1.0e-5, 1.0e-6, 1.0e-7` | 1.2434497875801753e-14 | true | false |
| `public300-load1.0-madnlp-flat_high` | `—` | `0.0001` | 1.279283345922977e-10 | false | false |
| `public300-load1.0-madnlp-flat_low` | `1.0e-7` | `1.0e-7` | 2.7977620220553945e-14 | false | true |
| `public300-load1.05-ipopt-anchor` | `—` | `1.0e-5` | 1.9988565507222944e-6 | true | false |
| `public300-load1.05-ipopt-flat_high` | `1.0e-6` | `1.0e-5, 1.0e-6` | 1.9981074839137136e-7 | true | false |
| `public300-load1.05-ipopt-flat_low` | `1.0e-6` | `1.0e-5, 1.0e-6` | 5.154099369519827e-12 | true | false |
| `public300-load1.05-madnlp-anchor` | `—` | `—` | 2.3092638912203256e-14 | true | false |
| `public300-load1.05-madnlp-flat_high` | `0.0001` | `0.0001, 1.0e-5` | 1.7319479184152442e-14 | false | true |
| `public300-load1.05-madnlp-flat_low` | `1.0e-5` | `1.0e-5` | 4.3520742565306136e-14 | true | false |

Frozen accepted: **12/24**. At least one continuation stage strictly accepted: **18/24**. At least one stage passed the diagnostic `1e-2` droop gate with all other gates unchanged: **23/24**.

## Paired acceptance summary

| Solver | Frozen | Continuation union | Gained cells | Lost frozen cells |
|---|---:|---:|---:|---:|
| ipopt | 8/12 | 8/12 | 1 | 1 |
| madnlp | 4/12 | 10/12 | 7 | 1 |

## Per-epsilon behavior

| Epsilon | Solver-valid | Strict-valid | Diagnostic `1e-2` valid | Mean seconds |
|---:|---:|---:|---:|---:|
| 0.01 | 15/24 | 0/24 | 0/24 | 8.271 |
| 0.001 | 18/24 | 0/24 | 0/24 | 3.593 |
| 0.0001 | 18/24 | 1/24 | 9/24 | 2.166 |
| 1.0e-5 | 19/24 | 7/24 | 19/24 | 3.996 |
| 1.0e-6 | 10/24 | 9/24 | 10/24 | 4.14 |
| 1.0e-7 | 8/24 | 8/24 | 8/24 | 11.066 |

## S1 interpretation

Continuation materially improves aggregate strict acceptance, especially for MadNLP, but it does not satisfy S1's no-loss reliability criterion: some frozen-accepted cells are not reproduced by this path. It also spends up to six independent solve allowances per cell, so 18/24 is not an equal-budget replacement for the 12/24 frozen baseline. The result supports continuation as a promising opt-in recovery strategy, not as a new default or closure of S1.
