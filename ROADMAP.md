# DroopOPF.jl Development Roadmap

Status: agile development plan with proof-of-concept priority.

Last updated: 2026-09-03

## 1. Product goal

Deliver a small but scientifically credible proof of concept that demonstrates:

> A Julia library can load a small AC network, attach synchronous-generator volt-var droop controls, solve a base AC OPF, and independently validate the resulting equilibrium.

The proof of concept is successful when the entire workflow is executable from a clean environment and produces an interpretable validation report.

## 2. Product strategy

Use vertical slices. Each iteration should leave the repository in a runnable state.

The priority order is:

```text
physical semantics
→ independent validation
→ droop response
→ one contingency
→ reproducible user workflow
→ robustness
→ performance
→ generality
```

Avoid spending early iterations on infrastructure that does not improve the proof of concept.

## 3. Proof-of-concept scope

### Included

- balanced single-phase AC network;
- MATPOWER case input;
- 3–9 buses;
- two or three generators;
- one reactive-power/voltage droop curve per participating generator;
- explicit regulated bus or terminal location per controller;
- reactive capability limits associated with each generator;
- one line or generator outage;
- base and post-contingency AC states;
- smooth softplus droop encoding;
- exact PWL curve replay;
- independent equilibrium validation;
- Markdown and machine-readable result report.

### Deferred

- multiple islands;
- frequency/active-power droop and dynamic governor response;
- PV/PQ switching;
- generator dynamic states;
- frequency nadir and RoCoF;
- multi-period studies;
- storage and unit commitment;
- PSS/E and PowerSystems adapters;
- GPU, MPI, and distributed decomposition;
- global optimality certificates.

## 4. Release targets

### v0.1.0-alpha: trusted reference slice

The release should provide:

```julia
case = load_case("case9_droop.json")
study = Study(case; contingencies = [:generator_2])
result = solve(study)
report = validate_equilibrium(study, result)
```

The report must state whether the base case and each contingency are valid, including residuals, margins, droop errors, smoothing error, solver metadata, and assumptions.

### v0.2.0-alpha: reusable SCOPF engine

Add:

- multiple contingencies;
- full enumeration;
- preventive and corrective modes;
- scenario-indexed results;
- exact and smooth control encodings;
- epsilon continuation;
- case and result serialization.

### v0.3.0-beta: scalable algorithm path

Add:

- contingency ranking;
- fast contingency evaluation;
- violation-driven constraint generation;
- warm starts;
- parallel scenario evaluation;
- benchmark and profiling harness.

### v1.0.0: stable research API

Only consider a 1.0 release after:

- the data model is versioned;
- results are backward-compatible;
- reference cases are reproducible;
- documentation covers assumptions and limitations;
- at least one large public benchmark family is supported;
- independent validation is part of the normal workflow.

## 5. Agile iterations

The suggested cadence is one-week iterations, with a demonstrable artifact at the end of each iteration. A team may compress or extend the timebox, but should preserve the order and exit criteria.

### Iteration 0 — charter and model contract

Deliver:

- `ARCHITECTURE.md`;
- this roadmap;
- equations for AC balance, droop, and contingency response;
- sign and unit conventions;
- a hand-worked 3-bus example;
- initial acceptance criteria.

Exit criteria:

- a reviewer can explain what `Δf` means;
- base dispatch and contingency response are unambiguous;
- the expected direction of generator response is known;
- unsupported scope is documented.

### Iteration 1 — package skeleton and data validation

Deliver:

- Julia package skeleton;
- minimal domain types;
- native in-memory case construction;
- curve validation;
- generator/control references;
- CI with unit tests.

Exit criteria:

- invalid IDs fail clearly;
- invalid breakpoint order fails clearly;
- units and references are checked;
- a minimal case can be constructed without JuMP.

### Iteration 2 — trusted AC baseline

Deliver:

- MATPOWER adapter;
- base-case AC OPF using JuMP and Ipopt;
- standardized state extraction;
- independent AC power-balance evaluator;
- base-case feasibility report.

Exit criteria:

- a small case solves from a clean environment;
- branch flows are recomputed outside the solver model;
- a deliberately perturbed result is detected as infeasible;
- all tolerances are visible in the report.

### Iteration 3 — exact and smooth droop curves

Deliver:

- exact PWL curve evaluator;
- ReLU-sum compilation;
- stable softplus evaluator;
- first and second derivatives;
- JuMP operator or equivalent smooth constraint encoding;
- dense-grid curve comparison tests.

Exit criteria:

- exact curve values match hand calculations;
- derivative tests pass;
- smoothing error is bounded and reported;
- deadband leakage and breakpoint proximity are measurable;
- epsilon is expressed in input units.

### Iteration 4 — multi-generator volt-var equilibrium

Deliver:

- one or more regulated voltage locations;
- two or three participating generators;
- reactive-power response with droop and deadband;
- scalar reference test with known response direction;
- saturation and active-power-dependent capability checks.

Exit criteria:

- low voltage causes positive network reactive injection;
- the voltage/reactive response satisfies the declared regulated location;
- generators saturate only when expected;
- exact curve replay passes the configured tolerance.

### Iteration 5 — one-contingency AC equilibrium

Deliver:

- scenario overlay;
- generator-outage or line-outage handling;
- base and contingency states;
- droop equations inside the AC model;
- scenario-indexed result extraction;
- independent contingency validation.

Exit criteria:

- the outage changes the solution as expected;
- unavailable devices are inactive;
- all AC residuals pass;
- all generator, voltage, and branch limits pass;
- the report distinguishes smooth feasibility from exact-curve feasibility.

### Iteration 6 — report, provenance, and reproducibility

Deliver:

- structured `Finding` type;
- `EquilibriumReport`;
- Markdown report;
- JSON result/report serialization;
- solver and model provenance;
- one documented end-to-end example.

Exit criteria:

- a new user can run the example;
- the report explains the result without solver-internal inspection;
- the same case reproduces from a clean project environment;
- the report identifies the binding contingency and control behavior.

### Iteration 7 — robustness before scale

Deliver:

- multiple initial points;
- epsilon continuation;
- near-breakpoint diagnostics;
- intentional infeasibility cases;
- multiple-contingency full enumeration;
- regression fixtures.

Exit criteria:

- failures are classified rather than silently accepted;
- different initial points produce comparable feasible solutions where expected;
- small epsilon does not overflow;
- every fixed bug has a regression test.

## 6. Prioritized backlog

### P0 — required for proof of concept

- P0-01: package skeleton and CI;
- P0-02: domain types for case, generator, control, curve, and contingency;
- P0-03: native case validation;
- P0-04: MATPOWER case adapter;
- P0-05: base AC OPF;
- P0-06: independent AC residual evaluator;
- P0-07: exact PWL response curve;
- P0-08: smooth softplus response curve;
- P0-09: multi-generator volt-var sharing test;
- P0-10: one-contingency scenario;
- P0-11: independent equilibrium validator;
- P0-12: structured report and end-to-end example.

### P1 — required for a useful research prototype

- P1-01: multiple contingencies;
- P1-02: preventive versus corrective modes;
- P1-03: epsilon continuation;
- P1-04: exact-versus-smooth curve replay;
- P1-05: result serialization;
- P1-06: multiple initial points;
- P1-07: PGLib-based base-case regression tests;
- P1-08: timing and memory measurements.

### P2 — scale-up

- P2-01: contingency ranking;
- P2-02: PTDF/LODF screening;
- P2-03: fast AC contingency evaluation;
- P2-04: constraint generation;
- P2-05: warm starts;
- P2-06: threaded contingency evaluation;
- P2-07: MadNLP backend;
- P2-08: ExaModels backend;
- P2-09: large GO Challenge benchmark;
- P2-10: distributed decomposition.

### P3 — broader model scope

- P3-01: frequency/active-power droop;
- P3-02: converter controls;
- P3-03: storage;
- P3-04: multi-period scenarios;
- P3-05: PSS/E and PowerSystems adapters;
- P3-06: island-specific frequency response;
- P3-07: dynamic initialization and small-signal validation.

## 7. Definition of ready

An issue is ready when it contains:

- a clear user or scientific need;
- the affected architectural layer;
- an acceptance test or measurable outcome;
- known assumptions and exclusions;
- a dependency list;
- a proposed validation strategy.

## 8. Definition of done

An implementation issue is done when:

- the smallest useful implementation exists;
- focused tests pass;
- the public behavior is documented;
- validation diagnostics are present;
- no solver-specific types leaked into the domain layer;
- the change does not modify unrelated behavior;
- benchmark impact is recorded when relevant;
- the issue and commit explain any intentional limitation.

## 9. Sprint working agreement

Each iteration should include:

1. backlog selection;
2. a short design note for risky work;
3. implementation in small vertical increments;
4. tests before broad refactoring;
5. an end-of-iteration runnable demonstration;
6. a review of new assumptions and diagnostics;
7. backlog reprioritization based on evidence.

The next two iterations should remain detailed. Later work should remain at epic level until the preceding slice exposes the real requirements.

## 10. Risk register

| Risk | Consequence | Mitigation |
|---|---|---|
| Droop sign convention is wrong | Physically reversed response | Hand-worked scalar tests and explicit conventions |
| Free slack masks voltage-control failure | False equilibrium | Require explicit regulated-location and Q-response checks |
| Smooth curve differs materially from exact curve | Misleading security result | Exact replay and smoothing-gap findings |
| AC model and validator share a bug | False confidence | Independent evaluator and differential tests |
| Tiny epsilon destabilizes NLP | Failed or unreliable solves | Continuation and per-curve scaling |
| Scenario copies exhaust memory | Poor SCOPF scaling | Immutable base plus overlays |
| Premature backend abstraction | Slow development | One reference backend first |
| Multiple AC equilibria | Non-repeatable results | Multiple starts and continuation |
| Solver status is over-trusted | Invalid results accepted | Separate solver, feasibility, and validation statuses |

## 11. Proof-of-concept acceptance test

The repository should contain one command or script that:

1. activates the project environment;
2. loads a small case;
3. attaches droop controls;
4. solves the base and one contingency;
5. replays the exact droop curves;
6. validates AC residuals and limits;
7. writes a Markdown report.

The test is not complete unless it also includes one deliberately invalid result or perturbation that the validator catches.

## 12. Scale-up gate

Do not begin P2 work until the following are true:

- the POC acceptance test is reproducible;
- exact and smoothed controls are both tested;
- the validator catches known errors;
- scenario results are stable and serializable;
- profiling identifies a real bottleneck;
- the public interfaces have been used from an example outside the implementation files.
