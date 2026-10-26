# Validation tables

Recorded outcomes retain their original scope. Historical assertion counts are checkpoint records, not current test results. Solver convergence, physical replay, operating limits, policy and coverage are distinct acceptance gates.

## [M1 — AC OPF with fixed volt-var curves](@id evidence-m1-tables)

| Check / comparison | Recorded result |
| --- | --- |
| Model | Base AC OPF, MATPOWER adapter, exact/smooth saturated volt-var response. |
| Acceptance | Independent equilibrium replay and deliberate-corruption tests. |
| Evidence type | Implementation and small-case numerical validation; not a large-network study. |

[Report](@ref evidence-m1-report)

## [M2 — Security-constrained AC OPF](@id evidence-m2-tables)

| Check / comparison | Recorded result |
| --- | --- |
| Scenario contract | Outage overlays preserve source input and deactivate failed equipment. |
| Coupling | Base and outage dispatch share the declared response policy; not independent OPFs. |
| Regression | Empty contingency sets reproduce base OPF; invalid policies and perturbations are rejected. |

[Report](@ref evidence-m2-report)

## [M3 — Bounded droop design](@id evidence-m3-tables)

| Check / comparison | Recorded result |
| --- | --- |
| Design | Shared bounded slope/reference/deadband parameters in the supported volt-var family. |
| Equivalence | Fixing selected parameters reproduces the underlying SCOPF problem. |
| Generalization | Held-out checks have their own acceptance gate. |

[Report](@ref evidence-m3-report)

## [M4 — Robustness and benchmark gate](@id evidence-m4-tables)

| Check / comparison | Recorded result |
| --- | --- |
| Repeated starts | Inputs, outputs, validation and objective/parameter spread are retained. |
| Diagnostics | Near-breakpoint controls, binding limits and critical scenarios are identified. |
| Benchmarks | Two pinned PGLib cases exercise adapter, solver, serialization and replay. |

[Report](@ref evidence-m4-report)

## [M5 — Transformer reference physics](@id evidence-m5-tables)

| Check / comparison | Recorded result |
| --- | --- |
| Physics | Both-terminal currents/powers, phase shifts, ratings and availability. |
| Integration | Fixed transformers participate in OPF, SCOPF and bounded droop design. |
| Historical checkpoint | 440/440 regression assertions at the M5 checkpoint; not a newly rerun count. |

[Report](@ref evidence-m5-report)

## [M6 — Shunt reference physics](@id evidence-m6-tables)

| Check / comparison | Recorded result |
| --- | --- |
| Physics | Positive conductance consumes active power; reactive power follows the declared susceptance sign and V-squared scaling. |
| Bank states | Supplied immutable legal count states are modeled; this does not optimize switching. |
| Historical checkpoint | 691/691 regression assertions at the M6 checkpoint; not a newly rerun count. |

[Report](@ref evidence-m6-report)

## [M7 — Continuous equipment and joint droop optimization](@id evidence-m7-tables)

| Check / comparison | Recorded result |
| --- | --- |
| M7.1 fixed / one tap / two taps | AC residuals 2.43e-15 / 2.87e-13 / 5.83e-14 pu. |
| M7.2 | 31-point capacitor/reactor sweeps and one/two-free-bank comparisons. |
| M7.3 | Eight fixed/free combinations, two starts each; all 16 reported starts physically valid. |
| Acceptance | AC 1e-6 pu; exact droop 1e-5 pu; continuous settings independently reconstructed. |
| Fresh CCOpt equipment comparison, 26 October | Two starts each for Ipopt/MadNLP/CCOpt: 6/6 native and independent physical acceptances. Droop parameters fixed; this is an equipment-design comparison, separate from the historical joint grid. Recorded before the MadNLP 0.10.3 dependency update; its original environment is retained. |

[Report](@ref evidence-m7-report) · [Figures](@ref evidence-m7-figures)

## [M8 — Steady-state transformer AVR](@id evidence-m8-tables)

| Check / comparison | Recorded result |
| --- | --- |
| Control meaning | An AVR-controlled tap follows a regulation equilibrium rather than unconstrained loss optimization. |
| Limits | Saturation and unmet target conditions remain visible. |
| Timing | Static equilibrium does not infer delay, dwell, hunting, reached position or action count. |

[Report](@ref evidence-m8-report)

## [M9 — Equipment-aware SCOPF](@id evidence-m9-tables)

| Check / comparison | Recorded result |
| --- | --- |
| Preventive policy | Selected common settings are shared over declared scenarios. |
| Corrective policy | Only selected equipment can move, within absolute and movement bounds. |
| Stages | Immediate and settled states are paired static assessments, not a transient trajectory. |

[Report](@ref evidence-m9-report)

## [M10 — Contingency assessment and comparative evidence](@id evidence-m10-tables)

| Check / comparison | Recorded result |
| --- | --- |
| M10.1 | 414 sourced equation-reference checks, three snapshots and eight applicable negative controls. |
| M10.2 | 54 feasible comparison groups; fixed-Q 105% comparator has a certified negative result. Original all-feasible gate failed. |
| M10.3 | 3,042/3,042 historical regression assertions, 126 saved-state replays and 32 profile runs. |
| Assessment engine | Catalogues, exact evaluation, ranking and resumable campaigns are implemented. |

[Report](@ref evidence-m10-report)

## [S1 — Convergence and scale study](@id evidence-s1-tables)

| Check / comparison | Recorded result |
| --- | --- |
| 14-bus free-droop matrix | 360/360 direct attempts; 120/120 solver/model/demand combinations accepted. |
| 500-bus free-droop matrix | 308/360 direct attempts; 120/120 combinations accepted after recovery. |
| Known-witness serial profile | 14 buses: 48/48 direct; 500 buses: 42/48 direct and 48/48 after recovery. |
| Fresh deadband extension | 0/0.005/0.01 pu half-width campaign is separate and in progress; historical closure is unchanged. |

[Report](@ref evidence-s1-report)

## [S2 — Shared security-design study](@id evidence-s2-tables)

| Check / comparison | Recorded result |
| --- | --- |
| 14 buses | Ipopt, MadNLP and CCOpt each qualify five training and four held-out demands over 24 connected outages. |
| 14-bus replay | 675 connected-state records plus 27 conditional island projections; zero recorded discrepancies. |
| 14-bus local nominal loss | Ipopt 0.886179073 MW; MadNLP 0.886179533 MW; CCOpt 0.886178982 MW. |
| 500 buses | Original campaign paused; normal-limit, emergency/relief and later P2 results retain separate policies. |
| Fresh deadband extension | In progress under a separately declared normal-limit/full-load sensitivity; does not resume original S2. |

[Report](@ref evidence-s2-report)

## [P0 — Proof-of-concept foundation](@id evidence-p0-tables)

| Check / comparison | Recorded result |
| --- | --- |
| P0-01–04 | Package/CI, types, input validation and MATPOWER adapter. |
| P0-05–09 | AC OPF, independent residuals, exact/smooth curves and reactive sharing. |
| P0-10–12 | One contingency, independent equilibrium validation and reports/examples. |

[Report](@ref evidence-p0-report)

## [P1 — Useful research-prototype workflow](@id evidence-p1-tables)

| Check / comparison | Recorded result |
| --- | --- |
| P1-01–05 | Multiple outages, policy modes, epsilon continuation, exact/smooth replay and versioned serialization. |
| P1-06 | Named M2 state and M3 parameter starts retain outputs and spread. |
| P1-07 | Two pinned PGLib-OPF v23.07 cases exercise the full adapter/solve/replay path. |
| P1-08 | Environment, actual JuMP dimensions, timing, allocations, objective and validity recorded. |

[Report](@ref evidence-p1-report)

## [P2 — Scaling and qualification](@id evidence-p2-tables)

| Check / comparison | Recorded result |
| --- | --- |
| Latest candidate | joint-five; Ipopt; feasibility objective, five one-hour demands 90/100/105/100/90%. |
| Connected coverage | 389/389 accepted five-period outage trajectories; no remaining numerical failures in that catalogue. |
| Replay accounting | 390 selected result files and 3,910 replayed state instances including repeated bases. |
| Operating policy | Full load, normal voltage/Rate-A, limit-aware active response; 15 AVR / 36 droop and assumed S=Pmax/0.95 circles. |
| Equipment | 131 continuous taps, supplied ±5%, movement ≤0.025 supplied ratio; 11 continuous banks, legal envelopes and ≤two sections; assumed 120-second settled stage. |
| Base loss energy | 121.62343825 MWh over five hours; not a certified minimum. |
| Open gates | General predictive skipping, full-catalogue resource/loss optimality, dynamics/discrete validation and large coupled memory limits. |

[Report](@ref evidence-p2-report) · [Figures](@ref evidence-p2-figures)

## [P3 — Extended model scope](@id evidence-p3-tables)

| Check / comparison | Recorded result |
| --- | --- |
| Initial multi-period slice | Five hourly 3/14/500-bus comparisons; 30 base-operation states independently replayed; fixed equipment. |
| RAW support | Strict AC conversion for supported v33/v34/v36 schemas; native v36 export qualification pending. |
| Saved-state check | Replay VM/VA/PG/QG without optimization or state repair; default saved-export tolerance 0.01 MW/MVAr per bus, distinct from solver acceptance. Missing ratings remain thermally unassessed; an import placeholder is not an equipment rating. |
| Mixed controls | Later outage recourse and AVR schedules have campaign-specific evidence under P2. |
| Deferred | Storage, detailed GFL/GFM, dynamics and general discrete equipment scheduling. |

[Report](@ref evidence-p3-report)
