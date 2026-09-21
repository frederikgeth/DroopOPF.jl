# DroopOPF.jl Development Roadmap

Status: agile development plan with proof-of-concept priority.

Last updated: 2026-09-20

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
validated on this branch. M6 and M7.1-M7.3 are also complete; M8-M10 remain pending. These are not release promises. The [equipment plan](TRANSFORMER_SHUNT_PLAN.md) supplies
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
AVR remains a later milestone; supplied switched-bank modeling is now complete in M6. Order is unchanged.


**M6 complete on `transformers` (unreleased, 2026-09-19):** fixed bus shunts,
MATPOWER GS/BS import, explicit banks with immutable legal step-count states,
nominal/current states and availability. Independent current-based validation
checks signs, V-squared scaling and accounting. Fixed states are integrated in
OPF, preventive/corrective SCOPF and bounded droop design, including backend
agreement. Study schema v4 preserves banks and reads v1-v3 with migration.
See [M6 numerical report and plots](artifacts/m6/report.md) and
[fixed-shunt/import evidence](artifacts/m6_1/report.md). Next: S1 — Reliable optimization convergence and scaling, then M9.1 preventive equipment SCOPF. Full regression: **691/691 tests pass**. Milestone order is unchanged.


**M7.1 complete on `transformers` (unreleased, 2026-09-20):** explicit per-branch
tap policies, continuous base-case OPF, separate solved settings and physical
reconstruction. Phase shifts, shunts and droop curves remain fixed. Fixed-bound
equivalence, a 41-point ratio sweep, independent replay, multiple selected taps,
Ipopt/MadNLP agreement and result serialization are covered. See
[M7.1 numerical report and plots](artifacts/m7_1/report.md).
Full regression: **750/750 tests pass**. Optimized equipment SCOPF is explicitly reserved for M9.


**M7.2 complete on `transformers` (unreleased, 2026-09-20):** simple capacitor/reactor
banks with one nonzero step type, continuous B within the legal-count envelope,
and G tied to the same fractional count. Explicit selection, fixed-bound and
empty-policy equivalence, independent V-squared accounting, capacitor/reactor
sweeps, multiple simple banks, serialization and backend comparison are covered.
Taps and droops remain fixed. Full regression: **840/840 tests pass**. See [M7.2 report and plots](artifacts/m7_2/report.md).

**Post-scaling backlog:** heterogeneous-bank relaxation, multiple step types and
complex switching combinations. Revisit only after benchmarks demonstrate adequate
scaling of simple banks together with transformer and droop models. The existing
M6 support for supplied fixed heterogeneous states remains available. This backlog
is not a prerequisite for M7.3-M10 and is not a claim that scaling is already proven.


**M7.3 complete on `transformers` (unreleased, 2026-09-20):** one base-case joint
design entry point with independent tap, simple-bank and droop parameter policies,
separate solved settings, versioned JSON and independent physical/policy validation.
The eight fixed/free configurations use the same objective with zero design penalty.
Two-start comparisons retain attempts and parameter/objective spread; standalone
equivalence is checked with matched starts. References and independent deadband
widths reuse the M3 family and are additionally tested. See
[M7.3 evidence](artifacts/m7_3/report.md) and the
[M7 documentation results gallery](docs/src/equipment_optimization.md).
Full regression: **916/916 tests pass**. This completes the base-case M7 scope; coordinated equipment SCOPF is M9.


| Milestone | Small validation slices | Dependency / central evidence |
|---|---|---|
| M5 — Transformer reference physics **complete** | M5.1 data/import; M5.2 fixed ratio; M5.3 fixed phase/availability; M5.4 OPF/SCOPF integration | M1-M4 foundation; analytical currents/powers, flow curves, outages and round trips |
| M6 — Shunt reference physics **complete** | M6.1 fixed admittance **complete**; M6.2 supplied bank states **complete**; M6.3 OPF/SCOPF integration **complete** | Independent of M5; signs, V-squared curves and reactive accounting |
| M7 — Continuous equipment optimization **complete** | M7.1 tap ratio **complete**; M7.2 simple-bank susceptance **complete**; M7.3 joint equipment/droop **complete** | Applicable M5/M6 physics; fixed-bound equivalence, sweeps and setting extraction |
| **S1 — Reliable optimization convergence and scaling (active)** | S1.1 mathematical contract; S1.2 diagnostics; S1.3 control isolation; S1.4 conditioning; S1.5 initialization/solver comparison; S1.6 larger networks | M7; convergence and physical feasibility reported separately; public 118-bus then 300-bus cases |
| M8 — Steady-state transformer AVR **deferred** | M8.1 target plus saturation; M8.2 deadband/selection; M8.3 fixed/OPF/AVR comparisons | Can start after M5.4; voltage-target tracking, tap limits and explicit equilibrium-selection semantics |
| M9 — Equipment-aware SCOPF | M9.1 preventive sharing; M9.2 bounded corrective action; M9.3 AVR stages **deferred with M8** | M7; independent shared/corrective coupling checks. M8 is not a prerequisite for M9.1/M9.2 |
| M10 — Comparative validation gate | M10.1 external physics references; M10.2 matched studies; M10.3 regression/performance evidence | Applicable M5-M7/M9 capabilities; AVR comparisons deferred |

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

### S1 — Reliable optimization convergence and scaling (dedicated active milestone)

User decision (2026-09-20): defer M8 transformer AVR, M9.3 AVR response-stage
comparisons and heterogeneous/complex-bank optimization until the simple models
have demonstrated adequate scaling together. Preserve milestone IDs and existing
acceptance specifications; deferred capabilities are not prerequisites for the
current path. Current order is **S1 → M9.1 → M9.2 → S2/M10**.

S1 is a standalone milestone, rather than an incidental benchmark task. It does
not reopen the completed M7 feature scope or renumber M8-M10. The initial
synthetic runs are diagnostic evidence; the full S1 exit gate remains open. Detailed slices are in [the equipment plan](TRANSFORMER_SHUNT_PLAN.md#s1--reliable-optimization-convergence-and-scaling).

**Implementation update (2026-09-20):** The
[formulation contract](docs/src/joint_formulation.md), exact-Hessian correction
and iteration/KKT instrumentation are delivered. The original joint synthetic
stalls are resolved without changing equipment equations or the objective.
The [extended S1 study](artifacts/s1_extension/report.md) adds independent control
counts, both solvers, three starts, smoothing/staged/continuation probes, and
public 118-/300-bus networks with explicitly synthetic controls.

All **35/35 synthetic robustness attempts pass**. Both public fixed-equipment
baselines validate, but the initial public matrix passes only **13/30 attempts**.
Validated joint solutions exist at both sizes and loading levels; solver/start
reliability and objective/setting agreement remain insufficient. Smaller bound
pushes help; continuation and cross-solver polishing give mixed results.
Failures and numerical/physical distinctions are retained in tables and plots.
Current regression: **1551/1551 tests pass**; documentation builds successfully. These
software checks do not override failed public optimization attempts.

**S1 remains active; M9 is not unlocked.** Primal/dual experiments, bounded restart
execution, opt-in controller normalization, staged release and load continuation have now been tested (latest checkpoints below).
Next: isolate saturated-droop/active-Q-bound numerical dependence in a small reproducer, then test an equivalent numerical remedy before broader reliability studies.
The restart policy remains experimental. Isolated, warmed performance acceptance follows reliability. No equipment law, hidden objective penalty, operating bound or
physical-validation tolerance has changed.

**S1 exit-review backlog:** rationalize the test hierarchy after deciding which
experimental S1 capabilities are retained. Keep permanent physics, derivative,
default-behavior, formulation-equivalence, validation and serialization coverage;
move retained solver-policy, restart, staged-initialization and research-diagnostic
checks into an extended numerical suite where appropriate; remove tests only with
the abandoned implementation and documentation they cover. Provide a fast core
development target while retaining the full cross-milestone suite in CI unless
measured runtime or maintenance cost justifies a narrower gate. Test assertion
count alone is not a pruning criterion.

**Model-change rule:** tell the user before implementing any equipment-model
change, including a correction to its physical equations. Describe the proposed
equation change and its implications first. Preserve the baseline objective; no
silent regularization, extra penalties, relaxed limits or weaker physical
acceptance tolerances. Record numerical configurations separately from physics.

- **S1: joint base-case convergence/scaling milestone (in progress).** Increase network
  size and selected droop/tap/simple-bank counts separately. Separate construction,
  solver, extraction and independent-validation time; record model size, Julia
  allocations, carefully scoped process memory, solver status and all failed runs.
  Begin with connected synthetic stress cases, then pinned medium public networks
  with documented control overlays. Add load stress and multiple starting states.
  The [initial experiment](artifacts/scaling_initial/report.md) is a first sample,
  not evidence that this gate is complete. The [revised historical experiment](artifacts/scaling_robustness/decision.md) retains the pre-correction synthetic stalls. Exact Hessians resolved those stalls; the [public-case extension](artifacts/s1_extension/report.md) now defines the remaining reliability failures.
- **M9.1: preventive SCOPF.** Shared installed droop parameters and shared optimized
  tap/bank settings across all selected contingencies; fixed/free choices remain
  independent. Validate sharing and frozen equipment under outages.
- **M9.2: corrective SCOPF.** Explicit bounded equipment recourse, with independent
  policy checks. An outage alone never authorizes a tap or shunt movement.
- **S2/M10: security scaling and comparative evidence.** Increase contingency
  counts and device counts, retain held-out cases and failed scenarios, and profile
  bottlenecks. Add screening, sparse-assembly improvements or decomposition only
  when measurements justify them. Define hardware-specific practical size/runtime
  budgets from evidence rather than claiming universal scalability.

Feasibility means independently validated AC balances, exact droop response,
operating limits and equipment/response policies. Solver failure is not proof of
infeasibility; feasible witnesses, warm starts and stress sweeps help distinguish
model errors from numerical difficulties. Continuous feasibility is separate from
physical switch implementability. Optional legal-state recovery must re-solve and
validate all applicable cases; arbitrary rounding cannot establish implementability.


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


### S1 matched scaling and failure localization

The next checkpoint retains all 12 matched Ipopt scaling attempts on IEEE 118/300 at nominal and +5% demand; 7/12 validate. Default gradient scaling, disabled scaling and maximum-gradient-1 scaling share the same primal starts, bounds, smoothing, objective and budgets. These are solver-internal scaling probes, not implementation of explicit variable normalization. No setting is promoted as a universal default.

Physical-failure diagnostics now identify equipment ID, quantity/terminal, violation, tolerance and exceedance in physical per-unit values. A separate audit of all 30 original public attempts agrees with the existing validator's failure categories; historical solver evidence is preserved. Tables and plots are in [the scaling checkpoint](docs/src/s1_scaling.md). Primal/dual warm starts, variable normalization, declared restart/selection policy and reliability across starts remain open before M9. Equipment equations and acceptance tolerances are unchanged.

Validation for this checkpoint: **1238/1238 regression tests pass**, including localized failure/category agreement, and the documentation build passes. S1 remains open; these checks do not convert rejected optimization attempts into validated designs.


### S1 primal/dual restart checkpoint (2026-09-21)

The same-formulation Ipopt restart matrix validates **9/16 attempts**, including four source runs. Saved multipliers preserve all three validated sources (3, 3 and 55 restart iterations), but fail to recover the stalled stressed IEEE 300 source. Zero-dual warm initialization recovers that case in 1000+40 iterations; ordinary primal restart needs 1000+491. An uninterrupted equal-budget 2000-iteration/120-CPU-second solve still fails physical validation. This supports further testing of status-dependent restarts, not a universal warm-start default.

Seeds retain primal values and nonlinear/bound multipliers with model-layout/context checks, finite-value rejection and explicit provenance. Failed sources are numerical seeds only. Candidate selection uses the lowest objective among fully validated outcomes and keeps unresolved groups explicit. All failures, tables, iteration and stationarity plots are in [the restart checkpoint](docs/src/s1_warmstarts.md). **1270/1270 regression tests pass.** Equipment equations, objective and physical tolerances remain unchanged.

S1 remains open: explicit variable normalization, broader start/placement/stress variation, and validation of an automatic restart policy are still required before M9. Primal/dual preservation is demonstrated for identical Ipopt formulations only; cross-scenario, cross-solver and changed-smoothing transfer remain unimplemented.


### S1 bounded restart policy checkpoint (2026-09-21)

The experimental runner now accepts the first independently validated result, permits at most one multiplier-reset recovery after selected numerical failures, and shares a 2000-iteration/120-second cooperative wall budget across attempts. It stops converged-but-invalid results for diagnosis and rejects incompatible/nonfinite seeds. It never silently switches solvers, changes smoothing or relaxes physical requirements. Context hashes include physical data, control policies, smoothing and backend/version.

Across IEEE 118/300, nominal/+5% demand and three declared starts, **Ipopt improves from 7/12 to 8/12 validated cases** (17 attempts); **MadNLP changes from 4/12 to 4/12** (19 attempts). The backend adapters differ: Ipopt resets constraint/bound starts through its warm initializer; MadNLP resets constraint multipliers while using native bound initialization. No iteration budgets were exceeded; observed cooperative wall overruns: Ipopt 0, MadNLP 0.

The [policy report](docs/src/s1_restart_policy.md) retains every attempt, physical failure category, seed and decision, with acceptance/matrix figures. **1306/1306 regression tests pass**, including native MadNLP initialization, deadline interruption, seed rejection and cumulative-budget tests. The policy is implemented and tested experimentally, but the public reliability gate remains unmet. S1 stays open before M9; equivalent variable normalization and broader reliability/solution-quality studies remain next. Equipment equations, objective and validation thresholds are unchanged.


### S1 controller normalization checkpoint (2026-09-21)

Opt-in affine normalization of free droop parameters, tap ratios and bank susceptances is implemented and verified: `control_normalization=:bounds` maps each finite free interval to [0,1], while `:none` remains the default. Physical settings, equations, objective, limits and validation tolerances are unchanged. Fixed intervals bypass normalization. Tests verify pointwise equations/objectives, Jacobian/Hessian chain rules, capacitor/reactor handling and physical result serialization.

The frozen 24-case policy benchmark is retained with SHA-256 evidence. Normalization validates **7/12 Ipopt cases versus 8/12 previously**, and **1/12 MadNLP cases versus 4/12**. It gains some starts and loses others, so it is not promoted as a reliability improvement. All 42 normalized attempts, failures, coordinate maps and paired objectives are retained.

A separate six-attempt smoothing study targets converged outcomes that fail only exact-droop validation and have recomputed smooth-droop residual at most 1e-6 pu. Reducing epsilon from 1e-6 to 1e-7, with one extra declared solve, validates **2/6**; four still fail numerically. These extra attempts do not alter the frozen acceptance counts. The [normalization report](docs/src/s1_normalization.md) separates optimization residuals from approximation gaps. **1419/1419 regression tests pass.**

S1 remains open. Next: staged initialization/load continuation under an explicitly shared budget, then broader load/placement tests outside the tuning matrix once a workflow improves reliability. Physical-coordinate default and existing bounded restart policy remain unchanged; no automatic smoothing adaptation has been promoted. Residual normalization is still unimplemented.


### S1 staged initialization checkpoint (2026-09-21)

Two independent experimental workflows now compose existing solves: fixed settings → free taps/banks → full joint design, and nominal → +2.5% → +5% demand. Each workflow shares a 2000-iteration/120-second cooperative wall budget across preparation and final solves. Only independently validated preparation stages inside the strict initialization domain provide physical primal seeds. Restricted-stage feasible points are retained separately and never count as final joint-design convergence.

The frozen IEEE 118/300 comparison contains **36 workflows and 127 solve attempts**, including every failed stage. Control release validates **7/12 Ipopt cases versus 8/12 direct**, and **3/12 MadNLP cases versus 4/12 direct**. Load continuation validates **3/6 Ipopt stressed cases versus 4/6 direct**, and **2/6 MadNLP cases versus 3/6 direct**. Across both strategies, 16/72 preparation stages supply accepted seeds. Observed cumulative iteration/wall overruns: 0/0. Timing includes compilation and concurrent work; it is not an isolated performance comparison.

The [staged report](docs/src/s1_staged.md) provides paired acceptance/objective tables, stage outcome plots, seed lineage and physical failure details. **1456/1456 regression tests pass.** Neither workflow is promoted to a default: gains on individual starts coexist with regressions. Equipment models, physical coordinates, objective and physical validation tolerances remain unchanged.

**S1 remains open before M9.** Next, use the retained failed cases to isolate residual scaling and stationarity/active-bound behavior before expanding the benchmark. Any equivalent numerical treatment needs equation/derivative checks and a paired comparison; broader load/placement holdouts follow a demonstrated reliability improvement. No additional equipment model is introduced.


### S1 stationarity and active-bound checkpoint (2026-09-21)

A read-only diagnostic reconstructs original-coordinate objective, nonlinear-constraint and bound contributions to the Lagrangian gradient, plus complementarity, dual-sign errors and Jacobian row/column magnitudes. Ten declared IEEE 118/300 runs across Ipopt and MadNLP reproduce the frozen direct first-attempt status, acceptance and objective exactly. No optimizer formulation or physical acceptance rule changes.

Stalled Ipopt cases retain free-coordinate stationarity residuals of roughly 0.06–0.4, compared with 1e-12–1e-10 in the selected accepted cases. The geometry audit also identifies saturated-droop rows numerically parallel to active Q bounds on both backends. Some accepted MadNLP points carry opposing droop/bound multipliers around 1e14–1e15; raw stationarity is cancellation-sensitive while native multiplier-scaled termination measures remain small. This is a solution-quality issue to investigate, not a retroactive change to physical validation or proof that every stall has the same cause.

The [diagnostic report](docs/src/s1_kkt.md) includes physical KKT decompositions, equation-scale plots, individual failure locations and saturated-controller geometry. Hypothetical row equilibration is evaluated only; it is not applied to solves. Scaling parallel rows cannot restore independence, and scaled stopping tolerances require explicit conversion to physical residuals. **1502/1502 tests pass.**

**S1 remains open. Next:** build a small reproducer for saturated droops at active reactive-power bounds, compare multiplier behavior and stopping rules, then evaluate an explicitly equivalent numerical remedy. Equipment-model changes still require telling the user beforehand. Broad holdout/scalability validation follows a demonstrated improvement; M9 remains blocked by the reliability gate.

### S1 saturated-droop reproducer and implied-bound checkpoint (2026-09-21)

A two-variable reproducer now isolates the saturated droop equality and generator-Q bound. At either saturation end, the droop row and active bound both have direction `[0, 1]`, and their stacked Jacobian has a zero singular value. Both Ipopt and MadNLP reproduce this dependence. The deadband case remains well behaved because the parallel Q bound is inactive.

An opt-in `droop_q_bounds=:implied` formulation omits only generator-Q bounds that are implied in exact arithmetic by the bounded smoothed droop response and the validated nesting of control capability inside generator limits. It retains `qg`, AC balances, droop equalities, objective, smoothing, settings and independent physical validation. The original `:explicit` formulation remains the default. Floating-point cancellation can move the response about 1e-15 beyond an endpoint; tests bound this effect and the unchanged 1e-6 physical validator still checks every returned Q value.

On the frozen matrix, implied bounds validate **7/12 Ipopt cases versus 8/12 explicit** and **3/12 MadNLP cases versus 4/12 explicit**. MadNLP gains all three nominal IEEE 118 starts but loses four previously accepted stressed/larger cases; Ipopt loses one stressed anchor. Accepted objectives also show different local solutions on some IEEE 300 cases. The [paired report](docs/src/s1_implied_q.md) retains all 42 attempts, objectives, failure decisions and the reproducer evidence. **1529/1529 tests pass.**

**Decision:** keep implied bounds experimental. The local dependence is real but does not explain all convergence failures. S1 stays open and M9 remains gated. Next, evaluate a reduced-space substitution or a smooth saturation representation that preserves explicit physical limits without a flat equality row; derive and test endpoint, derivative and objective equivalence before another public comparison.

### S1 reduced-space droop-Q checkpoint (2026-09-21)

An opt-in `droop_q_formulation=:reduced` now substitutes each attached
generator's smoothed droop response directly into reactive balance and the
reactive objective. It reconstructs Q in the returned operating point and keeps
the independent validator unchanged. Structural and two-solver small-case tests
verify the variable/equality removal and agreement of objective, voltage,
reactive output, tap and shunt results. The explicit formulation remains the
default.

The reduced model removes 37 variables and 111 reported JuMP constraints on
IEEE 118, and 35 variables and 105 constraints on IEEE 300. On the frozen public
matrix it validates **4/12 Ipopt cases versus 8/12 explicit**, and **8/12 MadNLP
cases versus 4/12 explicit**. MadNLP gains five cases but loses one prior stressed
IEEE 300 success; Ipopt loses four prior successes. The [paired report](docs/src/s1_reduced_q.md)
retains every attempt, physical failure and objective comparison.
The full regression suite passes **1551/1551 tests**.

**Decision:** keep reduced space experimental. Its MadNLP benefit confirms that
the explicit droop-Q row affects numerical behavior, but the backend-dependent
regressions fail the no-loss reliability gate. S1 remains open and M9 remains
gated. Next, test an alternative smooth-saturation or targeted equality treatment
on the minimal reproducer and frozen matrix before expanding to holdout cases.
