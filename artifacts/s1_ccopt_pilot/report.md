# S1 CCOpt pilot

This pilot is deliberately separate from the frozen Ipopt/MadNLP acceptance matrix. CCOpt uses a 1000 cumulative inner-iteration and 60-second native wall budget per attempt; its MOI wrapper does not expose a separate outer-homotopy count or budget.

| Case | Status | Valid | Objective | Inner iterations | Complementarity | Primal | Dual | Seconds |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| synthetic-joint-run1 | LOCALLY_SOLVED | true | 2.180817949146152e-5 | 27 | 4.547599778969756e-11 | 4.547599778969756e-11 | 1.2342470795401184e-13 | 29.955030041 |
| synthetic-joint-run2 | LOCALLY_SOLVED | true | 2.180817949146152e-5 | 25 | 4.5475997789697554e-11 | 4.5475997789697554e-11 | 1.2342644267748781e-13 | 0.010221334 |
| public118-fixed-run1 | LOCALLY_SOLVED | true | 7.621127059262051 | 30 | 7.775749228178714e-11 | 7.775749228178714e-11 | 2.8872373242228022e-11 | 0.141902125 |
| public118-fixed-run2 | LOCALLY_SOLVED | true | 7.621127059262051 | 149 | 7.775749234559155e-11 | 7.775749234559155e-11 | 2.8872394058909734e-11 | 0.712426458 |
| public118-joint-run1 | LOCALLY_SOLVED | false | 7.619955823998708 | 307 | 9.089930168332074e-11 | 9.089930168332074e-11 | 9.86178153028483e-12 | 2.264498416 |
| public118-joint-run2 | LOCALLY_SOLVED | false | 7.619955823998652 | 594 | 9.089930168398348e-11 | 9.089930168398348e-11 | 1.0983693989052856e-11 | 4.294530084 |
| public118-joint-tight-run1 | LOCALLY_SOLVED | true | 7.6199599063986625 | 408 | 9.089954245768859e-13 | 9.089954245768859e-13 | 1.0803343808884537e-13 | 3.300957542 |
| public118-joint-tight-run2 | LOCALLY_SOLVED | true | 7.619959906398606 | 687 | 9.089954245768857e-13 | 9.089954245768857e-13 | 1.5804368767941414e-13 | 5.262979417 |
| public300-fixed-run1 | LOCALLY_SOLVED | true | 101.63069640928052 | 32 | 8.023783469726897e-11 | 8.023783469726897e-11 | 1.6843092892626643e-11 | 0.664913625 |
| public300-fixed-run2 | LOCALLY_SOLVED | true | 101.63069640928074 | 234 | 8.023849191198556e-11 | 8.023849191198556e-11 | 8.003144933876414e-12 | 2.835425625 |
| public300-joint-run1 | LOCALLY_SOLVED | true | 101.62649861140244 | 120 | 9.090006573873731e-11 | 9.090006573873731e-11 | 4.4360699947574384e-12 | 1.674868792 |
| public300-joint-run2 | LOCALLY_SOLVED | true | 101.62649861140312 | 296 | 9.090006573879586e-11 | 9.090006573879586e-11 | 5.952191864389e-12 | 4.358021625 |
| public300-joint-tight-run1 | LOCALLY_SOLVED | true | 101.62650315517499 | 265 | 9.090034416122678e-13 | 9.090034416122678e-13 | 2.826417341383713e-12 | 5.754600958 |
| public300-joint-tight-run2 | LOCALLY_SOLVED | true | 101.62650315517544 | 327 | 9.09003441612168e-13 | 1.8189894035458565e-12 | 2.794209308376594e-12 | 5.342501666 |

Final primal/dual figures are CCOpt's relaxed-NLP metrics. They are not an original-MPCC stationarity certificate. Every acceptance decision also requires independent AC, equipment-policy and exact-droop validation.
