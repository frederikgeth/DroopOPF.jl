# Validation reports

These are curated report summaries, organized by milestone or workstream. Numerical tables and figures live on separate pages; full private historical reports remain in the [research archives](research.md). No historical campaign is rerun by rebuilding these pages.

## [M1 — AC OPF with fixed volt-var curves](@id evidence-m1-report)

**Purpose.** Solve base AC dispatch with supplied reactive-response curves.

**Status.** Implemented; declared small-case evidence.

**Scope and assumptions.** Balanced steady-state AC cases with attached generator volt-var controls and fixed equipment.

**Validation.** Compare smooth and exact response encodings, reconstruct the exact curve and independently replay bus balances and operating limits.

**Boundary.** No dynamic, global-optimality or arbitrary-network convergence claim.

[Validation tables](@ref evidence-m1-tables) · Figures: retained privately / none bundled · [Source register](validation_evidence.md)

Model and workflow documentation: [getting started](getting_started.md), [validation](validation.md), [solvers](solvers.md).

## [M2 — Security-constrained AC OPF](@id evidence-m2-report)

**Purpose.** Couple base and outage equilibria with an explicit active-response policy.

**Status.** Implemented; declared small-case evidence.

**Scope and assumptions.** Base dispatch plus declared branch/generator outages; preventive and corrective steady-state policies.

**Validation.** Check empty-catalogue equivalence, unavailable devices, response coupling, security-induced dispatch changes and independent scenario replay.

**Boundary.** Connected-catalogue acceptance is distinct from general island balancing or transient security.

[Validation tables](@ref evidence-m2-tables) · Figures: retained privately / none bundled · [Source register](validation_evidence.md)

Model and workflow documentation: [scopf](scopf.md), [validation](validation.md).

## [M3 — Bounded droop design](@id evidence-m3-report)

**Purpose.** Optimize declared droop parameters shared across training scenarios.

**Status.** Implemented; declared bounded-family evidence.

**Scope and assumptions.** Saturated volt-var slope, voltage reference and independently bounded lower/upper deadband widths.

**Validation.** Compare bounded optimization with a small sweep; fixed bounds reproduce SCOPF. Replay reconstructed exact curves and evaluate held-out scenarios.

**Boundary.** Arbitrary free-knot PWL topology, uniqueness and global optimality are outside this scope.

[Validation tables](@ref evidence-m3-tables) · Figures: retained privately / none bundled · [Source register](validation_evidence.md)

Model and workflow documentation: [droop optimization](droop_optimization.md), [droop security](droop_security.md).

## [M4 — Robustness and benchmark gate](@id evidence-m4-report)

**Purpose.** Measure repeated-start behavior, diagnostics and small public-case reproducibility.

**Status.** Implemented; bounded robustness evidence.

**Scope and assumptions.** Named state/design starts, breakpoint distances, operating margins and pinned small public benchmark cases.

**Validation.** Retain all attempts and compare objective/parameter spread; separate solver, replay and policy failures; record actual model and resource measurements.

**Boundary.** The original small-case gate does not establish large-system scaling or a universal solver ranking.

[Validation tables](@ref evidence-m4-tables) · Figures: retained privately / none bundled · [Source register](validation_evidence.md)

Model and workflow documentation: [robustness](robustness.md), [solvers](solvers.md).

## [M5 — Transformer reference physics](@id evidence-m5-report)

**Purpose.** Represent fixed transformer ratios, phase shifts, availability and terminal ratings.

**Status.** Implemented; declared equipment-physics evidence.

**Scope and assumptions.** Fixed-ratio and fixed-phase AC transformer models, import/schema identity and OPF/SCOPF integration.

**Validation.** Compare the optimizer admittance primitive with independent internal-current reconstruction, analytical sweeps and outage/serialization checks.

**Boundary.** Tap optimization and automatic transformer AVR belong to later milestones.

**Slices.** M5.1: Data, import and schema migration; M5.2: Fixed-ratio physics; M5.3: Phase shift, availability and terminal ratings; M5.4: OPF/SCOPF and droop-design integration.

[Validation tables](@ref evidence-m5-tables) · Figures: retained privately / none bundled · [Source register](validation_evidence.md)

Model and workflow documentation: [data model](data_model.md), [validation](validation.md).

## [M6 — Shunt reference physics](@id evidence-m6-report)

**Purpose.** Represent fixed shunts and supplied legal bank states.

**Status.** Implemented; declared equipment-physics evidence.

**Scope and assumptions.** Bus conductance/susceptance, MATPOWER GS/BS and supplied capacitor/reactor bank counts.

**Validation.** Independently check signs, V-squared power accounting, legal fixed states, availability and study round trips.

**Boundary.** Fixed heterogeneous banks are supported; general heterogeneous-bank optimization is separate.

**Slices.** M6.1: Fixed admittance and import; M6.2: Supplied bank states; M6.3: OPF/SCOPF and droop-design integration.

[Validation tables](@ref evidence-m6-tables) · Figures: retained privately / none bundled · [Source register](validation_evidence.md)

Model and workflow documentation: [data model](data_model.md), [equipment optimization](equipment_optimization.md).

## [M7 — Continuous equipment and joint droop optimization](@id evidence-m7-report)

**Purpose.** Choose selected continuous taps, simple-bank susceptance and bounded droop parameters.

**Status.** Implemented; synthetic base-case comparisons.

**Scope and assumptions.** Synthetic three-bus base operation; tap, shunt and droop freedom compared under the same dispatch-deviation objective.

**Validation.** Fixed-bound equivalence, independent current replay, tap/bank sweeps and an eight-configuration two-start joint-design comparison.

**Boundary.** Continuous local solutions; no discrete implementability, security or large-system scaling claim. The objective is dispatch deviation, not loss.

**Slices.** M7.1: Continuous tap-ratio optimization; M7.2: Continuous simple-bank susceptance; M7.3: Joint tap/shunt/droop design.

[Validation tables](@ref evidence-m7-tables) · [Figures](@ref evidence-m7-figures) · [Source register](validation_evidence.md)

Model and workflow documentation: [equipment optimization](equipment_optimization.md).

## [M8 — Steady-state transformer AVR](@id evidence-m8-report)

**Purpose.** Model an automatic transformer voltage-regulation equilibrium with limits.

**Status.** Implemented; bounded static-control tests.

**Scope and assumptions.** Transformer AVR targets/deadbands and limited ratio equilibrium, distinct from freely optimized ratios.

**Validation.** Validate the selected regulation mode, saturation behavior, unmet targets and physical reconstruction; preserve explicit control assignments.

**Boundary.** Transformer AVR is distinct from the generator AVR added to later mixed-control studies; dynamic/discrete control qualification is separate.

[Validation tables](@ref evidence-m8-tables) · Figures: retained privately / none bundled · [Source register](validation_evidence.md)

Model and workflow documentation: [data model](data_model.md), [scopf](scopf.md).

## [M9 — Equipment-aware SCOPF](@id evidence-m9-report)

**Purpose.** Coordinate preventive equipment, automatic response and bounded corrective recourse.

**Status.** Implemented; declared synthetic policy evidence.

**Scope and assumptions.** Shared preventive controls, scenario-specific corrective continuous controls and explicit timing/movement assumptions.

**Validation.** Check policy sharing, immediate/settled stages and bounded movement against independent scenario replay; zero movement reproduces the preventive policy.

**Boundary.** Any campaign must state actual devices, information sharing, movement budgets and assumed timing; no unlimited corrective adjustment is implied.

**Slices.** M9.1: Equipment policy layer and preventive sharing; M9.2: Corrective recourse and movement budgets; M9.3: Paired immediate/settled response stages.

[Validation tables](@ref evidence-m9-tables) · Figures: retained privately / none bundled · [Source register](validation_evidence.md)

Model and workflow documentation: [scopf](scopf.md), [equipment optimization](equipment_optimization.md).

## [M10 — Contingency assessment and comparative evidence](@id evidence-m10-report)

**Purpose.** Assess catalogues, compare control modes and close bounded physics/reproducibility gates.

**Status.** Declared scope complete; general qualification remains separate.

**Scope and assumptions.** Assessment/ranking/screening workflows plus sourced equipment physics, matched synthetic comparisons and reproducibility/performance closeout.

**Validation.** Retain negative controls and failed attempts; distinguish equation-reference checks, matched comparisons and software regression from network security certification.

**Boundary.** Equation-reference transcription is not an external-solver benchmark; transformer AVR and broader public comparisons are outside the matched synthetic scope.

**Slices.** M10.1: Sourced equipment-physics references; M10.2: Matched design/control comparisons; M10.3: Reproducibility and performance closeout.

[Validation tables](@ref evidence-m10-tables) · Figures: retained privately / none bundled · [Source register](validation_evidence.md)

Model and workflow documentation: [scopf](scopf.md), [droop security](droop_security.md), [research](research.md).

## [S1 — Convergence and scale study](@id evidence-s1-report)

**Purpose.** Test base-operation droop/equipment optimization across control families and demand samples.

**Status.** Historical declared scope closed; new deadband sensitivity separate.

**Scope and assumptions.** ARPA-E 14/500-bus variants, Pmin=0, symmetric Q, zero deadband, continuous equipment, five demands 90/95/100/105/110% and OPF-derived starts.

**Validation.** Compare independent design-at-demand with one nominal design frozen across demands; keep primary scores, retries, native status and physical replay separate.

**Boundary.** No original-Q-limit frozen-equipment, unseen-demand, dynamic or security closure follows. Known-witness performance is not an unseen-start success rate.

**Slices.** S1.1: Mathematical contract; S1.2: Numerical and physical diagnostics; S1.3: Control-family isolation; S1.4: Conditioning; S1.5: Initialization and solver comparison; S1.6: Larger-network scaling.

[Validation tables](@ref evidence-s1-tables) · Figures: retained privately / none bundled · [Source register](validation_evidence.md)

Model and workflow documentation: [release scope](release_scope.md), [solvers](solvers.md), [research](research.md).

## [S2 — Shared security-design study](@id evidence-s2-report)

**Purpose.** Design one controller across training demands/outages and test it on held-out demands.

**Status.** 14-bus declared scope closed; original 500-bus campaign paused.

**Scope and assumptions.** Historical Pmax-proportional response and explicit S2 equipment/operating contracts. Zero-deadband 14-bus shared design has five training and four held-out demands.

**Validation.** Require native design convergence, exact AC/controller replay, sharing/response policy checks and explicit catalogue coverage; retain separate emergency/relief lanes.

**Boundary.** No general islanding, continuous-demand, global-optimality or full 500-bus S2 closure. Later P2 success does not rewrite S2 history.

[Validation tables](@ref evidence-s2-tables) · Figures: retained privately / none bundled · [Source register](validation_evidence.md)

Model and workflow documentation: [release scope](release_scope.md), [droop security](droop_security.md), [research](research.md).

## [P0 — Proof-of-concept foundation](@id evidence-p0-report)

**Purpose.** Establish the smallest executable model-to-independent-validation workflow.

**Status.** Implemented; declared proof-of-concept scope.

**Scope and assumptions.** Package/CI, typed domain, MATPOWER import, base AC OPF, exact/smooth curves, one contingency and independent reports.

**Validation.** Exercise a complete small-case workflow and reject corrupted states rather than using solver status as the physical acceptance test.

**Boundary.** Foundation scope overlaps M1/M2 evidence; these are not independent repetitions to add to campaign totals.

[Validation tables](@ref evidence-p0-tables) · Figures: retained privately / none bundled · [Source register](validation_evidence.md)

Model and workflow documentation: [getting started](getting_started.md), [validation](validation.md).

## [P1 — Useful research-prototype workflow](@id evidence-p1-report)

**Purpose.** Make studies repeatable, diagnosable and serializable.

**Status.** Implemented; declared small-case workflow evidence.

**Scope and assumptions.** Multiple contingencies, preventive/corrective modes, smoothing continuation, exact replay, serialization, named starts, public regression and measurements.

**Validation.** Preserve inputs, every solver outcome, independent validation, objective/parameter spread and environment/model-resource measurements.

**Boundary.** This is a workflow priority, not a distinct network benchmark or proof of universal numerical robustness.

[Validation tables](@ref evidence-p1-tables) · Figures: retained privately / none bundled · [Source register](validation_evidence.md)

Model and workflow documentation: [validation](validation.md), [robustness](robustness.md), [solvers](solvers.md).

## [P2 — Scaling and qualification](@id evidence-p2-report)

**Purpose.** Improve larger security studies while retaining complete final AC qualification.

**Status.** Broader P2 open; latest declared connected-catalogue design qualified.

**Scope and assumptions.** Sparse models, ranking/filter diagnostics, bounded scenario addition, initialization, backends and fixed-candidate exhaustive assessment. Current mixed 500-bus lane uses limit-aware response. The selected joint model uses Ipopt.

**Validation.** Use bounded joint masters and full candidate scans; distinguish necessary exclusions from numerical failures. Reoptimize common controls for recovery, freeze the candidate, then replay all accepted results.

**Boundary.** All-connected-outage acceptance is not general islanding/transient security or overall P2 closure. Exact-S2 proportional filters cannot be applied to production limit-aware response. Equivalent full-catalogue CCOpt qualification is not established by this Ipopt evidence.

**Slices.** P2-01: Ranking diagnostics; P2-02: Bounded screening qualification; default off; P2-03: Sparse/resumable throughput; P2-04: Scenario addition and exhaustive final audit; P2-05: Numerical initialization policies; P2-06: Bounded threaded assessment; P2-07: MadNLP compatibility; P2-08: Conditional ExaModels work; not implemented; P2-09: Exact-S2 benchmark and bounded qualification; P2-10: Conditional decomposition; not implemented.

[Validation tables](@ref evidence-p2-tables) · [Figures](@ref evidence-p2-figures) · [Source register](validation_evidence.md)

Model and workflow documentation: [release scope](release_scope.md), [mixed avr droop](mixed_avr_droop.md), [droop security](droop_security.md).

## [P3 — Extended model scope](@id evidence-p3-report)

**Purpose.** Add multi-period, data-adapter and mixed-control capabilities as qualified slices.

**Status.** Selected slices implemented; broader extensions open.

**Scope and assumptions.** Deterministic period dispatch/shared curves and ramps, RAW import/saved-state checks, mixed AVR/droop and declared capability circles.

**Validation.** Qualify each extension under its own input, information, capability and replay contract; retain native RAW export gaps and unverified equipment assumptions.

**Boundary.** The initial base-operation profiles do not establish N−1 or transient security. Apparent ratings and ramp rates are explicit study assumptions.

[Validation tables](@ref evidence-p3-tables) · Figures: retained privately / none bundled · [Source register](validation_evidence.md)

Model and workflow documentation: [multi period](multi_period.md), [psse](psse.md), [mixed avr droop](mixed_avr_droop.md).
