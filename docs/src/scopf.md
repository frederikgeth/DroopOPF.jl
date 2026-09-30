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
```

The default unit suite exercises catalog ordering, full eligible enumeration,
fixed-base validation, accepted/unresolved classification, ranking, JSON
persistence, structural island detection, retained-component balancing,
production-filter routing, screening scores, and sparse model
construction on synthetic networks of eight buses or fewer. IEEE-118 and
IEEE-300 are excluded from unit tests and reserved for S1/S2 and explicit M10
reliability campaigns.

Use normal Julia compilation for performance runs. The supervisor no longer
uses `--compile=min`, which slows numerical model construction. Power-balance
expressions for the imported FreeQ baseline contain only nonzero admittance
entries; this preserves the equations while avoiding dense derivative graphs.
Declared reactive-control paths retain their existing expression ordering to
preserve sensitive CCOpt warm-start trajectories. Each completed baseline
writes `timing.json` separating construction (including first-call compilation)
from optimization and extraction. Compare warm runs in the same Julia process
when measuring sustained throughput; a fresh process pays compilation again.

On the development machine, the first IEEE-118 branch-outage evaluation with
the saved base reduced equality-Jacobian entries from 55,606 to 2,028.
The original Ipopt solve took 5.95 seconds; the sparse warmed evaluation took
0.33 seconds (0.36 seconds including validation and persistence). The complete
first runner call took 24.36 seconds, including compilation but excluding package
startup and a new base solve. Both formulations returned the same 44-iteration
local-infeasibility outcome, with constraint residual approximately 6.67e-4.
These are single-case measurements, not a convergence or campaign-time guarantee.

For complete enumeration, run `examples/m10_campaign.sh 118 OUTPUT`. The campaign
loads the case and validated base state once, evaluates every eligible outage in
one Julia process, and persists each outcome before continuing. Re-running the
same command resumes explicitly completed outcomes. Optional positional arguments
select the first and last eligible catalog indices, per-outage solver seconds,
and iteration limit. `campaign.json` and `campaign.md` distinguish completion,
accepted results, physical-only results, invalid results, and execution errors.
The aggregate ranking contains completed exact evaluations only; it is produced
after evaluation and is not a pre-solve filter.

`contingency_catalog(case)` deterministically enumerates every available
single branch and generator outage. Each candidate records its device ID and a
structural disposition. Connected outages and generator outages are
`eligible`; a branch outage that islands the network is retained as `excluded`
from the original single-component evaluator with reason
`islanding_unsupported`. It can instead be passed to
`evaluate_islanding_contingency`. That path retains the original-reference
component unless another component has strictly more buses. If the larger
component is selected, the bus of its available generator with greatest
`p_max` becomes the reference (generator ID breaks ties). Only the retained
component is balanced; discarded buses, load, and generation capacity are
reported and are never classified as served or safe.

`filter_contingencies` is a conservative routing layer. Generator outages go
to exact AC evaluation. Structurally islanding branch outages go to the
island-aware evaluator. Connected branch outages use a DC LODF estimate and
are screened only when predicted loading is below the declared threshold and
the base voltage is outside the guard band. Singular or uncertain calculations,
near-limit base voltages, and predicted thermal risk all fall back to exact AC
evaluation. Screening is a workload decision, not an AC security certificate;
thresholds require held-out reliability qualification before operational use.

The diagnostic baseline runner evaluates a numbered batch against one
independently validated, fixed base OPF state:

```sh
julia --project=. examples/m10_contingency_baseline.jl 118 artifacts/m10/ieee118-batch001 1 1
```

It writes both the complete catalog and the exact outcomes for that batch.
The first batch creates a source-hashed `ieee118-base-state.json` beside the
batch directories; later batches reuse that state only after independently
revalidating it. Thus every batch assesses the identical, solver-accepted base
without repeatedly optimizing a new base dispatch.
The runner writes `run-policy.md` before solving. Its default 120-second
Ipopt CPU-time and wall-clock limits, plus its 1,000-iteration limit, apply
independently to the base and each contingency batch. They begin after model
construction, so production runs need an external process supervisor for an
end-to-end budget. A bounded solver failure is retained as an unresolved
outcome; it is never converted into a safety or screening assertion.

Use the supplied POSIX supervisor for a bounded batch. It records its own
completion or timeout in `supervisor.md` and retains `run.log` even if the
child never reaches Ipopt. An operating-system CPU-limit signal is explicitly
recorded as `cpu_limited_unresolved`:

```sh
sh examples/m10_supervised_batch.sh 118 artifacts/m10/ieee118-batch001 1 1 180
```

For production enumeration, use `m10_campaign.sh` to execute a resumable range
in one Julia process. Compilation is reused, every outcome is persisted before
the next solve, and invalid outcomes do not stop later evaluations:

```sh
sh examples/m10_campaign.sh 118 artifacts/m10/ieee118-campaign 1 all 120 1000
```

After enumeration, generate metric-specific coverage and diagnostic rankings:

```sh
julia --project=. examples/m10_campaign_report.jl artifacts/m10/ieee118-campaign
```

Only after complete exact enumeration, benchmark the inexpensive base-state
loading/outage-size heuristic:

```sh
julia --project=. examples/m10_screening_benchmark.jl artifacts/m10/ieee118-campaign
```

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
Constraint generation and parallel execution remain outside the current scope.

## Response contract

All active/reactive powers and redispatch limits are per-unit on `case.base_power`;
voltage magnitudes are per-unit and angles are radians. Positive P/Q means network
injection. The reference bus fixes only its angle; it does not supply unbounded
balancing power. All available generators retain their capability bounds.

Preventive mode uses a base schedule and a prescribed automatic balancing policy:

```math
P_{g,c} = P_{g,0} + \alpha_{g,c}\Delta_c,\qquad
\alpha_{g,c}=\frac{w_g}{\sum_{h\text{ available in }c}w_h}.
```

Participation weights are supplied explicitly, must be nonnegative, and are
normalized over surviving generators. Unlisted generators have zero weight.
Every contingency needs a surviving participant. The scalar `Δ` represents
active power needed for lost generation and changes in AC losses. It is **not a
frequency deviation** or a dynamic governor model. Participants must remain
within their bounds; there is no automatic redistribution when one saturates.
Optional `redispatch_limits` also bound each participant's change from base.

Corrective mode replaces this participation equation with:

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
    taps = :preventive,       # default
    shunts = :preventive,     # default
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

Preventive equipment has one setting shared by the base case and every
scenario in which the device remains available. Corrective equipment has an
independent bounded setting in each scenario. These options may be selected
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
    participation = Dict(7 => 1.0, 9 => 1.0),
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

The end-to-end workflow also writes five self-contained SVG figures:

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

JSON documents use a document-kind tag. Study schema v8 and result schema v4
persist optional reactive-control assignments, selected tap/shunt policies,
the timing/movement policy, and scenario equipment settings. Older supported documents
reload with legacy attachment semantics, no optimized equipment, and the
default preventive policy. Study files contain all case data, contingencies,
and response policy. Result files contain scenario states, balancing powers,
equipment settings, solver/status, encoding, and smoothing widths.
Nonfinite diagnostics are written as JSON `null`; missing states remain `null`.
Report files are diagnostic exports; reports are regenerated from study/results,
not trusted as proof of validity. Save the Julia project/manifest alongside an
experiment when exact dependency versions matter.
