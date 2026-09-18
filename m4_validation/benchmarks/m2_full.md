# SCOPF benchmark: m2-three-bus

- Julia: 1.12.4
- DroopOPF: 0.4.0
- Solver: Ipopt
- Peak RSS scope: process lifetime; includes compilation, warm-up, solves and validation
- Structure: 3 scenarios, 3 buses, 3 branches, 2 generators

| Sample | Seconds | Allocated bytes | GC seconds | Variables | Constraints | Valid | Objective | Process peak RSS bytes |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 0.013715584 | 1900128 | 0.0 | 32 | 97 | true | 1.6763099432241095e-5 | 924794880 |
| 2 | 0.013311666 | 1900128 | 0.0 | 32 | 97 | true | 1.6763099432241095e-5 | 924794880 |
| 3 | 0.014393792 | 1900128 | 0.0 | 32 | 97 | true | 1.6763099432241095e-5 | 924794880 |
