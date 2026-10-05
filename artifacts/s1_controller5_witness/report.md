# IEEE-300 controller-5 deterministic witness replay

At load 1.02, both backends' strictly valid cumulative-six fixed-droop states remain strictly valid after removing controller 6, and after retaining controller 5 alone. No solve, relaxation, re-anchoring, or tolerance change is used.

| Witness backend | Replayed model | Valid | Max balance residual | Max exact-droop residual |
|---|---|---:|---:|---:|
| ipopt | raw | true | 1.1866063687193673e-12 | 0.0 |
| ipopt | cumulative_first_five | true | 1.1866063687193673e-12 | 4.440892098500626e-14 |
| ipopt | controller_5_only | true | 1.1866063687193673e-12 | 4.440892098500626e-14 |
| madnlp | raw | true | 5.703304495341399e-11 | 0.0 |
| madnlp | cumulative_first_five | true | 5.703304495341399e-11 | 3.907985046680551e-14 |
| madnlp | controller_5_only | true | 5.703304495341399e-11 | 3.907985046680551e-14 |

The matching direct five-controller and controller-5-only anchor paths fail for both Ipopt and MadNLP. The retained feasible states therefore classify those failures as `solver_path_failure_with_witness`; `LOCALLY_INFEASIBLE` is not a case-level infeasibility certificate here.
