# Transformer and switched-shunt extension

Updated planning scope, 2026-09-19. Branch `transformers` starts at local `main`
commit `e4d68ed` (v0.4.0). This revision records the agreed continuous-first direction and the AVR extension;
M5.1-M5.4 and M6.1-M6.3 are implemented and validated below; later slices remain planned.
ROADMAP.md owns sequencing and status; this branch is not a new release.
This is a selective extension of current main, not a copy of the earlier
brainstorming worktree's M5-M13 numbering.

## Pre-M5.1 architecture review — confirmed

Confirmed by the user on 2026-09-18 as the architecture baseline for M5.1.
M5.1-M5.4 and M6.1-M6.3 are implemented and validated on this branch; later slices remain pending.
Milestone order is unchanged. Preserve the four
boundaries: data, optimization problem, formulation, and independent validation.

1. **Common branch physics.** Extend `Branch` with `tap_ratio=1` and
   `phase_shift=0` (radians), with the complex tap on the declared from side.
   Require finite positive ratios and finite angles. Preserve legacy public
   constructors, numeric conversion and unity-tap behavior. Do not introduce a
   second transformer network/solver. Adjustable phase control remains deferred.
2. **Physical data versus control policy.** M5.1 stores fixed electrical settings.
   Later tap capability records attach to branch IDs; AVR is a separate attached
   controller. Bounds/legal positions must come from supplied equipment data,
   never be invented from a MATPOWER ratio. M6 shunts are explicit bus equipment,
   separate from constant-power loads and branch charging. Study policy will
   select fixed, continuous-optimized or AVR-controlled taps; one mode per device.
3. **Inputs versus solved settings.** Keep `ACState` as voltages and generator
   injections for M5.1. Future optimized/AVR settings belong in a separate result
   payload keyed by equipment and scenario (later period); do not overwrite case
   inputs. Fixed-equipment reports identify the exact supplied settings. Defer
   concrete result types until M7, while requiring this separation now.
4. **Preservation and schema migration.** Update all branch reconstruction paths,
   including `ACNetwork`, `Case`, and `scenario_case`. New study JSON uses schema
   v2; the reader accepts v1 with unity/zero defaults and requires explicit fields
   in v2. Version handling is by document kind, so unchanged result/report formats
   need not migrate. This prevents older readers silently discarding new physics.
   MATPOWER TAP=0 maps to unity and SHIFT degrees convert once to radians.
5. **Incremental support must be explicit.** M5.1 can import and round-trip data,
   but evaluation, solving and validation must reject nontrivial equipment until
   the relevant M5.2-M5.4 path supports it. Never silently use unity-tap equations.
   The same rule applies to nonzero imported bus shunts before M6 support.
   Later formulations share the electrical convention across backends; validation
   evaluates terminal currents outside optimizer expressions, backed by hand
   calculations to catch errors shared between implementations.
6. **M5.1 acceptance evidence.** Test defaults, invalid/nonfinite settings, units,
   v1 migration/v2 round trips, numeric conversion, case copying, contingency
   preservation and unsupported-path rejection. Produce a small import/copy
   report with expected versus actual values and a labelled two-bus diagram
   showing from-side ratio and shift. AC-flow accuracy starts in M5.2; M5.1 must
   not claim it. Resolve dependencies and establish baseline tests before coding.

Defer the exact variable-building API, continuous shunt envelope, discrete
recovery, AVR complementarity/deadband selection and security-stage coupling to
their respective milestones. Continuous optimization remains the main route;
discrete options remain optional. No new generic framework is needed for M5.1.

## Current-main audit

| Milestone | Evidence in current main | Status |
|---|---|---|
| M1 | `src/physics.jl`, `src/jump.jl`, `src/complementarity.jl`, `src/validation.jl`; network/curve/OPF tests | Released 0.1.0 |
| M2 | `src/scopf.jl`, `src/contingencies.jl`, `src/scopf_validation.jl`, `src/scopf_io.jl`; tests include dispatch-changing security case, outages, coupling and serialization | Released 0.2.0 |
| M3 | `src/droop_optimization.jl`, `src/droop_sweep.jl`; bounded slope/reference/deadband optimization shared over SCOPF and held-out evaluation | Released 0.3.0 |
| M4 | Multi-start and diagnostics modules, `test/test_robustness.jl`, pinned PGLib cases and `docs/src/scale_up_decision.md` | Released 0.4.0; no scaling algorithm justified |

The audit confirms implementation and test coverage in source, not a blanket
guarantee for unsupported equipment. `Branch` contains impedance, charging,
thermal rating and availability but no ratio or phase shift. `Bus` has no shunt
equipment. The adapter reads neither branch TAP/SHIFT nor bus GS/BS into physical
data. Line charging is already modeled; it is not a switched bus shunt.
`docs/src/robustness.md` explicitly limits the public fixtures to cases without
bus shunts or non-unity taps. Arbitrary PWL topology, general objective selection,
sensitivity design and multi-period studies are not implied by M1-M4 completion.

Implementation update, 2026-09-18: dependency instantiation resolved the initial
missing-JuMP issue. The unchanged M1-M4 baseline passed 338/338 tests. M5.1 adds
transformer data/import, preservation, study schema migration and support guards;
the extended suite passed 386/386 tests. The audit above describes the original
main commit, not the extended branch. See [M5.1 evidence](artifacts/m5_1/report.md)
and `examples/m5_1_transformer_data.jl`. M5.2-M5.4 now add fixed transformer AC physics,
both-terminal limits and OPF/SCOPF/droop-design integration. At M5 completion, the full suite
passed 440/440 tests; [M5 evidence](artifacts/m5/report.md) includes analytical
sweeps, scenario plots and independent checks. M6.1 subsequently added fixed shunt import, separate equipment records and
current-based validation (2026-09-19), with 568/568 full-suite checks passing.
See [M6.1 evidence](artifacts/m6_1/report.md). Switched-bank and integration evidence is in [M6](artifacts/m6/report.md).

## Required boundaries

| Layer | Extension |
|---|---|
| Data | Immutable equipment IDs, electrical parameters, positions, legal choices, availability and import provenance |
| Optimization problem | Independent fixed/free settings, scenario sharing, corrective permissions and movement limits |
| Formulation | Position-aware AC equations, supported continuous/discrete encodings and explicit solver capability checks |
| Validation | Independently recomputed electrical results, legal positions and inter-scenario control-policy checks |

Keep physical representation, decision freedom and coordinated response separate.
Fixed means the equipment remains in the network at its specified position.
Automatic local action is a separate operating policy, not implicit in optimizing
a tap or bank state. Result and JSON schema changes need defaults/migration tests
for existing M1-M4 inputs; starts do not become nominal design references.

## M5: transformer reference physics — complete on this branch

Implementation: `_branch_admittances` supplies optimizer Ybus and a shared
two-terminal thermal-limit builder for the smooth and complementarity paths.
`branch_flows` independently evaluates internal voltage and series current;
`power_balance` sums those terminal powers. No optimizer expression is used by
physical validation. M5.1 guards for these supported features are retired.

Evidence: `test/test_transformer_physics.jl` and the reproducible
`examples/m5_transformer_workflow.jl`. The synthetic case uses declared starts;
CCOpt requires tighter relaxation/bound settings for exact-droop acceptance.
Failed exploratory settings are retained under `artifacts/m5/diagnostics`.
This is an implementation milestone, not a new release or an arbitrary-start
convergence claim. M6 onward and optional discrete branches are unchanged.


Deliver a supported two-terminal complex tap on the declared from side, including
fixed phase shift. Preserve unity-tap line behavior. For series admittance y,
total charging b and complex ratio a = tau exp(j phi), adopt and document:

    Yff = (y + j b/2) / |a|^2;  Yft = -y / conj(a)
    Ytf = -y / a;              Ytt = y + j b/2

Compute terminal currents from this primitive and terminal powers from V conj(I).
The independent validator must test equivalent direct terminal-current calculations
against analytical/reference fixtures rather than merely reuse optimizer expressions.
Import TAP=0 as unity and SHIFT in degrees with explicit conversion; retain rating,
orientation and availability. Test construction, copying, scenario overlays and
JSON round trips. Existing fixed-equipment M2/M3 studies must preserve these fields.
Reject unsupported transformer features explicitly; three-winding, magnetizing
models and controllable phase shifters are outside the initial slice.

Exit: unity-ratio regression; non-unity and nonzero-phase analytical fixtures;
reverse-end flows and both terminal limits; transformer outage zero flows;
deliberate sign/ratio perturbation detected; supported solver paths checked or
unsupported combinations rejected without silently using line equations.

## M6: fixed and switched-shunt reference physics

M6.1 is complete: `FixedShunt`, `ACNetwork.shunts`, MATPOWER GS/BS conversion,
independent `shunt_powers`, preservation and schema migration. M6.2 and M6.3
are also complete: explicit legal bank states and fixed-state OPF/SCOPF integration.
See [M6 evidence](artifacts/m6/report.md). `examples/m6_1_fixed_shunts.jl` generates conversion tables,
analytical/computed voltage curves and error-detection plots. No switching state,
bank grid or controller is inferred. Study v4 supersedes earlier writers while retaining v1-v3 readers. Negative conductance is rejected for passive equipment.


Represent fixed bus admittance plus identified switchable banks with supplied
positions. Specify B positive capacitive and G positive consuming: network shunt
consumption is P=G V^2, Q=-B V^2. Injection signs follow from the declared balance
convention; account for the admittance once. Import GS/BS using baseMVA and rated
unit-voltage meaning. MATPOWER bus data supply aggregate fixed admittance, not
bank identities or legal switching steps; these require explicit additional data.

Bank data include step admittances, legal combinations, nominal/current positions
and availability. M6 fixes all positions during the solve. Reuse the same physics
in base OPF, SCOPF and bounded droop design. No constant-Q approximation.

Exit: capacitive/inductive signs; V-squared scaling; nonzero conductance; unavailable
bank; invalid position; fixed-plus-bank accounting; import/serialization fidelity;
deliberate missing/double shunt injection rejected; legacy zero-shunt regression.

## Validation slices for M5 and M6

Each slice produces the validation bundle defined below. Acceptance is numerical;
visuals make the physical behavior and failures inspectable.

| Slice | Small change | Validation and required visual |
|---|---|---|
| M5.1 | Transformer data/import/serialization | Round-trip field table; tap-side/orientation diagram; reject invalid ratios |
| M5.2 | Fixed magnitude ratio, zero phase shift | Hand-calculated terminal currents/powers; reference-versus-computed flow plot; unity-ratio regression |
| M5.3 | Fixed phase shift and availability | Signed flow versus phase shift; both-end limits; outage zero-flow checks and deliberate sign error |
| M5.4 | Fixed transformer in existing OPF/SCOPF | Base/contingency voltage and terminal-flow panels; independent residuals and exact droop checks |
| M6.1 **complete** | Fixed shunt admittance and import | GS/BS conversion table; analytical and computed P(V), Q(V) curves; sign and double-count checks |
| M6.2 **complete** | Bank data at supplied legal states | Bank-state/admittance table and Q-by-state plot; invalid/unavailable state checks |
| M6.3 **complete** | Fixed shunts in existing OPF/SCOPF | Voltage profiles and reactive-balance breakdown; scenario residuals; zero-shunt regression |

## M7: continuous equipment optimization — primary path

M7.1-M7.3 are implemented on `transformers`.
The [validation report](artifacts/m7_1/report.md) compares fixed, one-free-tap and
two-free-tap cases with a 41-point fixed-tap sweep. Each case uses fixed shunts,
droop curves and phase shifts. `TapControl` selects a branch with explicit bounds,
optional initial ratio and nominal reference. Unselected branches stay fixed.
`TapOPFResult` stores solved settings separately; `with_tap_settings` reconstructs
physical data for independent validation. `optimize_taps(Study, ...)` rejects
optimized equipment SCOPF until M9. Ratios are continuous relaxed outputs.


Preserve discrete equipment data, but optimize tap ratio tau and shunt susceptance
B continuously within declared physical envelopes by default. Fixed modes remain
available independently for every device and droop setting. Phase shift remains
fixed in this scope. Document whether conductance stays fixed or follows a bank
mapping; arbitrary independent G/B freedom must not be introduced by relaxation.
M7.2 is restricted to one nonzero capacitor/reactor step type per bank. Its legal
counts define the continuous B interval and G follows the same fractional count.
Heterogeneous relaxation and complex switching combinations are post-scaling
backlog: first benchmark simple banks, transformers and droops together. Existing
fixed heterogeneous states remain supported; their optimization is not part of M7.2.

| Slice | Small change | Validation and required visual |
|---|---|---|
| M7.1 **complete** | Continuous tap optimization; shunts/droop fixed | Fixed-bound equivalence; bound checks; objective/feasibility versus ratio sweep and selected solution |
| M7.2 **complete** | Simple capacitor/reactor banks; taps/droop fixed | V-squared injection and bounds; objective/feasibility versus susceptance sweep |
| M7.3 **complete** | Joint equipment and existing M3 droop design | Independent fixed/free flags; matched configuration grid with selected settings, validity and objective components |

Reuse the existing NLP path and baseline objective first. Add only needed
quantities with independently evaluated raw values and explicit normalization.
Record relaxed settings separately from legal physical positions. Continuous
movement measures are not switching-event counts. A locally solved relaxation
is not a certified lower bound on the discrete optimum or proof of scalability.

## M8: continuous steady-state transformer AVR — deferred

Attach a voltage controller to transformer equipment without changing its
electrical representation. Per study/device select exactly one mode: fixed tap,
OPF-optimized tap, or AVR-controlled tap. The AVR owns regulated location, fixed
target, control direction, optional deadband and tap bounds. It does not grant
an independently optimized tap while simultaneously claiming a fixed AVR policy.

| Slice | Small change | Validation and required visual |
|---|---|---|
| M8.1 | One transformer, one bus, zero-deadband target with tap limits | Interior target tracking and both saturation regimes; regulated voltage and ratio versus load, with bounds and target |
| M8.2 | Fixed deadband and explicit settled-state selection | Inside/outside-band and limit tests; voltage-band diagram and feasible/selected tap interval |
| M8.3 | Compare fixed, optimized and AVR-controlled taps under fixed/optimized droop | Common-case mode comparison showing voltage error, Q effort, tap ratio and limit exposure |

Interior control seeks Vreg=Vset; at a bound permit only the residual-error sign
consistent with the declared orientation and control direction. Validate direction
on the fixture and fail/flag unsupported behavior. Implement a documented active-set
or complementarity encoding; smoothing must report its exact-regime mismatch.
An impossible target must produce a classified saturated/unmet-target state,
not hidden voltage-target relaxation or a false regulation success.

A deadband defines an acceptable settled-state set, not a unique reached position.
Record whether the result is merely a feasible settled state or uses an explicitly
declared selection rule. If OPF selects among deadband equilibria, label it as
coordinated selection, not autonomous AVR behavior. No switching-count claim
follows. Initial-position-dependent settling belongs to a later sequential runner.
Multiple AVRs on the same regulated bus are initially unsupported unless an
explicit coordination policy is added and independently tested.

Dependency: M8 can start after M5.4; it need not wait for shunts or joint M7.3.
Targets and deadbands remain fixed policy inputs initially. Co-design of AVR
targets with droop is a later explicit experiment, not hidden corrective freedom.

## M9: equipment response in SCOPF (AVR stages deferred)

Extend M2/M3 builders and validators. M5/M6 already provide fixed-equipment SCOPF;
this milestone adds decision sharing and response-policy coupling.

| Slice | Small change | Validation and required visual |
|---|---|---|
| M9.1 | Shared preventive continuous tap/shunt settings | Scenario-by-device setting table; no-contingency equivalence; independent shared-setting perturbation check |
| M9.2 | Explicit bounded corrective equipment settings | Base-to-contingency ratio/B movement versus permitted bounds; preventive/corrective margin comparison |
| M9.3 **deferred** | Before-tap-response and AVR-settled contingency assessments | Paired voltage/thermal/Q margins, frozen versus settled taps, target errors and saturation status |

M9.1/M9.2 require applicable M7 controls; M9.3 additionally requires M8. Before
permitted tap response, freeze positions at their pre-event values. After AVR
settling, enforce the declared AVR policy and limits. These are two steady-state
assessments, not a simulated transient trajectory. Match active dispatch recourse
and operating-limit assumptions to each response stage and report them explicitly.
Both stages are required when claiming security at both response stages.

Installed droop parameters and fixed AVR targets stay shared across design cases.
Outages do not automatically authorize equipment movement. Preserve availability,
unsupported-island diagnostics, schema round trips and failed-scenario coverage.
Independently detect illegal corrective actions even when per-scenario AC states
are feasible. Optional discrete recovery must preserve the same sharing/recourse
policy across all cases rather than round each case independently.

## M10: comparative evidence and regression gate

| Slice | Small change | Validation and required visual |
|---|---|---|
| M10.1 | External/reference equipment physics | Trusted versus computed terminal quantities and error plots; sourced case with nontrivial taps/shunts |
| M10.2 | Matched droop/equipment/control-mode studies | Configuration comparison, interaction effects and held-out margins; separate relaxed results and any physical recovery |
| M10.3 | Reproducibility and performance review | M1-M4 regression results, multi-start spread, coverage, schema checks and build/solve/validation timing plots |

Consolidate evidence already produced by each slice; do not postpone testing to
M10. Report losses, voltage margins, reactive effort/reserve, exact droop error,
tap/bank settings, AVR target error and limit exposure. Action counts are meaningful
only for discrete settings with explicit transitions; continuous displacement is
reported in ratio or susceptance units. Compare droop methods under identical
equipment freedom to avoid attributing extra fractional flexibility to droop.

## Optional discrete verification and solution branches

- D1, after M7.1/M7.2: enumerate small legal position sets for integration checks,
  sweeps and comparisons. Use analytical fixtures for elementary unit tests.
- D2, after M7 and applicable M9 coupling: recover legal positions from relaxed
  solutions and re-solve the full selected AC/SCOPF problem. Preserve installed
  droop when assessing its realizability; any droop retuning is a separate study.
  Report feasibility loss and objective change, with no certified gap claim.
- D3: mixed-integer formulation only after a supported backend and a clear use
  case are selected. It is not a required dependency of ordinary tests.

Each optional branch reports attempted, failed and valid assignments. Discrete
checks are valuable evidence but are not the primary large-case optimization
path. Fractional solutions must never be labelled implementable tap/bank schedules.

## Mandatory validation bundle for every slice

One runnable command must produce:

1. Inputs/provenance, units, fixed/free/control modes, solver/encoding, reference
   quantities, declared response policy and tolerances.
2. Machine-readable states/settings, expected/computed values, errors, numerical
   pass/fail checks and failed/unavailable coverage.
3. A readable report separating solver status, physical validity, operating-limit
   compliance, equipment-policy compliance and AVR target satisfaction.
4. The slice-specific plots/tables above, using comparable axes and visible limits
   or tolerances where applicable. Include failed cases rather than hiding them.
5. Focused positive and deliberately perturbed negative tests, with immutable raw
   inputs, reproducible starts and exact-physical checks outside the optimizer.

Reporting and visualization are acceptance requirements, not a later milestone.
Visual agreement never replaces numerical validation. Larger publication-quality
comparisons assemble these bundles rather than invent a second evaluation path.

## Scope and readiness

M5.1-M5.4 and M6.1-M6.3 are implemented and validated; later slices are agreed direction / pending
implementation. For each next slice, choose its fixtures, tolerances and supported
solver combinations; settle AVR encoding when approaching M8. Each issue lists
data, optimization-problem, formulation and validation changes separately.

Sequential tap/shunt controllers with delay, dwell, discrete step selection,
event order and hunting detection remain a later optional milestone. Steady-state
AVR with a deadband does not implement that runner. Automatic shunt regulation,
multi-period schedules, sensitivity synthesis, adjustable phase-shift control
and full observed-state reconciliation remain outside this equipment branch.
ROADMAP.md is authoritative; this proposal does not replace delivered M1-M4.

### M7.2 evidence and scope

[Report and plots](artifacts/m7_2/report.md) retain 31-point capacitor and reactor
sweeps, fixed/one-free/two-free comparisons and admittance-envelope plots. A
`ShuntControl` selects a bank, with optional bounds inside its legal-count envelope,
and separate initial/nominal B. Unselected banks and fixed shunts remain unchanged.
Mixed step types are rejected for optimization. One variable B determines both
reactive injection and conductance loss. Result JSON preserves the problem policy
and solved relaxed B. Independent replay substitutes selected banks with equivalent
fixed admittances once; original equipment metadata are preserved in the input.

### M7.3 evidence

The [joint-design report](artifacts/m7_3/report.md) records all eight tap/shunt/droop
fixed/free configurations, two starts per configuration, objective decomposition,
physical metrics, setting/parameter spread and matched droop benefits at each
equipment freedom. The objective has no design penalty in any configuration.
`DroopControl` reuses the M3 parameter family with independent bounds; omitted
parameters are fixed. Base-case standalone comparisons use matched starts because
local optima can depend on initialization. [The documentation gallery](docs/src/equipment_optimization.md)
embeds numerical tables and figures for all M7 slices. Results are continuous and
local; M9 adds security-constrained equipment decisions.

## Revised execution priority (2026-09-20)

AVR (M8 and M9.3) joins complex-bank optimization in the post-scaling backlog.
Its specification is preserved for later review. Work now follows the ROADMAP's
S1 base-case gate, M9.1 preventive sharing, M9.2 bounded corrective equipment, and
S2/M10 security scaling. M10 applies to supported simple models first; it does not
wait for deferred AVR features. Initial synthetic evidence is in
[the connected scaling experiment](artifacts/scaling_initial/report.md).
Report failure coverage, validated AC/policy feasibility and meaningful timing/size
curves. Medium public networks and diverse starts remain required before claiming
robustness beyond the structural fixture. Continuous settings are not executable
switch schedules without legal-position recovery and fresh validation.

## S1 — Reliable optimization convergence and scaling

Status: dedicated active milestone after M7 and before M9.1. Initial synthetic
experiments are retained evidence, not acceptance of this milestone. AVR (M8 and
M9.3) and complex-bank optimization remain deferred. ROADMAP owns sequencing.

| Slice | Deliverable | Acceptance and reporting |
|---|---|---|
| S1.1 — Mathematical contract | Write the implemented base-case joint NLP explicitly, then map equations to builders and validators | Variable/bound table; transformer terminal powers with tap and phase; fixed and simple-bank G/B terms; AC balances; exact and smooth droop; objective; fixed/free selection. State units, signs, smoothing and relaxation assumptions. Review discrepancies before changing a model. |
| S1.2 — Convergence diagnostics | Retain iteration logs, primal/dual residuals, complementarity, bound activity, iteration counts and termination reasons | Reproduce 12- and 96-bus stalls; distinguish AC/policy feasibility, exact-droop validity and solver stationarity. Plot residual histories and retain failed runs. |
| S1.3 — Isolate control families | Fixed, droop-only, tap-only, bank-only, pairwise and joint cases; vary the number of free controls independently | Matched starts/objectives, timing and success tables. Identify the family or interaction responsible for deterioration without selecting only successful cases. |
| S1.4 — Numerical conditioning | Check derivatives, variable/objective scaling and smoothing near droop breakpoints | Derivative comparisons and conditioning diagnostics; map any equivalent scaling back to original units. Physical validation tolerances and baseline objective are unchanged. Any proposed non-equivalent model or objective change is surfaced to the user first. |
| S1.5 — Initialization and solver robustness | Feasible fixed-control starts, staged release, smoothing continuation and matched Ipopt/MadNLP comparisons | Multiple declared state/design starts; complete success/failure coverage; objective and parameter spread; primal/dual stationarity and timing. More iterations alone do not establish reliability. |
| S1.6 — Larger-network acceptance | Pin a public 118-bus case, then a 300-bus case; document controller overlays; retain synthetic count sweeps | Independently validate imported fixed-equipment baselines before adding controls. Grow droop/tap/simple-bank counts, loading stress and start variation. Report build/solve/extraction/validation time, model size, allocations and correctly scoped memory, with plots. |

S1.1/S1.2 and preparation of the 118-bus baseline can proceed together. Public
case sources, versions, licenses and local transformations must be pinned when
acquired. Controller settings and bank capability data are explicit study overlays,
not implied measurements from a network file. A failed baseline or unsupported
feature must be reported rather than silently converted into an easier case.

The mathematical contract is now [docs/src/joint_formulation.md](docs/src/joint_formulation.md),
using explicit power-flow equations and equipment quantities. Include the unchanged dispatch objective and explain the
relationship between mathematical feasibility, exact-curve replay and solver KKT
conditions. Any discovered mismatch is a finding, not permission to change the
physical model silently.

Before changing equipment equations, assumptions, capability envelopes or
control laws, tell the user what would change, why, and which comparison would
be affected. This applies to proposed fixes as well as new model features.
Numerical experiments may vary starts, solver configuration and documented
smoothing/scaling while retaining exact-physical checks. Do not silently add a
nominal-design penalty or regularization, relax operating limits, or weaken
acceptance tolerances to turn a failure into a pass.

Milestone exit: publish a reproducible formulation/diagnostic report and a declared
benchmark matrix with per-case starts, numerical and physical tolerances, iteration
and runtime budgets, and hardware/software provenance. For the declared supported
matrix, require acceptable solver convergence AND independent AC, exact-droop,
operating-limit and policy validity. Compare multiple starts and both solvers;
classify objective/parameter disagreement rather than promise uniqueness. Record
coverage and out-of-scope/failed cases explicitly. Any excluded cases or unmet
convergence criteria keep that part of the gate open. Set practical performance
budgets from measured evidence before the final acceptance run; no universal
runtime, global optimality or large-network feasibility guarantee is implied.

The S1 exit review also owns test-suite rationalization. Classify retained tests
as fast core regression or extended numerical/research infrastructure, retire
tests only together with abandoned experimental capabilities, and preserve
cross-milestone CI coverage. The current assertion count is not itself a reason
to remove coverage; measured runtime, fragility, duplication and maintenance
value determine any consolidation.

Outputs include numerical tables, convergence histories, control-count and
network-size timing/resource plots, settings/bound diagnostics, and machine-readable
attempts. Continuous feasibility remains distinct from legal switch implementability.
S1 covers base-case optimization; contingency-count scaling follows M9.1/M9.2.

### S1 implementation checkpoint (2026-09-20)

| Slice | Current evidence | Remaining |
|---|---|---|
| S1.1 | Explicit mathematical contract and builder/validator map | Keep synchronized with approved changes |
| S1.2 | Both solver trace adapters, residual-scale labels, bound snapshots, phase timing and failure retention | Same-formulation Ipopt seeds and restart diagnostics now demonstrated; broader transfer remains open |
| S1.3 | Eight-family matrix at 12/96 buses; 15 independent count sweeps at fixed 96-bus size | Broaden placement and stress coverage after reliability |
| S1.4 | Exact Hessians, breakpoint derivative checks, error-bounded smoothing, public Jacobian scale/weak-column scans | Controller normalization and staged initialization benchmarked; residual normalization and reliable initialization remain open |
| S1.5 | Both solvers and three starts; staged release, smoothing/load continuation, small bound pushes and cross-solver polishing tested | Bounded one-reset policy and shared-budget staged workflows tested on both backends; public reliability remains incomplete |
| S1.6 | Pinned 118-/300-bus imports and fixed baselines; public controls at nominal/+5% load; phase/allocation/process-memory reporting and figures | Reliability and solution-quality gate fails; isolated warmed performance acceptance remains |

[Extension evidence](artifacts/s1_extension/report.md): synthetic 35/35 pass;
initial public pilot 13/30 pass. Public overlays contain 37/35 droops, 11/129
candidate tap controls and 12/32 simple banks on 118/300 buses. Actual adjustment
ranges are not supplied by source TAP flags; assumed ranges and bank data are
recorded explicitly. Aggregate shunts and generator capability remain unchanged.

Recovery successes do not erase failures. Smaller smoothing is not automatically
better numerically. Exact-droop validation is distinct from solver termination.
Weakly determined settings and objective/parameter spreads are reported without
adding penalties. S1 remains active before M9.


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

The minimal reproducer confirms that a saturated smooth droop equality becomes parallel to an active generator-Q bound. An opt-in equivalent formulation therefore omits only attached droop-generator Q bounds already implied by the bounded response; all physical equations, objectives, control limits, result fields and independent validation remain. The explicit formulation remains the default, and endpoint roundoff is measured rather than assumed away.

The frozen policy matrix does not support promotion: implied bounds validate **7/12 versus 8/12 Ipopt** and **3/12 versus 4/12 MadNLP** cases. Gains on nominal IEEE 118 starts coexist with losses under stress and at 300 buses. The [report](docs/src/s1_implied_q.md) includes the rank reproducer, paired objectives and all failed attempts. **1529/1529 tests pass.** S1 remains open; reduced-space or alternative smooth-saturation formulations require derivation and small-case equivalence tests before another public benchmark. M9 remains gated.

### S1 reduced-space droop-Q checkpoint (2026-09-21)

The opt-in reduced formulation removes each attached controlled-generator Q
variable and droop equality, substitutes the same smoothed response into reactive
balance and objective terms, and reconstructs Q for the unchanged result and
validation layers. It removes 37 variables on IEEE 118 and 35 on IEEE 300.

The frozen comparison is solver dependent: **Ipopt falls from 8/12 to 4/12**
accepted cases, while **MadNLP rises from 4/12 to 8/12** but loses one prior
stressed IEEE 300 success. The [full ledger](docs/src/s1_reduced_q.md) separates
native termination from physical failures and retains all attempts. Explicit Q
remains the default, reduced Q remains diagnostic, and **1551/1551 regression
tests pass**. M9 stays gated while S1
tests another equivalent treatment against the same no-loss criterion.
