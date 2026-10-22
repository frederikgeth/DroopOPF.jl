# DroopOPF Reactive-Control Reliability Roadmap

## Purpose

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

The shunt equation is not the main source of the frozen failures. Continuous
shunt feasibility and discrete/legal-step implementability must remain separate
questions.

### Incremental public-case matrix

The checkpointed diagnostic starts from the untouched PGLib case and adds
droops or synthetic shunt banks cumulatively. It uses:

Main result:

| Scope | Passed | Failed |
|---|---:|---:|
| Complete incremental matrix | 258 | 62 |
| Raw PGLib, no added control | 12 | 0 |
| Shunt-only increments | 68 | 0 |
| One droop plus one shunt | 24 | 0 |

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

For SCOPF:

- droop and AVR may provide automatic response;
- active response follows declared participation;
- taps and shunts are preventive by default;
- corrective tap/shunt movement is allowed only with justified response time;
- scenario-specific independent equipment settings are forbidden unless explicitly
  modelling corrective controls.

### M9.1 implementation checkpoint

The SCOPF study now carries selected continuous `TapControl` and `ShuntControl`
policies plus an explicit `SCOPFControlPolicy`. Taps and shunts default to
preventive timing and are constrained to the base setting in every scenario
where they remain available. Either family may instead be declared corrective,
which permits an independently bounded setting in each scenario. An outaged
controlled transformer has no scenario variable; that absence is checked and
is not counted as corrective movement.

Reactive behavior is deliberately `:automatic`, not preventive or corrective:
the assignment, AVR setpoint, FixedQ schedule, Volt–VAr curve, and regulated
location are shared, while reactive output, voltage, limit regime, and surviving
common-location AVR group respond to scenario physics. This prevents accidental
scenario-specific voltage targets while preserving actual automatic response.

The result persists scenario-indexed tap and shunt settings. Independent
validation reconstructs every outage network with those reported settings,
checks their key sets and bounds, replays AC/control physics, and separately
reports preventive equipment-coupling error. Deliberately corrupted settings
are rejected. Study schema v8 and SCOPF-result schema v4 retain backward reading
of older studies as fixed-equipment, preventive-policy cases.

Synthetic regressions cover preventive and corrective timing, tap outages,
persistence, corruption detection, fixed-base rejection when settings are
unavailable, and staged initialization. The latter is important: the enlarged
nonlinear model can terminate at an infeasible restoration point from a direct
start even when a validated staged witness exists. That outcome remains a
solver-start failure, not an infeasibility claim.

The remaining M9 feature slices are distinct from S2:

- **M9.2 — explicit corrective-action budgets (implemented):** constrain movement from the
  base setting per device/scenario, declare which actions are available, and
  validate those delta limits independently. M9.1 already supports corrective
  scenario settings within absolute equipment bounds; it does not yet represent
  movement time or action count; M9.2 now supplies base-to-contingency movement
  budgets.
- **M9.3 — staged response assessment (implemented):** compare the immediate contingency state
  with preventive equipment frozen against a later AVR/equipment-settled state.
  Report voltage, thermal and Q margins, AVR target error and saturation. These
  are two steady-state assessments, not a transient trajectory.

A separate direct-witness recovery lane initializes every fixed-equipment
scenario from the direct M9.1 result instead of leaving contingency states cold.
Ipopt still ended at `TIME_LIMIT`, although only power-balance residuals
remained; MadNLP and CCOpt reached the same external wall limit without an
artifact. This excludes that simple all-scenario seed substitution as a complete
recovery, without changing the declared fixed-seed S2 lane.

## Recommended immediate execution order

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
