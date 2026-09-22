# Frozen S1 — CCOpt exact-complementarity lane

This is the CCOpt counterpart to `examples/s1_policy_matrix.jl`: the same 12 public S1 cells (IEEE 118/300 × nominal/+5% load × anchor/flat-low/flat-high), overlay construction, controls, serialized design artifacts, and independent acceptance checks. CCOpt is evaluated with its native direct profile: one exact-complementarity solve per cell, 1000 inner iterations and 60 seconds. It has no portable dual-reset or outer-homotopy budget through MOI, therefore it is not assigned the Ipopt/MadNLP multiplier-reset recovery policy.

Profile: `sigma_min=1.0e-14`, `tol=1.0e-11`, `acceptable_tol=1.0e-11`. A result is accepted only when solver, policy, AC physical, and direct exact-droop validation all pass.

| Case | Status | Accepted | Validated local witness? | Physical | Exact droop max | Inner iterations | Seconds | Objective |
|---|---|---:|---|---:|---:|---:|---:|---:|
| public118-load1.0-ccopt-anchor | ITERATION_LIMIT | false | unknown (not infeasible) | false | 0.07926612102624732 | 1000 | 47.142058625 | 7.64418670132514 |
| public118-load1.0-ccopt-flat_low | ITERATION_LIMIT | false | unknown (not infeasible) | false | 0.09250966134148975 | 1000 | 12.507556334 | 7.639186594038165 |
| public118-load1.0-ccopt-flat_high | LOCALLY_SOLVED | true | yes | true | 5.441994956237317e-6 | 974 | 11.486070708 | 7.593141612459988 |
| public118-load1.05-ccopt-anchor | LOCALLY_SOLVED | true | yes | true | 3.789766942152717e-6 | 798 | 12.725170833 | 11.384334474339198 |
| public118-load1.05-ccopt-flat_low | ITERATION_LIMIT | false | unknown (not infeasible) | false | 0.010531543178895533 | 1000 | 13.22895475 | 11.40837627376527 |
| public118-load1.05-ccopt-flat_high | ITERATION_LIMIT | false | unknown (not infeasible) | false | 0.01131636727347718 | 1000 | 18.664433917 | 11.390882272848017 |
| public300-load1.0-ccopt-anchor | TIME_LIMIT | false | unknown (not infeasible) | false | 0.7497621018452314 | 952 | 60.119322916 | 88.79875715376897 |
| public300-load1.0-ccopt-flat_low | ITERATION_LIMIT | false | unknown (not infeasible) | false | 0.7497523540333884 | 1000 | 36.378773625 | 88.81483786358672 |
| public300-load1.0-ccopt-flat_high | ITERATION_LIMIT | false | unknown (not infeasible) | false | 0.7497332176080285 | 1000 | 49.842682791 | 89.18093545795364 |
| public300-load1.05-ccopt-anchor | ITERATION_LIMIT | false | unknown (not infeasible) | false | 0.17494932348083836 | 1000 | 43.728353292 | 140.67458640773134 |
| public300-load1.05-ccopt-flat_low | ITERATION_LIMIT | false | unknown (not infeasible) | false | 0.7497660221010989 | 1000 | 39.280901625 | 140.05402467494264 |
| public300-load1.05-ccopt-flat_high | ITERATION_LIMIT | false | unknown (not infeasible) | false | 0.7497216705409837 | 1000 | 47.893345458 | 140.44883821824783 |

CCOpt internal primal/dual/complementarity figures are retained in each `*-diagnostics.json`; they are relaxed-NLP diagnostics, not a certificate of the original MPCC. The direct curve audit is the physical droop acceptance criterion.
