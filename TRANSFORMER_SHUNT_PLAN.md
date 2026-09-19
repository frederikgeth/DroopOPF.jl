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

Preserve discrete equipment data, but optimize tap ratio tau and shunt susceptance
B continuously within declared physical envelopes by default. Fixed modes remain
available independently for every device and droop setting. Phase shift remains
fixed in this scope. Document whether conductance stays fixed or follows a bank
mapping; arbitrary independent G/B freedom must not be introduced by relaxation.
For heterogeneous bank combinations, define the admissible relaxed envelope
explicitly rather than assume one continuously adjustable physical bank exists.

| Slice | Small change | Validation and required visual |
|---|---|---|
| M7.1 | Continuous tap optimization; shunts/droop fixed | Fixed-bound equivalence; bound checks; objective/feasibility versus ratio sweep and selected solution |
| M7.2 | Continuous shunt optimization; taps/droop fixed | V-squared injection and bounds; objective/feasibility versus susceptance sweep |
| M7.3 | Joint equipment and existing M3 droop design | Independent fixed/free flags; matched configuration grid with selected settings, validity and objective components |

Reuse the existing NLP path and baseline objective first. Add only needed
quantities with independently evaluated raw values and explicit normalization.
Record relaxed settings separately from legal physical positions. Continuous
movement measures are not switching-event counts. A locally solved relaxation
is not a certified lower bound on the discrete optimum or proof of scalability.

## M8: continuous steady-state transformer AVR

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

## M9: equipment and AVR response in SCOPF

Extend M2/M3 builders and validators. M5/M6 already provide fixed-equipment SCOPF;
this milestone adds decision sharing and response-policy coupling.

| Slice | Small change | Validation and required visual |
|---|---|---|
| M9.1 | Shared preventive continuous tap/shunt settings | Scenario-by-device setting table; no-contingency equivalence; independent shared-setting perturbation check |
| M9.2 | Explicit bounded corrective equipment settings | Base-to-contingency ratio/B movement versus permitted bounds; preventive/corrective margin comparison |
| M9.3 | Before-tap-response and AVR-settled contingency assessments | Paired voltage/thermal/Q margins, frozen versus settled taps, target errors and saturation status |

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
