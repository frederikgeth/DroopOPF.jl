# Security-constrained AC OPF (M2 and M9.1)

The SCOPF engine jointly optimizes one base dispatch and a declared set of line and
generator outages. Droop settings remain fixed across scenarios. Each scenario
has its own AC voltages, angles, active generation, and reactive generation.
The joint formulation remains a small-network reference implementation. M10
also provides a separate conservative pre-solve filter for independent
contingency assessment; it is not applied inside the joint SCOPF model.

## M10 contingency catalog and baseline assessment

M10's core capability is network-size agnostic. Given any validated `Case` and
fixed base `ACState`, `evaluate_contingency_catalog` evaluates every eligible
entry independently and returns its solver result, independent report, and
rank. `contingency_screening_scores` supplies deterministic within-device
priority percentiles without classifying a low-scored outage as safe:

```julia
catalog = contingency_catalog(case)
assessments = evaluate_contingency_catalog(case, base_state;
    catalog, participation=participation)
scores = contingency_screening_scores(case, base_state; catalog)
decisions = filter_contingencies(case, base_state; catalog,
    loading_threshold=0.8, voltage_guard=0.02)
pipeline = assess_contingency_pipeline(case, base_state; catalog,
    audit_screened_ids=[:branch_11])
write_contingency_pipeline("pipeline.json", pipeline)
```

Use normal Julia compilation for performance runs. The supervisor no longer
uses `--compile=min`, which slows numerical model construction. Power-balance
expressions for the imported FreeQ baseline contain only nonzero admittance
entries; this preserves the equations while avoiding dense derivative graphs.
Declared reactive-control paths retain their existing expression ordering to
preserve sensitive CCOpt warm-start trajectories. Each completed baseline
writes `timing.json` separating construction (including first-call compilation)
from optimization and extraction. Compare warm runs in the same Julia process
when measuring sustained throughput; a fresh process pays compilation again.

`contingency_catalog(case)` deterministically enumerates every available line,
transformer, and generator outage. Each candidate records its device ID and a
structural disposition. Connected outages and generator outages are
`eligible`; a line or transformer outage that islands the network is retained as `excluded`
from the original single-component evaluator with reason
`islanding_unsupported`. It can instead be passed to
`evaluate_islanding_contingency`. That path retains the original-reference
component unless another component has strictly more buses. If the larger
component is selected, the bus of its available generator with greatest
`p_max` becomes the reference (generator ID breaks ties). Only the retained
component is balanced; discarded buses, load, and generation capacity are
reported and are never classified as served or safe.

`filter_contingencies` is a conservative routing layer. Generator outages go
to exact AC evaluation. Structurally islanding line and transformer outages go to the
island-aware evaluator. Connected network outages use a DC LODF estimate and
are screened only when predicted loading is below the declared threshold and
the base voltage is outside the guard band. Singular or uncertain calculations,
near-limit base voltages, and predicted thermal risk all fall back to exact AC
evaluation. Screening is a workload decision, not an AC security certificate;
thresholds require held-out reliability qualification before operational use.

`assess_contingency_pipeline` executes those routes and provides the integrated
checks around them. It validates the base state, requires exactly one decision
for every catalog entry, checks decision identity against the catalog, retains
per-contingency evaluation errors, and independently validates every executed
AC result. Generator outages always use exact fixed-base SCOPF assessment;
islanding line/transformer outages use retained-component AC assessment;
screened connected network outages remain explicitly `screened_not_evaluated`.

The optional `audit_screened_ids` list selects deterministic screened cases for
an exact AC cross-check. An unresolved audited case becomes
`screening_audit_failure`, moves to the top of the combined ranking, and makes
the pipeline completeness check fail. `screening_enabled=false` converts every
otherwise screened connected outage into an exact baseline run. The result
reports `routing_complete` separately from `full_ac_coverage` and
`all_outcomes_accepted`; therefore a successfully routed filtered run cannot be
mistaken for complete AC security assessment. The result contains aggregate
network, line, transformer, and generator rankings plus a combined operational
ranking. The combined ordering uses explicit tiers—screening-audit failure,
evaluation error, invalid result, island load loss, physical-only result,
accepted exact result, then unaudited screened entry—before severity and stable
ID tie-breaks. The aggregate network ranking is retained for compatibility,
while line and transformer rankings are separate families.

The diagnostic baseline runner evaluates a numbered batch against one
independently validated, fixed base OPF state:

Use the supplied POSIX supervisor for a bounded batch. It records its own
completion or timeout in `supervisor.md` and retains `run.log` even if the
child never reaches Ipopt. An operating-system CPU-limit signal is explicitly
recorded as `cpu_limited_unresolved`:

The integrated runner writes `campaign.md` and `campaign.json` directly.
The report command recognizes these files; for historical campaigns it still
generates the legacy metric-specific coverage and timing report:

Only for **historical-format**, complete exact enumerations, the old inexpensive
base-state loading/outage-size heuristic can be benchmarked with:

The benchmark reports unresolved-case recall at fixed evaluation budgets and
the smallest retrospective budget that captures every unresolved exact
outcome. It does not activate filtering: thresholds selected and evaluated on
the same campaign cannot establish out-of-sample safety.
`rank_contingencies(catalog, report)` ranks only outages represented in the
report; invalid or physical-only outcomes remain visible ahead of accepted
ones, and unlisted outages are never presumed safe. This is a fixed-base
security assessment, not a security-constrained redispatch solve. Complete all
batches before comparing ranking or filtering methods to the enumeration
baseline. The production routing API uses LODF only after this exact baseline
was established; it is not silently enabled in the historical IEEE campaigns.
The shared-droop scenario-addition driver is documented in
[Droop security design](droop_security.md); parallel execution remains future work.

### Opt-in droop-response guard

`droop_response_guard=true` adds individual generator/controller Q headroom,
bounded AC/droop-response prediction and controller-regime transition guards.
It only changes screened branches to exact evaluation; it never changes exact
or island-aware routes into screens. Unsupported or uncertain predictions fall
back to exact AC. Pass the same participation weights used by subsequent exact
assessment. The flag is supported by filtering, the integrated pipeline,
qualification and resumable campaigns, and is included in campaign fingerprints.
The default is false. See [P2-02 qualification](research.md) for the
frozen protocol and current evidence; saved-case improvement is not held-out
qualification or a security certificate.

### Generic resumable campaigns and filtering qualification

`run_contingency_campaign(directory, case, base_state)` supports arbitrary
networks and the integrated screened, exact, audited and island-aware routes.
Set `screening_enabled=false` for the exhaustive AC reference. Its returned
`result` is a `ContingencyPipelineResult`; `resumed_count`, `evaluated_count`
and `fingerprint` describe reuse. Completion refers to the supplied catalog;
a subset does not imply complete network N-1 coverage.

The atomic JSON checkpoints bind the complete case/catalog, saved base,
participation, screening thresholds, audit IDs, numerical settings, code,
Julia version and dependency files. A changed contract is rejected, not silently
reused. Corrupt/incomplete checkpoints and evaluation errors are rerun. Saved
states are revalidated and reranked; saved acceptance flags are not trusted.
Invalid completed solves can be resumed as unresolved evidence. To retry with
different settings, choose a new directory. The directory lock prevents
concurrent writers; after a forcibly killed process, verify no writer is active
before removing its stale `.campaign-lock` directory. Checkpoints provide
process-interruption recovery, not a power-loss durability guarantee.

`validate_contingency_filter(case, base_state)` compares filter decisions with
exhaustive AC routes on identical inputs, separately for lines, transformers
and generators. It reports screened unresolved outcomes, screened physical
failures, and counts found at each evaluation budget. Solver errors/rejections
are unresolved, not proven infeasibility. Recall is undefined if there are no
unresolved cases. Evaluation order is mandatory routes first, then descending
predicted loading with stable ID ties; post-evaluation severity ranking remains
a separate output. LODF factorization is reused across candidate transactions;
nonfinite predictions and unsupported numerical conditions fall back to AC.

The default filter now additionally uses `reactive_guard=0.1` and
`ac_risk_guard=true`. The first compares aggregate upward/downward generator Q
headroom with available Q range. The second escalates predicted apparent-flow
loading and large impedance-based voltage-drop changes after redistribution.
Neither is an AC solution or a mathematically certified bound. They only
escalate: they cannot change an existing exact route into a screen. Generator
outages remain exact. Both settings are included in campaign fingerprints;
changed settings require a new campaign directory.

Run the broader small-network qualification and timing experiment sequentially:

```sh
julia --project=. examples/scopf_filter_qualification.jl artifacts/scopf_filter_qualification/baseline baseline both
julia --project=. examples/scopf_filter_qualification.jl artifacts/scopf_filter_qualification/enhanced enhanced both
julia --project=. examples/scopf_filter_qualification.jl artifacts/scopf_filter_qualification summary
```

The predeclared discovery partition contains twelve 3/5-bus cases; held-out
contains twelve 4/6-bus cases. Ring/chord topology, demand, reactive reserve,
generation location and transformer taps vary. Legacy thresholds are frozen
at 0.8 loading and 0.02 pu voltage margin; its additional guards are disabled.
Enhanced settings were frozen after discovery and before held-out evaluation.
Per-family unresolved recall is compared with exhaustive AC assessment.
Reports retain failures and rejected bases, rather than silently omitting them.

Three paired timing repetitions alternate execution order. The first is excluded
from warmed results. Phase timing separates filter, preparation/model building,
optimization/extraction and independent validation/ranking; report serialization
is timed separately and excludes disk I/O and plotting. First-comparison wall
and runtime-provided compilation time are retained separately; they exclude
process startup, package precompilation/loading and base construction. Phase
times and compile counters are not claimed to be an exact disjoint accounting.
The evidence index is `artifacts/scopf_filter_qualification/evaluation.md`.

The first frozen comparison covered 168 outages over those 24 inputs. Legacy
screening missed two unresolved branch outages in the discovery reactive-stress
case; the enhanced guards escalated both. Both policies had zero observed misses
on 90 held-out outages. The enhanced policy screened 44 held-out branch outages
(legacy: 66), so its extra caution has a measurable workload cost. Warm
screened/exhaustive speedup for the enhanced policy was 1.22× on discovery and
1.31× on held-out, based on summed per-input medians, not a large-system forecast.
First-comparison JIT dominated approximately nine seconds of cold execution.
All held-out branch outages passed the exhaustive reference; held-out branch
failure recall is therefore undefined, not 100%. The observed unresolved
held-out cases were generator outages, which remain exact under both policies.
After the enhancement, the full unit suite passed 2,626/2,626 tests in 3m35.0s;
the documentation build passed with its API-page size warning only. Coverage
and phase-timing SVGs were rendered and visually inspected.

## Response contract

All active/reactive powers and redispatch limits are per-unit on `case.base_power`;
voltage magnitudes are per-unit and angles are radians. Positive P/Q means network
injection. The reference bus fixes only its angle; it does not supply unbounded
balancing power. All available generators retain their capability bounds.

Preventive mode uses a base schedule and limit-aware automatic active response:

```math
P_{g,c}=\operatorname{clip}(P_{g,0}+\alpha_{g,c}\lambda_c,\ L_{g,c},\ U_{g,c}).
```

Effective bounds intersect generator and attached droop active capability with
any declared base-to-outage `redispatch_limits`. A zero-weight unit holds its
base output. Unavailable generators supply zero and are excluded. Zero-range
units are excluded from normalized response weights. As the common signal grows,
a participant at a bound stays there and unsaturated participants continue
responding. If total reserve is inadequate, the model does not invent balancing
power or relax operating bounds.

`Study` and assessment APIs default to `default_participation(case)`: nonzero
effective active-capability-range weights. Supply actual governor/AGC weights
when known; the default is an explicit approximation. An explicit empty dictionary
selects no participants and is rejected when an outage requires response.
The surviving weights are normalized. Weights do not encode response speed.

The retained `balancing_power` result field contains the common request signal
`lambda`, in pu. After saturation it is **not** the total delivered adjustment;
calculate that from surviving generators' actual base-to-outage changes.
The smooth reactive encoding uses an exact piecewise active projection
(`min`/`max`) with kinks at saturation. The complementarity encoding uses
projection KKT conditions with nonnegative bound slacks and multipliers.
Both represent the same exact bounded active-response law. Coupled preventive
CCOpt models default both the solver and proportional-update relaxation floors
to `1e-14`; supplied optimizer attributes can override these numerical defaults.
This tightens the internal relaxation without changing physical acceptance
tolerances. Projection slacks enforce equipment bounds without duplicate active
variable-bound rows. A sole movable participant uses an equivalent canonical
request-equals-delivery signal. It is not a smooth governor dynamic model;
local convergence and saturation-boundary behavior require validation.

Current study/result JSON carries `active_response="limit_aware_v1"` (study v10,
result v5). Historical coupled preventive files without this marker are rejected,
rather than silently reinterpreted. Replay them with their original source.
Campaign fingerprints include the response contract; use a fresh output directory
for the new policy. Historical filtering thresholds and performance outcomes
require requalification before use as evidence for this policy.

Corrective mode replaces this automatic-response equation with:

```math
-r_g \le P_{g,c}-P_{g,0}\le r_g.
```

`redispatch_limits[g]` supplies the finite, nonnegative symmetric bound `r_g`.
An omitted generator has zero permitted redispatch. This represents controlled
post-contingency redispatch, without a time or ramp-rate model. Participation
weights are rejected in this mode to avoid an ambiguous policy.

In both modes:

- Unavailable generators inject zero P/Q and their droop equation is omitted.
- Unavailable branches contribute neither admittance nor flow.
- Available controlled generators obey their fixed `Q(V)` relation at the
  declared regulated bus in each scenario. No voltage setpoint is optimized.
- Generators without a droop attachment retain M1's independently adjustable Q
  within capability limits. Attach controls to every unit when autonomous
  volt-var equilibrium is the intended experiment.
- Loads, branch ratings, and voltage limits are unchanged across scenarios.
- Disconnected base networks are rejected by the joint SCOPF formulation.
  Islanding outages use the separate retained-component assessment described
  above.
- Reactive capability is M1's constant Q interval with a permitted P interval;
  a curved P-dependent capability boundary remains outside this implementation.

## Equipment and reactive-control timing (M9.1)

`Study` may select continuous transformer ratios and simple-bank susceptances
with the same `TapControl` and `ShuntControl` policies used by base-case design.
Timing is explicit:

```julia
policy = SCOPFControlPolicy(
    taps = :corrective,       # default: scenario-specific within bounds
    shunts = :corrective,     # default: scenario-specific within bounds
    reactive = :automatic,    # the only supported reactive timing
    # Optional M9.2 maps: listed devices receive ± movement budgets;
    # selected but unlisted corrective devices are frozen.
    tap_movement_limits = nothing,
    shunt_movement_limits = nothing,
)

study = Study(case;
    contingencies,
    participation,
    reactive_assignments,
    tap_controls = [TapControl(11; lower=0.95, upper=1.05)],
    shunt_controls = [ShuntControl(201)],
    control_policy = policy,
)
```

Corrective equipment has an independent bounded setting in each scenario and
is the default for selected tap and shunt controls. Preventive equipment has
one setting shared by the base case and every scenario in which the device
remains available; request it explicitly. These options may be selected
separately for taps and shunts. A controlled transformer that is itself
outaged has no contingency setting or coupling equation. This is availability,
not corrective movement.

Reactive modes are automatic: the assignment, droop curve, AVR voltage target,
FixedQ schedule, and regulated location are shared across scenarios, while Q,
voltage, AVR limit regime, and the set of surviving common-location regulators
respond to scenario physics. Scenario-specific voltage targets or droop
parameters are not introduced. A branch-terminal regulator is disabled when
its monitoring branch is outaged, as in the fixed-equipment SCOPF path.

Tap ratios and shunt susceptances remain continuous relaxations. Corrective
timing asserts that movement is allowed in the modeled post-contingency stage;
it does not supply a response time, switching count, discrete recovery, or
dynamic feasibility claim. The caller is responsible for making that timing
credible for the equipment represented.

M9.2 movement maps refine corrective timing. `nothing` retains M9.1 behavior:
every selected corrective device may choose any setting inside its absolute
control bounds. A supplied dictionary declares the allowed-action set. Listed
devices satisfy `abs(setting[c]-setting[base]) <= limit`; selected devices
omitted from the dictionary are frozen at their base setting. Limits are finite,
nonnegative, and independently replayed by the validator.

Long assessments can solve the two M9.3 stages in separate processes and then
call `assemble_scopf_response_stages(immediate_study, settled_study, immediate,
settled)`. This performs the same independent validation and metric assembly as
`assess_scopf_response_stages` without rerunning either solve. The S2 public
runner uses this path so an external wall timeout cannot erase a completed
stage.

The process-isolated S2 example also supports a **separate recovery lane** that
seeds a fixed-equipment solve from a direct SCOPF witness across every scenario.
It is diagnostic evidence only: its outcome must not overwrite the declared
FreeQ-base fixed-seed qualification lane. A physically replay-valid solution
with a rejected solver status may be used as an initialization witness, but is
still rejected for solver-acceptance reporting.

When the direct equipment-aware result is already independently valid, M9.3 may
also be anchored directly to its saved base state and equipment settings. This
is distinct from claiming success for a nominal-equipment staging lane. Reports
must identify the anchor lineage and keep immediate, settled, physical-replay,
and solver-acceptance outcomes separate.

The objective is the existing M1 base schedule-deviation objective:

```math
\min \sum_g (P_{g,0}-P_g^{\rm initial})^2
       + 10^{-3}(Q_{g,0}-Q_g^{\rm initial})^2.
```

Contingency states impose feasibility constraints without an additional cost.
Consequently, corrective dispatch can be nonunique. This is not an economic
SCOPF cost model. With no contingencies, the problem reproduces M1.

## Solve and evaluate

```julia
study = Study(case;
    contingencies = [
        Contingency(:line_22; branch_ids = [22]),
        Contingency(:generator_9; generator_ids = [9]),
    ],
    participation = default_participation(case),
)
result = solve(study)
report = equilibrium_report(study, result)
println(markdown_report(report))

# Assess an existing base equilibrium without changing its dispatch or voltage.
evaluation = evaluate_contingencies(study, result.states[:base])

# Alternatively, allow bounded corrective redispatch.
corrective = Study(case; contingencies = study.contingencies,
    mode = :corrective, redispatch_limits = Dict(7 => 0.8, 9 => 0.8))
corrective_result = solve_scopf(corrective)
```

IDs refer to device IDs, not array positions. State vectors retain original case
order, including zero entries for outaged generators. Results use `:base` and the
contingency IDs as dictionary keys. No state is silently treated as feasible:
a failed solve may return an infeasible iterate, or `nothing` if none is available.
During fixed-base evaluation, the supplied base is independently validated but
is not rebuilt as a redundant set of fixed equations in the NLP.

The default solver is Ipopt. `optimizer_factory=MadNLP.Optimizer` uses the same
smooth formulation. `encoding=:complementarity` selects CCOpt and the exact PWL
formulation; omit `optimizer_factory` for this encoding. Solver options are
passed through `optimizer_attributes`.

`solve_scopf_continuation(study; smooth_epsilons=[1e-2,1e-3,1e-4])` returns the
sequence of results, warm-starting all scenario states. It stops after solver
failure or a missing state. Independently validate the final result. For other
initial points, pass a dictionary through `initial_states` to `solve_scopf`.

Equipment variables use each control's `initial` value. For difficult joint
models, first solve the fixed-equipment SCOPF and pass its scenario states as a
staged start; then seed a corrective run's control initials from the validated
preventive settings. A solver's infeasible termination is retained and is not
treated as a physical infeasibility certificate.

`result.tap_settings` and `result.shunt_settings` are scenario-indexed maps of
the selected controls only. Fixed-base evaluation accepts an `ACState`; studies
with selected equipment must also pass the exact saved base maps through
`fixed_base_tap_settings` and `fixed_base_shunt_settings`. Missing or extra
settings are rejected rather than guessed.

M9.3 pairs two assessments around that same saved base:

```julia
assessment = assess_scopf_response_stages(
    immediate_preventive_study,
    settled_corrective_study,
    validated_base_result,
)
write_scopf_stage_assessment("stages.json", assessment)
println(markdown_report(assessment))
```

The immediate study must freeze taps and shunts. The settled study may apply
M9.2 budgets. The report compares voltage, thermal and generator-Q margins plus
equipment movement. It represents two steady-state equilibria, not elapsed
time, dynamics, switching sequences, or transient stability.

## Independent acceptance checks

`equilibrium_report(study, result)` rebuilds the outage cases and checks AC
balance, both ends of branch flows, generator and voltage limits, exact droop
replay, disabled generators, reference angles, active-response coupling, and
equipment timing. For every scenario it reconstructs a physical network from
the reported tap and shunt settings before calculating residuals. Missing,
out-of-bounds, nonfinite, or unexpectedly present settings are rejected; for
preventive controls, deviation from the base setting is reported separately as
`equipment_coupling_violation`.
The report records tolerances and scenario-specific failures.

- `physical_valid` requires exact-curve equilibrium and all physical/coupling checks.
- `encoded_physical_valid` checks the numerical droop encoding in place of exact replay.
- `valid` additionally requires a successful solver termination. For a fixed-base
  evaluation with no contingencies there is no optimization; status is `:NOT_RUN`
  and independent feasibility alone determines validity.

The report lists exact and encoded droop residuals separately, along with their
smoothing gap. Default power/limit/coupling tolerances are `1e-6`, exact and
encoded droop tolerance is `1e-5`, and unavailable-generator tolerance is `1e-8`.
Tolerances are explicit keyword arguments. These checks certify only the
reported equilibrium to those tolerances, not global optimality, uniqueness,
transient stability, or frequency response.

## Reproducibility

Run from the repository root:

```sh
julia --project=. examples/m2_workflow.jl /tmp/droopopf-m2
```

The example writes a study, result, and validation report as JSON, plus a Markdown
report. It reloads the JSON files, independently validates the restored result,
and deliberately corrupts an outage result to demonstrate rejection.

The M9.1 workflow stages a preventive continuous tap/shunt SCOPF from a
fixed-equipment witness, then solves a separately declared corrective-timing
study. Both are independently validated and persisted:

```sh
julia --project=. examples/m9_1_equipment_scopf.jl /tmp/droopopf-m9-1
```

```julia
write_study("study.json", study)
write_scopf_result("result.json", result)
write_scopf_report("report.json", report)
restored_study = read_study("study.json")
restored_result = read_scopf_result("result.json")
restored_report = equilibrium_report(restored_study, restored_result)
```

## Visual validation

The end-to-end workflow writes nine self-contained SVG figures. Five detailed
operating plots are retained:

- `m2_droop_operating_points.svg` overlays base and contingency operating
  points on the exact volt-var curves. Marker shape identifies the scenario;
  curve colour identifies the control.
- `m2_bus_voltages.svg` compares each bus across scenarios and shows its
  allowable voltage interval behind every operating point.
- `m2_branch_loading.svg` reports apparent-power loading as a percentage of
  rating, draws the 100% threshold, and marks outaged branches with a cross.
- `m2_generator_dispatch.svg` compares active and reactive generation and
  marks outaged generators.
- `m2_validation_residuals.svg` plots AC-balance, exact-droop, and response
  residuals divided by their acceptance tolerances. The horizontal threshold
  is one; bars below it pass.

Four cross-scenario evaluation plots connect declared inputs to independently
checked outputs:

- `scopf_declared_inputs.svg` lists each outage, active-power response policy,
  and preventive/corrective tap and shunt timing;
- `scopf_operating_margins.svg` shows voltage, thermal, generator-P, and
  generator-Q margins, with near-limit and violated cells highlighted;
- `scopf_response_deltas.svg` compares maximum voltage, angle, active-power,
  and reactive-power changes from the saved base state on a logarithmic scale;
- `scopf_validation_matrix.svg` maps every scenario to independent state,
  balance, droop/AVR, voltage, thermal, capability, availability, response, and
  equipment checks. It is intentionally writable for invalid results so
  negative controls and failed solves can be investigated visually.

Generate the complete bundle with:

```julia
paths = write_scopf_validation_plots("m2-validation", study, result)
```

Individual writers are available when only one view is needed:
`write_scopf_droop_plot`, `write_scopf_voltage_plot`,
`write_scopf_branch_loading_plot`, `write_scopf_dispatch_plot`, and
`write_scopf_residual_plot`. A missing scenario state or a result whose
scenario set differs from the study is rejected instead of producing a partial
figure. The graphics explain a validated result; the independent numerical
report remains the acceptance authority.

Run `julia --project=. examples/scopf_edge_case_evaluation.jl OUTPUT` to produce
matched bundles for an accepted base/line/generator study and a deliberately
invalid negative controls with nonzero reactive output on the outaged generator,
missing state, excessive voltage, and altered active generation. These corruptions
test validation sensitivity; they are not feasible stressed operating points.
The example also solves changed-input cases with tight thermal ratings and
insufficient post-generator-outage capacity, retaining rejected results for review.
Each directory includes `evaluation.md`, which embeds all nine figures and the
authoritative numerical validation report in one reviewable input/output index.
The report separates solver acceptance, exact physical validity, and encoded
physical validity, states assumptions and tolerances, and saves complete
`evaluation-inputs.json`, `evaluation-outputs.json`, and `evaluation-validation.json`
records. Loading plots reconstruct solved taps and shunts. Missing or malformed
states produce NOT EVALUATED cells and labelled gaps rather than passes.
Available scenarios remain visible; voltage trajectories never bridge a missing
scenario. Without a base, voltage/loading/dispatch plots still show available
outages, but base-relative deltas are unavailable. Legacy droop plots are N/A
for free-Q/explicit-assignment studies. Independent numeric checks remain the
authority, including for solver-rejected states that can still be inspected.
PASS is limited to the declared scenarios and checks, not dynamic security or
global optimality. Optional `context` text labels the provenance of each bundle.

The same example now produces a single root `evaluation.md` linking all
evidence: accepted/corrupted three-bus states; two-bus thermal, voltage,
reactive-capacity and non-unity-transformer fixtures; exhaustive filtering
comparisons and budget plots; and a loaded five-bus island campaign. Interior
bases are chosen with AVR targets (1.009 pu for the tight-voltage fixture,
1.0 otherwise), while the declared post-outage reactive response is free Q
within limits. A deliberately disabled-voltage-guard run tests the benchmark's
ability to identify false screens. Retained island validity is reported beside
excluded demand and reference choice; it never implies that discarded islands
were balanced. This is small-network qualification, not operational deployment
certification. Large public networks remain S1/S2 reliability/robustness inputs
only, never unit-test fixtures.

Qualification snapshot (2026-10-03): the five guarded two-bus fixtures covered
20 connected outages, including six unresolved outcomes. Six branch outages
were screened with zero observed misses. Disabling the voltage guard on the
tight-voltage fixture produced two false screens (one line and one transformer),
both detected by the exhaustive comparison. All four loaded island branch
outages validated on their retained components while explicitly reporting
excluded demand (0.03 or 0.12 pu). Campaign replay reused all seven island-case
checkpoints without executing another route. The full unit suite passed
2,574/2,574 tests in 3m50.9s; the documentation build passed with its API-page
size warning only. SVGs were rendered and representative accepted, missing,
rejected, ranking and island figures visually inspected. The generated evidence
index is `artifacts/scopf_validation/evaluation.md`; regenerate it using the
example above. These are fixture-level observations, not held-out certification.

JSON documents use a document-kind tag. Study schema v10 and result schema v5
persist optional reactive-control assignments, selected tap/shunt policies,
the timing/movement policy, and scenario equipment settings, with an explicit
limit-aware active-response marker. Historical coupled preventive documents
without the marker require their original source for replay. Supported uncoupled
and corrective documents retain the existing equipment/attachment migrations.
Selected equipment policies default to corrective timing; unselected taps and
shunts remain supplied fixed data.
Study files contain all case data, contingencies,
and response policy. Result files contain scenario states, active-response request signals,
equipment settings, solver/status, encoding, and smoothing widths.
Nonfinite diagnostics are written as JSON `null`; missing states remain `null`.
Report files are diagnostic exports; reports are regenerated from study/results,
not trusted as proof of validity. Save the Julia project/manifest alongside an
experiment when exact dependency versions matter.
