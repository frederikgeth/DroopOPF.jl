# SCOPF benchmark: pglib_opf_case5_pjm

- Julia: 1.12.4
- DroopOPF: 0.4.0
- Solver: Ipopt
- Peak RSS scope: process lifetime; includes compilation, warm-up, solves and validation
- Structure: 1 scenarios, 5 buses, 6 branches, 5 generators

| Sample | Seconds | Allocated bytes | GC seconds | Variables | Constraints | Valid | Objective | Process peak RSS bytes |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 0.006718041 | 1341008 | 0.0 | 20 | 62 | true | 1.2393052289084356 | 954433536 |
| 2 | 0.00652225 | 1341008 | 0.0 | 20 | 62 | true | 1.2393052289084356 | 954433536 |
| 3 | 0.005536042 | 1341008 | 0.0 | 20 | 62 | true | 1.2393052289084356 | 954433536 |
