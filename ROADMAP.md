# DroopOPF.jl Development Roadmap

Status: agile development plan with proof-of-concept priority.

Last updated: 2026-10-19

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

The maintained deferred-capability register is
[docs/src/future_work.md](docs/src/future_work.md). It covers dynamic security,
multi-island operation, production-filter qualification, discrete equipment,
scale, adapters, and optimization guarantees without duplicating those lists
across roadmap and milestone files.

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

M4 did not include PTDF/LODF screening, constraint generation, parallelism,
ExaModels, or distributed decomposition. Subsequent P2 status is recorded below.

Implemented: named M2 state multi-start runs preserve every solver
result and independent report, classify valid objective agreement, and emit
versioned JSON/Markdown. Structured diagnostics now report per-control nearest
breakpoint distance, device-level near-binding limits, validation/solver
failures, and the minimum-margin contingency. Named M3 runs now vary the actual
design-variable starts and report both objective and final parameter spread.
Two pinned public PGLib cases now exercise the adapter, solve, serialization,
and independent validation path with machine-readable provenance. Reproducible
benchmarks record environment, actual JuMP model size, elapsed time, and Julia
allocations. At the M4 checkpoint, those small-case measurements did not justify
a new P2 scaling algorithm. Later sparse-balance and threaded evidence is
recorded in the current P2 ledger.

### Equipment extension — revised continuous-first plan

M1-M4 remain released and unchanged. The following M5-M10 milestones record the
agreed planning direction. M5–M9 are released, the bounded initial S2 public
qualification gate is complete, and broader S2 and screening-reliability work remains.
These are not future release promises. The [equipment plan](TRANSFORMER_SHUNT_PLAN.md) supplies
small validation slices and acceptance evidence. This roadmap owns sequencing.

The separate [500-bus S2 investigation](docs/src/s2_500bus.md) has completed its
bounded campaigns: MadNLP and Ipopt qualify all 389 connected outages at nominal demand;
both also qualify independent 90% and 95% designs,
while the required 110%/G60 case has an independently verified rational
infeasibility certificate that survives numerical acceptance tolerances.
The five-demand target cannot be accepted under the original normal-limit, full-demand bounds; CCOpt
and full-N-1 gates remain unqualified. Overall 500-bus S2 stays open; the
approved emergency/relief policy retains separate acceptance gates. S1 and the declared sampled
14-bus S2 scope remain closed.

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
| **S1 — Reliable optimization convergence and scaling (closed)** | S1.1 mathematical contract; S1.2 diagnostics; S1.3 control isolation; S1.4 conditioning; S1.5 initialization/solver comparison; S1.6 larger networks | M7; convergence and physical feasibility reported separately; current public sequence: ARPA-E IEEE 14-bus, then 500-bus if the small case reproduces |
| M9 — Equipment-aware SCOPF **released in v0.9.0** | M9.1 policy layer, M9.2 recourse budgets and M9.3 paired response stages implemented and synthetically validated | Shared automatic reactive assignments, preventive sharing, explicit bounded corrective movement and independent scenario replay |
| M10 — Contingency assessment and comparative evidence complete for declared scope | Catalog, evaluation, ranking, screening and resumable campaigns implemented; M10.1 sourced equation-reference physics complete for declared scope; M10.2 matched comparisons complete for declared synthetic scope (one certified negative comparator); M10.3 reproducibility/performance closeout complete with 3,042/3,042 regression assertions | [Implementation and evidence audit](docs/src/m10_audit.md); generator AVR included in bounded M10.2; transformer AVR remains outside scope |

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

### S1 — Reliable optimization convergence and scaling (closed)

The 2026-10-15 closeout uses the ARPA-E 14/500-bus sequence. It supersedes the earlier public-network acceptance sequence. The supported study contract is Pmin=0, symmetric Q limits, zero deadband, continuous taps/banks, five sampled demand levels and OPF-derived starts. Qualification records successful native termination plus independent AC, exact-droop and operating-policy checks. Failures and bounded recoveries remain part of the evidence. Serial warmed performance measurements and test-suite classification complete the closeout. See [S1 closeout](docs/src/s1_closeout.md).

Original-Q-limit frozen-equipment compatibility, unseen demands, dynamics and security qualification remain outside this closed scope. The separate native S2 14-bus nominal-demand study now qualifies all 24 connected eligible outages, with nine accepted solver runs and 157 independently replayed states. One islanding outage remains excluded; see [S2 coverage](docs/src/s2_14bus.md). Released implementation milestone identities are unchanged.

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

**Classification update (2026-10-22):** independently certified infeasible
requirements count as completed negative P2 tests under their declared scope.
The PGLib 14/39-bus capacity-excluded requirements need no further same-scope
recovery. Feasible-case scaling and unresolved numerical outcomes remain separate
qualification work; see the [case identity and classification clarification](docs/src/p2_corrective_reassessment.md#test-classification-clarification--22-october-2026).

**Corrective reassessment (2026-10-21):** bounded corrective equipment and
demand-specific preventive scheduling are now authorized; see
[the corrective reassessment](docs/src/p2_corrective_reassessment.md). Public
capacity exclusions still apply; P2 and the release gate remain open.

**Earlier same-day policy comparison:** preventive active response is limit-aware,
with effective-capability-range default weights. The authorized [staged control
comparison](docs/src/p2_preventive_controls.md) retains a fixed baseline, then
allows shared droop design and shared preventive equipment settings. Curves and
equipment freeze for held-out evaluation; post-outage equipment movement stays
zero. All three fixture configurations pass their sampled demands/outages,
including a legal-bank/supplied-tap recovery. Rational cut bounds exclude the
public 14/39-bus declared training requirements even with these freedoms.
Historical P2 screening and performance measurements retain their original
policy; broader new-policy qualification and the release gate remain open.

The 500-bus P2 benchmark now uses [the exact S2 data and control policy](docs/src/p2_s2_500.md).
Its input/configuration preflight passes. [Fresh S1/S2 implementation](docs/src/p2_s2_implementation.md)
passes the 14-bus full/progressive comparison and the 500-bus 105% feasibility
pilot with all 389 connected outages. [The multi-demand continuation](docs/src/p2_s2_multidemand.md)
qualifies shared 90/95/100/105% with zero shedding and shared
90/95/100/105/106.25% with S2 relief, all 389 outages per demand. [The remaining qualification campaign](docs/src/p2_remaining_qualification.md)
passes four held-out demands on each network and three fresh exhaustive 500-bus
passes with documented native-error recovery. Paired design references pass but
show no general progressive speed advantage. Pure flat initialization remains
unqualified on 500 buses; explicit base recovery passes. Broader predictive
and exhaustive resource-objective qualification remain open. Former P2-specific
large-case results are retired.
The [recovery follow-up](docs/src/p2_resolution.md) retains synthetic 60/84-bus
screening evidence and public diagnostics for the remaining cases.

The 2026-10-19 completion attempt and the twelve-step qualification ledger are
recorded in `docs/src/p2_completion.md` and `artifacts/p2_completion/REPORT.md`.
Fixed supplied equipment, frozen shared droop and preventive equal active weights
were that historical campaign contract. S2 was excluded. Implementation is not equivalent to
public-network or release qualification.

- **implemented; predictive qualification limited** — P2-01: deterministic family
  and combined ranking, with public-network recall-versus-budget measurements;
- **bounded qualification complete; general scope open** — P2-02: opt-in response
  guard. The prior six 48/96-bus cases cover 552 outages, 148 screens and zero
  misses, with 114 unresolved outcomes. Earlier four rejected anchors remain
  coverage gaps. Public-network evaluation is retained in the completion ledger.
  Default remains off; final security acceptance requires exhaustive AC audit;
- **implemented; bounded throughput evidence** — P2-03: sparse balances and
  resumable campaigns. Latest synthetic warm timing improves from 156.60 to 21.39
  seconds for exhaustive assessment; this is not a universal speedup guarantee;
- **implemented reference; scale qualification limited** — P2-04: scenario
  addition with exhaustive final audit and fixed-control comparisons against full
  enumeration. Failed masters remain failures, not accepted designs;
- **implemented; measured policies** — P2-05: flat, base and previously validated
  neighbouring scenario starts. Numerical initialization does not change the
  preventive dispatch or frozen equipment/controller policy;
- **implemented; bounded threaded pipeline** — P2-06: independent model building,
  serialized native Ipopt calls, deterministic coordinator checkpoints and bounded
  active models. One worker remains the default; no unrestricted solver parallelism;
- **complete** — P2-07: MadNLP backend with compatibility tests and documented
  validated-warm-start requirements;
- **conditional; not implemented** — P2-08: ExaModels. Reconsider after a qualified
  large case isolates a bottleneck that sparse JuMP cannot meet;
- **implemented; bounded multi-demand qualification passed** — P2-09: exact S2 500-bus input and control
  contract, including corrective equipment and declared emergency/relief policy;
  fresh bounded S1/S2 runs are recorded separately; broader scaling qualification remains open;
- **conditional; not implemented** — P2-10: distributed decomposition. Requires
  evidence of a centralized bottleneck and a valid comparison baseline.

The 2026-10-22 local Julia 1.10/1.12 suites each pass 3,147 checks; remote Ubuntu
CI remains separate. The [fresh gate ledger](artifacts/p2_remaining_qualification_20261022/REPORT.md)
retains native failures, six corruption checks and bounded optimization scope.

P2 and the stable research release gate are not closed merely by completing the
implementation/tests. See the completion ledger for actual outcomes and remaining
public-network qualification requirements.

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

Historical M4 status: **closed without passage to P2 at that checkpoint**.
Subsequent profiling justified sparse balances and the bounded threaded campaign
pipeline. The 2026-10-19 P2 completion ledger records their actual qualification
scope; the stable research release and large public-network gates remain open.

For further conditional backends or distributed algorithms, require:

- the POC acceptance test is reproducible;
- exact and smoothed controls are both tested;
- the validator catches known errors;
- scenario results are stable and serializable;
- profiling identifies a real bottleneck;
- the public interfaces have been used from an example outside the implementation files.


The subsequent confirmed 500-bus emergency/loadability investigation changes N−1 operating allowances, not equipment capabilities. It establishes sampled critical-outage shared-controller feasibility through 110%, necessary infeasible upper samples, and explicit island relief-budget obstructions. Exhaustive 110% connected coverage is 387/389; bounded preventive-dispatch recovery is retained in the follow-up artifacts. Full 500-bus S2 remains open, and no physical remedies are investigated in this scope.


The 500-bus electrical network-reduction follow-up now tests exact 377- and 430-bus voltage models with every original rating and voltage/angle constraint retained through reconstruction. The sparse 430-bus 105% expanded master passes native convergence and full-network validation. Bounded fixed-controller and free shared-design retries do not recover the 110% expanded master. Reduction and equivalent auxiliary cleanup are reported separately; full 500-bus S2 remains open. See the network-reduction section of the [500-bus report](docs/src/s2_500bus.md).

The subsequent [continuation and response-policy follow-up](docs/src/s2_500bus.md#demand-continuation-and-response-policy-diagnostics) uses the accepted 105% expanded master as its start. It retains all original physical constraints and confirmed corrective equipment bounds, diagnoses proportional-response coupling separately, and requires a fresh zero-relaxation model for recovery. The campaign report records the accepted demand frontier, exact/diagnostic solver outcomes and original 500-bus checks. Exhaustive connected-outage qualification and a shared five-demand optimum remain separate gates.

The [free-droop follow-up](docs/src/s2_500bus.md#free-droop-continuation-with-exact-active-response) releases the 51 slopes and references with the active-response rule kept exact. Its bounded recovery uses equivalent droop-only scaling and the accepted demand anchor. Reports distinguish native physical feasibility, resource-polishing outcomes and a separately validated DR-first allocation witness; all original equipment limits and full-network acceptance gates remain enforced. Five-demand and exhaustive connected-outage qualification remain explicit conditional gates.

The [solver and independent-demand campaign](docs/src/s2_500bus.md#solver-qualification-and-independent-demand-designs) recovers Ipopt at 100% and both smooth backends at 90% and 95%, each with 389/389 connected-outage coverage and all 102 droop parameters free. Demand-matched S1 starts, small shared-controller masters, exact reduced models, feasibility-first attempts and exact-Hessian restarts retain full-network acceptance. The best 105% scan is 387/389; numerical failures remain unresolved, and the 110% normal-limit target remains certified infeasible. No multi-demand or full-N-1 closure follows.

The targeted independent emergency-design campaign qualifies connected-outage designs at 105%; see the [targeted results](docs/src/s2_500bus.md#targeted-diagnosis-and-independent-emergency-designs). The 110% emergency gate and CCOpt remain unresolved. No shared multi-demand or full N−1 closure is implied.

The capped 500-bus follow-up stops at the verified 106.25% critical-outage ceiling, correcting the earlier unresolved 106.5% sample. New continuation and common-controller feasibility witnesses pass original-network replay under the approved emergency/relief policy. Three-backend joint optimization, completed 105% loss polishing, and exhaustive shared-controller qualification remain distinct gates; the preceding 389/389 emergency controller is retained. See [the capped follow-up](docs/src/s2_500bus.md#capped-continuation-and-shared-multi-demand-attempts).

The expanded 105% recovery includes the four newly unresolved generator outages and qualifies a native Ipopt feasible controller across all 389 connected outages with zero shedding. Equivalent direct-relief equations halve the targeted master variable count, and implied-Q-bound cleanup recovers joint 90/95/100% feasibility and resource priorities for Ipopt/MadNLP. Final loss convergence and higher-demand/CCOpt gates remain separate; see [the incremental recovery](docs/src/s2_500bus.md#expanded-outage-master-and-incremental-shared-demand-recovery).


S2 checkpoint, 18 October 2026: paused at the user’s request. Preserve the current accepted designs, qualification records and unresolved optimisation gates; resume later from `artifacts/s2_scopf/ieee500_native/incremental_shared_recovery/PAUSED.json`. The 500-bus scope remains open.
