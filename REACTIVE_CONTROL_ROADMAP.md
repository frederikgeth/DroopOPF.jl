# DroopOPF Reactive-Control Reliability Roadmap

## Purpose

This document is a self-contained handoff for continuing the investigation of
DroopOPF's transformer-tap, shunt, Volt–VAr droop, and generator-voltage-control
models. The immediate goal is to determine whether the remaining IEEE-118/300
frozen-test failures are caused by:

1. incorrect equipment equations;
2. inappropriate controller assignments or synthetic data;
3. inadequate physical reactive capability; or
4. nonlinear-solver conditioning and initialization.

Do not overwrite or reinterpret the existing frozen evidence when implementing
the work below. New formulations and qualification rules belong in separately
labelled comparison lanes.

## Current evidence

### Transformer taps

DroopOPF's fixed and variable magnitude-tap equations have been checked against
an independent transcription of the canonical PowerModels ACP OLTC/PST terminal
equations.

- 256 randomized fixed-transformer operating points compare both terminal
  complex powers.
- Five variable-tap NLP operating points compare both bus injections.
- Resistance, charging, tap ratio, signed fixed phase shift, voltage magnitudes,
  and angle differences are covered.
- New equivalence assertions: 527/527 passed.
- Full regression after adding the oracle: 2132/2132 passed.

The transformer terminal-flow equations are therefore not the leading explanation
for the frozen failures. Phase-shift optimization remains outside the current
`TapControl` scope and should only be added for data-identified phase-shifting
transformers.

Relevant test:

- `test/test_transformer_physics.jl`

### Shunts

DroopOPF uses the standard admittance model:

\[
P_{sh}=G V^2, \qquad Q_{sh}=-B V^2
\]

under the project's consumption sign convention. Fixed-shunt, capacitor/reactor,
continuous-bank, sign, availability, replay, and voltage-squared tests pass.

The incremental IEEE matrix produced:

- shunt-only cells: 68/68 strict passes;
- one-droop/one-shunt cells: 24/24 strict passes;
- all 12 synthetic IEEE-118 banks pass without droops;
- all 32 synthetic IEEE-300 banks pass without droops through load 1.03.

The shunt equation is not the main source of the frozen failures. Continuous
shunt feasibility and discrete/legal-step implementability must remain separate
questions.

### Incremental public-case matrix

The checkpointed diagnostic starts from the untouched PGLib case and adds
droops or synthetic shunt banks cumulatively. It uses:

- IEEE-118 loads 1.00 and 1.05;
- IEEE-300 loads 1.00, 1.01, 1.02, and 1.03;
- Ipopt and MadNLP;
- nominal raw anchor start;
- smooth epsilon `1e-6`;
- exact-droop acceptance `1e-5`;
- the frozen one-reset policy;
- source transformer ratios fixed.

Main result:

| Scope | Passed | Failed |
|---|---:|---:|
| Complete incremental matrix | 258 | 62 |
| Raw PGLib, no added control | 12 | 0 |
| Shunt-only increments | 68 | 0 |
| One droop plus one shunt | 24 | 0 |
| IEEE-118 | 83 | 5 |
| IEEE-300 nominal | 58 | 0 |
| IEEE-300 load 1.01 | 45 | 13 |
| IEEE-300 load 1.02 | 42 | 16 |
| IEEE-300 load 1.03 | 30 | 28 |

All one-, two-, and four-droop fixed/free cells pass. Failures emerge with larger
droop populations under stress and are non-monotonic in count, formulation,
solver, and load.

Failure final statuses across the main matrix:

| Final status | Count |
|---|---:|
| `LOCALLY_INFEASIBLE` | 42 |
| `ITERATION_LIMIT` | 12 |
| `LOCALLY_SOLVED` but strict validation failed | 3 |
| `SLOW_PROGRESS` | 3 |
| `NUMERICAL_ERROR` | 2 |

Physical failure categories include reactive/active power balance in 56 failed
cells and exact droop mismatch in 22; some cells contain both. These are failed
solver paths, not global infeasibility certificates.

Artifacts and runner:

- `artifacts/s1_incremental_controls/report.md`
- `artifacts/s1_incremental_controls/summary.json`
- `examples/s1_incremental_controls.jl`

### IEEE-300 controller 5 / generator 11

The first recurring stressed hotspot in the deterministic cumulative ordering is
controller 5:

- generator: 11;
- bus: 119;
- nominal anchor voltage: approximately 1.060 pu;
- nominal anchor Q: approximately 9.460 pu;
- Q limits: `[-5.00, 10.21]` pu;
- voltage deadband: approximately `[1.055, 1.065]` pu;
- slope: `0.00262985` pu-V/pu-Q;
- gain: approximately 380 pu-Q/pu-V;
- normalized upper headroom at the anchor: about 4.9% of its total Q range.

Bus 119 is electrically close to bus 117. Bus 117 has a large fixed capacitive
shunt `B=3.25` pu, and failed stressed iterates repeatedly exhibit their largest
reactive-balance residual at bus 117.

Generator 11 is not outside its Q limits at load 1.02:

| Operating point | Q11 | Upper margin |
|---|---:|---:|
| Nominal raw anchor | 9.460 | 0.750 |
| Raw load 1.02 | 9.673 | 0.537 |
| Valid six-droop fixed solution | 9.966 | 0.244 |
| Valid six-droop free-slope solution | 9.953 | 0.257 |
| Valid 35-droop free-slope solution | 10.004 | 0.206 |

The valid fixed-slope six-droop solution has bus-119 voltage about 1.05367 pu;
upper-Q saturation would begin near 1.05303 pu, so it is not saturated. The
free-slope solution selects half the nominal slope, has voltage about 1.05435 pu,
and is also below but not at Qmax.

The single-controller-5 probe completed 16 cells:

- load 1.00: 4/4 pass;
- load 1.01: 4/4 pass;
- load 1.02: 0/4 pass for the tested paths;
- load 1.03: 1/4 pass.

However, a valid six-controller solution at load 1.02 is also a feasible witness
for the five-controller model after controller 6's equality is removed. Therefore
the failed five-controller paths at 1.02 are demonstrably solver-path failures,
not proofs of infeasibility. Non-monotonic results—five fails, six may pass—show
that controller interactions and local solver basins matter.

Artifacts:

- `artifacts/s1_incremental_control5/report.md`
- `artifacts/s1_incremental_control5/summary.json`

### Same-case witness-seed matrix

The 12 unresolved cells in the 24-cell frozen Ipopt/MadNLP matrix were rerun
from a validated witness for the *same* network and load. Each seed contained
the full physical decision—AC state plus tap, shunt, and droop settings—not
just the state. The target equations, objective, smoothing, strict validation,
and one-reset budget were unchanged. Same-backend seeds were preferred; the
three IEEE-118 nominal MadNLP cells used an Ipopt primal seed with no duals.

- 7/12 strict passes from the witness seed;
- all five IEEE-300 and both stressed IEEE-118 MadNLP targets pass;
- the two stressed IEEE-118 Ipopt targets terminate `LOCALLY_SOLVED` but retain
  exact-droop mismatch about `1.122e-5`, just above the frozen `1e-5` gate;
- the three nominal IEEE-118 MadNLP targets retain `SLOW_PROGRESS` despite
  balance and exact-droop residuals near machine precision.

This establishes both basin-sensitive failures and residual/termination
robustness failures. It does not replace any direct-start frozen decision, and
a failed witness-seed solve remains no infeasibility certificate.

Artifacts:

- `artifacts/s1_frozen_witness_seed_matrix/report.md`
- `artifacts/s1_frozen_witness_seed_matrix/summary.json`

### Third-solver scorecard: CCOpt

CCOpt is retained as the third solver family through its exact-complementarity
lane. It covers the same 12 public direct-start cells and uses independent AC
and exact-droop validation, but its formulation and native one-solve budget are
not pooled as a like-for-like comparison with the smooth Ipopt/MadNLP lanes.

| Solver | Formulation | Strict `1e-5` | Relaxed `1e-2` |
|---|---|---:|---:|
| Ipopt | smooth explicit droop | 8/12 | 8/12 |
| MadNLP | smooth explicit droop | 4/12 | 5/12 |
| CCOpt | exact complementarity | 2/12 | 2/12 |

Relaxing only exact-droop tolerance does not improve CCOpt: every rejected
CCOpt row also fails solver convergence or AC balance. CCOpt therefore broadens
the solver/formulation evidence but does not yet clear the S1 reliability gate.

Artifact: `artifacts/s1_three_solver_scorecard/report.md`.

## Meaning of the current anchor

The **anchor** is one independently validated nominal raw AC-OPF solution of the
untouched PGLib case:

\[
x^{anchor}=(V,\theta,P_g,Q_g).
\]

It currently has two roles:

1. It defines the synthetic droop curves:
   - `V_ref = V_anchor`;
   - voltage deadband is `V_anchor ± 0.005` pu;
   - `Q_ref = Q_anchor` inside the voltage deadband.
2. It supplies the starting state for anchor-start frozen solves.

These roles must be distinguished:

- changing only the starting state changes the numerical path;
- rebuilding controls from another anchor changes the mathematical problem.

The present anchor is one locally solved nominal OPF snapshot, not a time series,
historical observation, or unique system state. Raw stressed cases have been
solved separately, but their solutions have not been used to qualify or rebuild
the synthetic droop assignments.

## Terminology correction: voltage deadband and Q reference

The deadband is a voltage interval. For example,

\[
0.995 \le V \le 1.005
\]

means reactive output remains constant while voltage is inside that interval.
The constant output is a Q reference or bias:

\[
Q(V)=Q_{ref}\quad\text{inside the voltage deadband}.
\]

The current field `q_at_deadband` is therefore better described as `q_ref` or
`q_bias`; it is not a Q deadband.

Setting `Q_ref=Q_anchor` makes the newly constructed curve reproduce the nominal
OPF point. That is convenient for a synthetic numerical fixture, but it is not
automatically physical:

- inverter Volt–VAr control commonly uses `Q_ref=0` or a documented plant Q/PF
  schedule inside the normal-voltage region;
- scheduled incremental droop may legitimately use a nonzero Q schedule;
- a synchronous generator with AVR should normally regulate voltage until a Q
  limit is reached rather than hold an arbitrary OPF-derived Q constant inside a
  voltage deadband.

The existing `Q_ref=Q_anchor` lane must be retained for reproducibility but
labelled synthetic.

## Target reactive-control data model

Each generator should have at most one explicit reactive-control mode.

### `FreeQ`

\[
Q_{min}\le Q_g\le Q_{max}
\]

No voltage-control equality. This is the standard raw AC-OPF comparator.

### `FixedQ`

\[
Q_g=Q_{schedule}
\]

Use only for an explicit fixed schedule or a clearly labelled synthetic test.

### `AVR`

Hold a declared voltage setpoint while Q is interior. When a Q limit becomes
active, permit voltage to depart from the setpoint. This is PV-to-PQ switching
and is the preferred model for conventional synchronous generator voltage
regulation.

Implement both:

- a smooth projection/transition formulation with an independently reported
  exact AVR mismatch;
- an exact complementarity formulation for comparison.

### `VoltVarDroop`

Use a voltage deadband, a declared `Q_ref` inside it, sloping response outside,
and saturation at Q capability. Reserve this for explicit inverter/static
Volt–VAr studies or clearly labelled synthetic assignments.

### Possible later mode

Add power-factor or `Q(P)` control only if required by actual plant data.

## Ordered execution phases

1. Preserve the frozen evidence and its strict acceptance contract.
2. Classify failures with Phase-I restoration and feasible witnesses.
3. Reduce and isolate each failure class in the unchanged frozen lane.
4. Test numerical remedies against that unchanged contract.
5. Maintain both adversarial and physically qualified benchmarks.
6. Apply the reliability gate before accepting a frozen-lane remedy.
7. Add explicit reactive-control modes with backward compatibility.
8. Implement and verify AVR.
9. Build raw operating envelopes.
10. Separate anchor construction from start sensitivity.
11. Qualify generators and declare controller-assignment lanes.
12. Compare Volt–VAr references and slope rules independently.
13. Re-run the isolation matrix for every new control lane.
14. Gate the relevant physical lane before SCOPF.

## Detailed workstreams

The ordering below is deliberately reliability-first.  The frozen lane already
contains feasible-but-unsolved cells, so adding controller semantics or new
physical qualification rules cannot be treated as the primary fix for those
tests.  The existing synthetic lane remains a required adversarial regression
target while the project also builds a physically qualified lane.  Neither lane
may silently redefine the other.

### Evidence preservation

- Do not overwrite frozen matrices or incremental artifacts.
- Keep current anchor-derived droop as a reproducible synthetic/adversarial lane.
- Store every failed iterate and raw mismatch.

### Explicit reactive-control modes

Current implementation: opt-in base-case assignments support FreeQ, FixedQ,
and VoltVarDroop in smooth OPF and the CCOpt entry point, with independent
equilibrium validation. Exact base-case AVR is implemented in CCOpt and its
central-path approximation in Ipopt/MadNLP, with independent regime validation
and small-case cross-solver agreement. Study v5/result v2 persistence and
SCOPF replay are implemented with legacy-schema compatibility. Common-location
AVRs use proportional Q-range sharing and aggregate PV/PQ limits. Remote-bus
and identified branch-terminal AVR locations are implemented; an outaged
monitoring branch disables its branch-terminal regulator. Preliminary
one-device and unstaged k3 attempts retain their bounded no-result outcomes;
they are historical direct-path non-passes, not the final staged scorecard. A
predeclared three-device, one-per-bus headroom set is used for the qualified
staged lane. AVR-aware base-case joint
tap/shunt design is implemented and persisted. The k3 AVR set validates under
Ipopt at loads 1.00 and 1.01 for both IEEE systems. The direct IEEE-118 k3
joint-tap run has a retained bounded non-pass, but a same-case staged k1 → k2
→ k3 continuation validates all three stages, identifying initialization and
conditioning rather than k3 infeasibility. The staged policy validates the full
Ipopt and MadNLP joint-design envelopes at loads 1.00 and 1.01 on both
IEEE-118 and IEEE-300: all 24 stage/backend/case cells are `LOCALLY_SOLVED` and
independently valid. The exact CCOpt staged lane validates 11/12 physical
cells (7/12 with a strict `LOCALLY_SOLVED` status gate): only IEEE-300 load
1.01 k3 is invalid (`LOCALLY_INFEASIBLE`), after physically valid but
`ALMOST_LOCALLY_SOLVED` k1/k2 stages. Diagnosing that exact stressed-k3 boundary
with a full smooth k3 cross-seed recovers a valid exact point
(`ALMOST_LOCALLY_SOLVED`, complementarity residual `2.484e-8`, tap movement
from the seed about `5.18e-9`). The original `LOCALLY_INFEASIBLE` result is
therefore basin-sensitive rather than physical infeasibility. SCOPF integration
remains open.
Pure FreeQ/FixedQ calls through CCOpt
delegate to MadNLP and must not count as independent third-solver evidence.

- Implement `FreeQ`, `FixedQ`, `AVR`, and `VoltVarDroop` assignments.
- Enforce at most one reactive-control mode per generator.
- Rename or alias `q_at_deadband` to `q_ref` with backward-compatible study-file
  reading.
- Keep current public APIs working where possible.

### AVR implementation and verification

Implement smooth and exact PV-to-PQ formulations. Required unit tests:

- interior-Q PV operation;
- upper-Q-limit transition;
- lower-Q-limit transition;
- multiple generators at one bus;
- fixed voltage-setpoint equivalence;
- smooth-versus-exact agreement;
- rejection of inconsistent voltage/Q states;
- Ipopt, MadNLP, and CCOpt comparison where supported.

For SCOPF later, base and contingency voltage regulation must be coupled according
to the declared AVR policy; do not give every contingency an unrelated voltage
target.

### Raw operating envelopes

Before adding synthetic controls, solve the untouched source case at:

- 1.00;
- 1.01;
- 1.02;
- 1.03;
- 1.04/1.05 only where a validated raw continuation witness exists.

For every level record:

- `V`, `theta`, `Pg`, `Qg`;
- upper/lower and normalized Q headroom;
- voltage and thermal margins;
- fixed-shunt injections;
- transformer loading;
- solver, start, and continuation source;
- independent physical validation.

Continuation is useful evidence but must not turn a failed path into an
infeasibility claim.

### Anchor-construction versus start sensitivity

**Starting-point sensitivity:** keep identical control parameters and compare
anchor, previous-load, flat, alternate accepted, and independent cold starts.

**Controller-construction sensitivity:** rebuild controllers from different raw
operating points, such as:

- current dispatch-deviation OPF;
- source economic-cost OPF when costs are imported;
- fixed-P reactive power flow;
- voltage/reactive-loss-oriented solution;
- representative measured snapshots when available.

Report these as different models, not merely different warm starts.

### Generator qualification over the raw envelope

For each candidate and raw scenario `s`, compute:

\[
h_Q^s=
\frac{\min(Q_g^s-Q_{min},Q_{max}-Q_g^s)}{Q_{max}-Q_{min}}.
\]

Also record directional absolute reserves. Predeclare exploratory rules such as:

- minimum normalized bidirectional headroom, initially investigate 10%;
- minimum absolute Q reserve;
- no raw Q-limit activation;
- minimum voltage distance to saturation knees;
- maximum allowed `dQ/dV` gain;
- a validated raw solution at every included stress level.

Do not delete rejected generators. Label them with reasons such as
`near_q_limit`, `excessive_gain`, `raw_snapshot_unavailable`, or
`unknown_device_type`. Thresholds must be declared before comparing pass rates to
avoid post-hoc selection bias.

### Controller-assignment lanes

1. **Raw/FreeQ:** all generators bounded but otherwise free in Q.
2. **AVR:** conventional-generator PV-to-PQ response.
3. **FixedQ:** declared Q schedules.
4. **Volt–VAr:** explicitly selected inverter/static controls.
5. **Mixed:** only with documented assignments.

Do not present droop on nearly every PGLib generator as a physical model of the
IEEE system.

### Volt–VAr reference comparisons

Voltage-reference/deadband variants:

- nominal-system deadband, e.g. 0.995–1.005 pu;
- source voltage setpoint ± declared half-width;
- raw-anchor voltage ± declared half-width;
- documented plant setpoint.

Q-reference variants:

- `Q_ref=0`;
- `Q_ref=Q_source`;
- `Q_ref=Q_anchor` (current synthetic method);
- documented Q or power-factor schedule.

Failure of `Q_ref=0` may correctly reveal that the network requires scheduled
reactive support or AVR; it must not automatically be labelled a solver defect.

### Automatic slope rule

The current rule,

\[
m=\frac{0.04}{Q_{max}-Q_{min}},
\]

makes generators with wide Q ranges extremely stiff. Investigate slopes based
on:

- equipment MVA rating and percentage droop;
- explicit maximum `dQ/dV`;
- declared voltage movement from `Q_ref` to each limit;
- local network Q–V sensitivity;
- grid-code/plant settings where available.

Every curve report should include slope, gain, both saturation voltages, and the
minimum distance from the raw operating envelope to either knee.

### Frozen-failure reduction and isolation

Start with the frozen synthetic `Q_ref=Q_anchor` lane, before changing control
semantics, qualification thresholds, objectives, equations, acceptance gates,
or the declared one-reset budget. Run:

1. raw network;
2. each candidate controller individually;
3. cumulative controller counts 1, 2, 4, 8, 16, 32, all;
4. intermediate counts around transitions;
5. shunts only with zero droop attachments;
6. taps only with zero droop/shunts;
7. one droop plus one shunt;
8. one droop plus one tap;
9. full family combinations.

Use both solvers, declared starts, qualified load levels, unchanged strict gates,
and explicit fixed/free parameter labels. Non-monotonic cumulative results require
individual-device and pairwise checks.

### Phase-I diagnostics and witness-based classification

Phase I should minimize separately reported slacks for:

- active/reactive balance;
- voltage limits;
- generator Q limits;
- thermal limits;
- droop equality;
- AVR complementarity;
- tap/shunt bounds.

Never accept a slack solution as a strict physical result. Classify every cell as:

1. `validated_feasible`;
2. `solver_path_failure_with_witness`;
3. `strict_audit_failure`;
4. `unknown_feasibility`;
5. `raw_case_unqualified`;
6. `minimum_violation_positive`.

The failed IEEE-300 five-droop load-1.02 path already belongs to
`solver_path_failure_with_witness` because a valid stricter six-droop solution
exists and remains feasible after removing controller 6's equality.

### Numerical remedies against the unchanged frozen contract

Evaluate:

- load continuation;
- controller-count continuation;
- slope continuation from soft to physical gain;
- smoothing-epsilon continuation;
- compatible warm starts only;
- independent cold rebuild/retry;
- alternate barrier strategy and linear solver where available;
- reduced-Q formulation;
- exact complementarity comparison;
- rectangular-voltage formulation if justified.

Always retain and report the raw exact mismatch even when showing a diagnostic
relaxed tolerance.

### Two benchmark suites

**Physically qualified suite:** validated raw envelope, explicit controller types,
adequate Q reserve, credible slopes/schedules, source-faithful taps and shunts.
Use this for physical-model and reliability claims.

**Adversarial numerical suite:** generator 11/controller 5, near-limit units,
high-gain droops, many simultaneous controllers, stressed loads, and difficult
starts. Use this to improve numerical robustness without treating it as a
representative physical IEEE model.

### Reliability gate before model expansion

Before a numerical remedy becomes the default path, require that it:

- is evaluated on every frozen cell, not only a selected failure;
- preserves all previously accepted frozen witnesses under the original strict
  physical validation;
- records both within-budget and diagnostic/out-of-budget outcomes separately;
- improves the classified failure set without changing equations, objective,
  physical bounds, or strict acceptance thresholds; and
- remains reproducible from the declared starts and restart policy.

A remedy that only solves a re-anchored, requalified, relaxed, or otherwise
different problem is useful comparative evidence, but does not resolve a frozen
test failure.

### Gate before SCOPF

Proceed to full SCOPF only when:

- raw base cases validate over the declared envelope;
- FreeQ, FixedQ, AVR, and Volt–VAr unit tests pass;
- transformer and shunt oracle tests pass;
- physically qualified 118/300 base cases have reliable witnesses;
- failures are classified rather than pooled;
- preventive/corrective timing is declared.

For SCOPF:

- droop and AVR may provide automatic response;
- active response follows declared participation;
- taps and shunts are preventive by default;
- corrective tap/shunt movement is allowed only with justified response time;
- scenario-specific independent equipment settings are forbidden unless explicitly
  modelling corrective controls.

## Recommended immediate execution order

1. Freeze the exact test contract and produce a per-cell ledger of status,
   strict residuals, last finite iterate, seed lineage, and known witnesses.
2. Build the smallest deterministic reproducer for each distinct failure class,
   starting with IEEE-300 controller 5 at load 1.02; include one-device,
   transition-count, and pairwise variants.
3. Add Phase-I restoration and witness-based classification to every frozen
   failure.  Do not call an unclassified failed solve infeasible.
4. On the unchanged frozen model, compare targeted numerical remedies: compatible
   warm starts, continuation, scaling/coordinates, reduced-Q and smooth-clamp
   alternatives, derivative/Hessian paths, and exact-complementarity comparison.
5. Promote a remedy only if it meets the Phase-6 reliability gate across the
   complete frozen matrix; retain unsuccessful attempts and diagnostic budgets.
6. In parallel, add the backward-compatible explicit reactive-control data model
   and its unit-level invariants—without making it a prerequisite for resolving
   the legacy frozen lane.
7. Implement and verify AVR, then produce raw envelopes and Q-reserve reports.
8. Declare qualification annotations and run separately labelled controller,
   `Q_ref`/`V_ref`, slope, and anchor-construction comparison lanes.
9. Freeze the physically qualified benchmark alongside (not in place of) the
   adversarial frozen benchmark.
10. Begin SCOPF only after the base-case gate passes for the relevant physical
    lane and frozen-lane reliability evidence remains intact.

## Interpretation rules

- A solver failure is not an infeasibility certificate.
- A looser reporting tolerance never replaces the strict acceptance gate.
- A valid solution of a stricter model can prove feasibility of a relaxed model
  obtained by removing constraints.
- Re-anchoring droops at every stress point hides the response being tested and
  should not be used as a reliability fix.
- Changing an initial state is a numerical experiment; rebuilding `V_ref` or
  `Q_ref` from another anchor is a model change.
- Continuous shunt feasibility and legal switching implementation are separate.
- Synthetic PGLib controller assignments must not be described as measured plant
  controls.
