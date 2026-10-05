# SCOPF input/output evaluation

Changed-input solve: thermal limit=0.65 pu; active demand=0.6 pu. Acceptance is determined by the independent report, not assumed. Iteration budget: 300.

- Case: `m2-three-bus`
- Response mode: `preventive`
- Scenarios: 3
- Solver status: `LOCALLY_INFEASIBLE`
- Independently valid and solver-accepted: `false`

- Exact physical validation: `false`
- Encoded physical validation: `false`
- Primal status: `INFEASIBLE_POINT`
- Objective: `1.576522588661444e-6`

## Assumptions and interpretation

Steady-state AC equations with the declared demand, topology, generator limits and reactive controls. Power and voltage are per-unit; angles are radians. Preventive response uses surviving participation weights; corrective response uses the declared redispatch bounds. Equipment follows the declared timing and movement limits.

A solver success flag alone is not validation. Checks independently replay the saved states and solved tap/shunt settings against the declared study. PASS applies only to these scenarios and tolerances; it is not a dynamic-security, global-optimality or all-contingency certificate. Missing or malformed states are NOT EVALUATED, never physical passes. Response-delta plots include outage changes, are descriptive rather than pass/fail, and floor values at 1e-8.

## Reproducible inputs, outputs and tolerances

The accompanying evaluation-inputs.json and evaluation-outputs.json contain the complete declared study and saved solution, including network data, controls, limits, policy and scenario states. evaluation-validation.json contains the independently recomputed checks.

- Participation weights: `Dict(7 => 1.0, 9 => 1.0)`
- Redispatch limits (pu): `Dict{Int64, Float64}()`
- Base power: `100.0`; base frequency: `50.0`
- Demand by load (id, bus, P pu, Q pu): `[(1, 30, 0.6, 0.15)]`
- Generator bounds (id, Pmin, Pmax, Qmin, Qmax pu): `[(7, 0.0, 1.2, -1.0, 1.0), (9, 0.0, 1.2, -1.0, 1.0)]`
- Branch ratings (id, kind, apparent-power limit pu): `[(11, :line, 0.65), (22, :line, 0.65), (33, :line, 0.65)]`
- Bus voltage bounds (id, Vmin, Vmax pu): `[(10, 0.9, 1.1), (20, 0.9, 1.1), (30, 0.9, 1.1)]`
- Reactive response: declared legacy droop controls
- Validation tolerances: `(power_tolerance = 1.0e-6, droop_tolerance = 1.0e-5, limit_tolerance = 1.0e-6, unavailable_tolerance = 1.0e-8, coupling_tolerance = 1.0e-6)`

## Declared inputs and cross-scenario checks

![Declared network topology and equipment](scopf_network_topology.svg)

The topology figure documents the declared base equipment and limits. It is not a solved operating-state diagram: the scenario-input table and detailed operating plots show each outage and its resulting state.

![Declared scenario inputs](scopf_declared_inputs.svg)

![Operating margins](scopf_operating_margins.svg)

![Response deltas](scopf_response_deltas.svg)

![Validation matrix](scopf_validation_matrix.svg)

## Detailed operating plots

![Droop operating points](m2_droop_operating_points.svg)

![Bus voltages](m2_bus_voltages.svg)

![Network loading](m2_branch_loading.svg)

![Generator dispatch](m2_generator_dispatch.svg)

![Validation residuals](m2_validation_residuals.svg)

## Numerical validation

# SCOPF report: m2-three-bus

- Valid: `false`; exact-curve feasible: `false`; encoded-model feasible: `false`
- Solver: Ipopt; termination: `LOCALLY_INFEASIBLE`; primal: `INFEASIBLE_POINT`
- Mode: `preventive`; encoding: `smooth`
- Base dispatch objective: 1.576522588661444e-6
- Tolerances (p.u., reference angle in radians): `(power_tolerance = 1.0e-6, droop_tolerance = 1.0e-5, limit_tolerance = 1.0e-6, unavailable_tolerance = 1.0e-8, coupling_tolerance = 1.0e-6)`

| Scenario | AC residual | Exact droop residual | Encoded droop residual | Smooth/exact gap | Branch margin | P-response violation | Equipment violation | Failures |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| base | 0.1676468910980073 | 5.2572728182899976e-5 | 5.274549681430123e-5 | 1.8106985277821508e-7 | 0.3491053572326575 | 0.0 | 0.0 | power_balance, droop |
| line_22 | 2.7478019859472624e-15 | 1.6653345369377348e-16 | 5.551115123125783e-17 | 1.1102230246251565e-16 | 0.016147211335365008 | 5.637851296924623e-18 | 0.0 | none |
| generator_9 | 0.16777226495043018 | 4.7167753702660463e-7 | 2.3152969559237108e-9 | 4.7399283398252834e-7 | 0.24845333303011796 | 0.0 | 0.0 | power_balance |

Controls and network limits are checked independently in each scenario. Active-power response follows the declared policy; this report makes no dynamic or frequency-stability claim.
