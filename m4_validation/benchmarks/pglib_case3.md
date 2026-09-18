# SCOPF benchmark: pglib_opf_case3_lmbd

- Julia: 1.12.4
- DroopOPF: 0.4.0
- Solver: Ipopt
- Peak RSS scope: process lifetime; includes compilation, warm-up, solves and validation
- Structure: 1 scenarios, 3 buses, 3 branches, 3 generators

| Sample | Seconds | Allocated bytes | GC seconds | Variables | Constraints | Valid | Objective | Process peak RSS bytes |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 0.00393125 | 687856 | 0.0 | 12 | 36 | true | 141.4785809808278 | 946094080 |
| 2 | 0.003077958 | 687856 | 0.0 | 12 | 36 | true | 141.4785809808278 | 946094080 |
| 3 | 0.002895083 | 687856 | 0.0 | 12 | 36 | true | 141.4785809808278 | 946094080 |
