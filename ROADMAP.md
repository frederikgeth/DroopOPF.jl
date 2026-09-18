# DroopOPF.jl Development Roadmap

Status: agile development plan with proof-of-concept priority.

Last updated: 2026-09-18

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

## 4. Current milestone plan

The milestone names below match the README. The original alpha/beta version
numbers were planning targets, not releases; M1 was actually released as 0.1.0.

### M1 — AC OPF with fixed volt-var curves (released in 0.1.0)

Typed case data, MATPOWER loading, AC OPF, exact/smooth droop encodings,
independent equilibrium validation, solver comparison, and plotting.

### M2 — security-constrained AC OPF (released in 0.2.0)

The implementation contract is in [docs/src/scopf.md](docs/src/scopf.md).
The validation-sized steps are:

1. Preserve M1: an empty contingency set reproduces its objective and dispatch.
2. Validate outage overlays: known IDs, unchanged input, zero unavailable-device
   output/flows, and explicit rejection of islanding.
3. Couple one line-outage equilibrium to base dispatch using an explicit response policy.
4. Add generator outages with inactive droop and normalized surviving participation.
5. Enumerate multiple scenarios with preventive or bounded corrective response.
6. Independently validate physical residuals, exact/encoded droop, limits, and
   response coupling; reject deliberate perturbations and infeasible policies.
7. Reproduce an end-to-end workflow with JSON study/result round trips,
   Markdown/JSON reports, warm starts, and smoothing continuation.

Acceptance includes a constrained case where security changes base dispatch,
not merely independently feasible scenario solves. Run
`julia --project=. examples/m2_workflow.jl` for the reproducible workflow.

### M3 — optimize droop curves (released in 0.3.0)

Start with one bounded droop parameter and validate against a small parameter
sweep. Fixing that parameter must reproduce M2. Add reference settings, deadbands,
and generalized curves incrementally, with exact replay and held-out scenarios.

The first slice is a reference-anchored fixed-slope sweep. It
reuses the complete M2 SCOPF, warm-starts neighbouring candidates, independently
validates every candidate, and writes versioned JSON plus an SVG trade-off plot.
The completed bounded-design slice promotes slope, voltage reference, and
independent lower/upper deadband widths to variables shared across all training
scenarios. Fixed bounds reproduce M2, continuous slope optimization agrees with
the sweep, optimized states replay against reconstructed exact PWL curves, and
an excluded line outage provides the held-out acceptance gate. Versioned design
JSON and a numerical/visual validation bundle make the workflow reproducible.

M3 deliberately retains the standard saturated volt-var family and fixed
reactive capability. Arbitrary free-knot PWL topology optimization is deferred;
it requires a separate identifiability and regularization contract rather than
an implicit expansion of this milestone.

### M4 — robustness and benchmark gate (released in 0.4.0)

M4 should establish whether the validated small-system workflow is repeatable,
diagnostically useful, and ready to scale. It is not a scale-up milestone.

Deliver:

1. systematic multi-start M2/M3 experiments with recorded initial-point,
   feasibility, objective, and parameter spread;
2. per-scenario distance-to-breakpoint diagnostics for every active droop
   control, including an explicit near-breakpoint classification;
3. structured findings for solver failure, validation failure, binding limits,
   critical contingencies, and sensitive control behaviour;
4. small public PGLib regression cases exercised through the normal adapter,
   solver, serialization, and independent-validation workflow;
5. reproducible timing, model-size, and memory measurements for the reference
   cases and full-enumeration SCOPF;
6. a written scale-up decision identifying the measured bottleneck and whether
   any P2 algorithm is justified.

Acceptance requires:

- repeated starts either produce comparable independently valid solutions or
  classify the disagreement without silently selecting one result;
- reports identify binding limits, the critical contingency, and operating
  points close to droop breakpoints;
- at least two public small cases run from a clean environment and retain
  machine-readable provenance;
- benchmark output records Julia, package, solver, model-size, time, and memory
  information;
- the scale-up decision cites measurements rather than assumed bottlenecks.

M4 does not include PTDF/LODF screening, constraint generation, parallelism,
ExaModels, or distributed decomposition. Those remain behind the scale-up gate.

Implemented: named M2 state multi-start runs preserve every solver
result and independent report, classify valid objective agreement, and emit
versioned JSON/Markdown. Structured diagnostics now report per-control nearest
breakpoint distance, device-level near-binding limits, validation/solver
failures, and the minimum-margin contingency. Named M3 runs now vary the actual
design-variable starts and report both objective and final parameter spread.
Two pinned public PGLib cases now exercise the adapter, solve, serialization,
and independent validation path with machine-readable provenance. Reproducible
benchmarks record environment, actual JuMP model size, elapsed time, and Julia
allocations. The evidence-based decision is to retain the current formulation:
no P2 scaling algorithm is justified by the validated small-case measurements.

### Equipment extension — revised continuous-first plan

M1-M4 remain released and unchanged. The following M5-M10 milestones record the
agreed planning direction on branch `transformers`; M5.1-M5.4 are implemented and
validated on this branch, while M6-M10 remain pending. These are not release promises. The [equipment plan](TRANSFORMER_SHUNT_PLAN.md) supplies
small validation slices and acceptance evidence. This roadmap owns sequencing.

**M5 complete on `transformers` (unreleased, 2026-09-18):** transformer
data/import/schema migration (M5.1), fixed-ratio physics (M5.2), fixed phase shift,
availability and both-terminal ratings (M5.3), and OPF/SCOPF plus bounded-droop
integration (M5.4). Independent validation computes internal-side currents;
the optimizer uses the admittance primitive. The full suite passed 440/440
tests. See the [M5 evidence report](artifacts/m5/report.md) and
[M5.1 data report](artifacts/m5_1/report.md).

The synthetic integration fixture uses declared proportional-regime starts and
explicit CCOpt accuracy settings. Failed flat-start/default-CCOpt diagnostics
are retained; convergence from arbitrary starts is not claimed. Tap optimization,
AVR and shunt physics remain in their existing later milestones. Order is unchanged.


| Milestone | Small validation slices | Dependency / central evidence |
|---|---|---|
| M5 — Transformer reference physics **complete** | M5.1 data/import; M5.2 fixed ratio; M5.3 fixed phase/availability; M5.4 OPF/SCOPF integration | M1-M4 foundation; analytical currents/powers, flow curves, outages and round trips |
| M6 — Shunt reference physics | M6.1 fixed admittance; M6.2 supplied bank states; M6.3 OPF/SCOPF integration | Independent of M5; signs, V-squared curves and reactive accounting |
| M7 — Continuous equipment optimization | M7.1 tap ratio; M7.2 susceptance; M7.3 joint equipment/droop | Applicable M5/M6 physics; fixed-bound equivalence, sweeps and setting extraction |
| M8 — Steady-state transformer AVR | M8.1 target plus saturation; M8.2 deadband/selection; M8.3 fixed/OPF/AVR comparisons | Can start after M5.4; voltage-target tracking, tap limits and explicit equilibrium-selection semantics |
| M9 — Equipment/AVR-aware SCOPF | M9.1 preventive sharing; M9.2 bounded corrective action; M9.3 before-response versus AVR-settled security | M7 and, for AVR cases, M8; independent coupling and stage-specific margin checks |
| M10 — Comparative validation gate | M10.1 external physics references; M10.2 matched studies; M10.3 regression/performance evidence | M5-M9; held-out conditions, interactions, multi-starts and reproducible reports |

Continuous tap-ratio and shunt-susceptance relaxation is the primary optimization
path. Discrete physical position data and fixed operation remain first-class.
Small enumeration, legal-position recovery and mixed-integer optimization are
optional verification/solution branches, not prerequisites for the primary path.
Relaxed outputs are labelled explicitly; recovery requires a new physical solve,
including all selected security cases. A local relaxed objective is not a
certified lower bound on the discrete problem.

Fixed transformers/shunts are present in existing SCOPF from M5.4/M6.3 onward.
M9 adds coordinated decisions and response policies, not a second SCOPF engine.
Transformer mode is fixed, OPF-optimized or AVR-controlled. AVR equilibrium,
including limit saturation, is distinct from unrestricted tap optimization.
Deadband feasibility alone does not establish a reached position or action count.

Each submilestone requires a runnable example, machine-readable evidence, a
readable report and the specified plots/tables. Separate solver, physics,
operational-limit and control-policy statuses. Report AVR unmet targets explicitly.
Numerical checks and adversarial tests determine acceptance; visuals explain it.
M10 consolidates existing evidence rather than postponing validation.

Maintain data / optimization problem / formulation / validation boundaries.
M5 and M6 can proceed independently; M8 can branch from M5 while M7 progresses.
Sequential automatic delays, dwell, hunting and discrete event counts are later
scope; M9.3 compares two steady states and makes no transient-security claim.
The original performance gate and released milestone identities remain unchanged.

### Later scaling target

Contingency ranking, fast AC evaluation, violation-driven constraint generation,
warm starts at scale, parallel evaluation, and benchmark-driven performance
tuning. Begin only after M4 and the scale-up gate below identify a real need.
Basic warm starts and the MadNLP backend already exist; their performance at
scale is not yet established.

### Stable research API target (v1.0.0)

Require a versioned data model, backward-compatible results, reproducible public
reference cases, documented assumptions, at least one large public benchmark
family, and independent validation in the normal workflow.

## 5. Agile iterations

The iterations below retain the original implementation breakdown; they are not
additional numbered milestones. The current milestone/status authority is section 4.

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

Status terms below are authoritative for the current implementation:

- **complete** — implemented, tested, and documented;
- **partial** — a useful slice exists but the stated backlog outcome is not met;
- **pending** — not implemented;
- **deferred** — intentionally outside the current milestone sequence.

### P0 — required for proof of concept

- **complete** — P0-01: package skeleton and CI;
- **complete** — P0-02: domain types for case, generator, control, curve, and contingency;
- **complete** — P0-03: native case validation;
- **complete** — P0-04: MATPOWER case adapter;
- **complete** — P0-05: base AC OPF;
- **complete** — P0-06: independent AC residual evaluator;
- **complete** — P0-07: exact PWL response curve;
- **complete** — P0-08: smooth softplus response curve;
- **complete** — P0-09: multi-generator volt-var sharing test;
- **complete** — P0-10: one-contingency scenario;
- **complete** — P0-11: independent equilibrium validator;
- **complete** — P0-12: validation reports and end-to-end examples.

### P1 — required for a useful research prototype

- **complete** — P1-01: multiple contingencies;
- **complete** — P1-02: preventive versus corrective modes;
- **complete** — P1-03: epsilon continuation;
- **complete** — P1-04: exact-versus-smooth curve replay;
- **complete** — P1-05: versioned result serialization;
- **complete** — P1-06: systematic named M2 state and M3 design-parameter starts
  retain their inputs, solver outputs, independent reports, objective
  classification, and parameter spread;
- **complete** — P1-07: two pinned PGLib-OPF v23.07 cases exercise the normal
  adapter, solver, serialization, and independent-validation path;
- **complete** — P1-08: reproducible measurements record environment, actual
  JuMP model size, elapsed time, Julia allocations, objective, and validity.

### P2 — scale-up

- **pending** — P2-01: contingency ranking;
- **pending** — P2-02: PTDF/LODF screening;
- **pending** — P2-03: benchmark-driven fast AC contingency evaluation;
- **pending** — P2-04: violation-driven constraint generation;
- **partial** — P2-05: scenario and neighbouring-design warm starts exist,
  but effectiveness at scale has not been measured;
- **pending** — P2-06: threaded contingency evaluation;
- **complete** — P2-07: MadNLP backend with M1–M3 compatibility tests and a
  documented validated-warm-start requirement for the M2/M3 fixture;
- **pending** — P2-08: ExaModels backend;
- **pending** — P2-09: large GO Challenge benchmark;
- **pending** — P2-10: distributed decomposition.

### P3 — broader model scope

- **deferred** — P3-01: frequency/active-power droop;
- **deferred** — P3-02: converter controls;
- **deferred** — P3-03: storage;
- **deferred** — P3-04: multi-period scenarios;
- **deferred** — P3-05: PSS/E and PowerSystems adapters;
- **deferred** — P3-06: island-specific frequency response;
- **deferred** — P3-07: dynamic initialization and small-signal validation.

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

Current status: **closed without passage to P2**. M4 supplied reproducible
profiling and public small-case evidence, but found no bottleneck at the
validated scale. The correct decision is therefore to retain full enumeration
and the existing JuMP formulation rather than pre-emptively add a scaling
algorithm.

Do not begin the remaining P2 scale-up algorithms until the following are true:

- the POC acceptance test is reproducible;
- exact and smoothed controls are both tested;
- the validator catches known errors;
- scenario results are stable and serializable;
- profiling identifies a real bottleneck;
- the public interfaces have been used from an example outside the implementation files.
