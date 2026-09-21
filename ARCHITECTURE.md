# DroopOPF.jl Architecture

Status: proposed architecture for the proof-of-concept and subsequent scale-up.

Last updated: 2026-09-03

## 1. Purpose

`DroopOPF.jl` is a Julia library for steady-state and quasi-steady security-constrained AC optimal power flow with explicit generator and converter control responses, initially focused on synchronous-generator volt-var droop.

The project has two simultaneous goals:

1. provide a small, trustworthy reference implementation;
2. provide a path to large-scale contingency screening and decomposition.

The reference implementation and the scalable implementation must share the same physical semantics, data model, result schema, and validation layer.

## 2. Scope and non-goals

### Initial scope

- balanced single-phase AC networks;
- single-period steady-state and quasi-steady-state studies;
- MATPOWER-compatible input;
- generator reactive-power/voltage droop;
- preventive and corrective contingency response;
- line and generator outages;
- exact piecewise-linear control curves;
- smooth softplus control encodings for nonlinear solvers;
- independent equilibrium validation;
- full-contingency enumeration before screening and decomposition.

### Explicit non-goals for the proof of concept

- transient stability or frequency-nadir guarantees;
- automatic generator-model identification;
- unit commitment;
- multi-period storage scheduling;
- unbalanced distribution networks;
- topology optimization;
- GPU and MPI support;
- a new nonlinear programming solver;
- a universal power-system data model.

These may become later extensions, but they must not complicate the first vertical slice.

## 3. Core design principles

### 3.1 Physical semantics are solver-independent

The public data model describes generators, networks, controls, scenarios, and physical curves. It must not contain `JuMP.Model`, `JuMP.VariableRef`, solver callbacks, or solver-specific indexing.

### 3.2 Exact physical data, approximate numerical encoding

The exact piecewise-linear droop curve is the source of truth. Softplus, Bezier, complementarity, and mixed-integer representations are numerical encodings selected by a formulation or backend.

### 3.3 Immutable input, mutable solve state

User-owned case data is never modified during a solve. Compilation produces an immutable or structurally stable `CompiledCase`; mutable iterates, scratch arrays, caches, and solver state live in a separate `SolveWorkspace`.

### 3.4 Compile once, solve many

Topology, integer indices, sparse structures, curve encodings, and scenario overlays are compiled once and reused across solver iterations and contingencies.

### 3.5 Validation is a first-class product feature

The library must independently recompute AC residuals, branch flows, control responses, limits, and exact-curve errors. A solver success status is never sufficient evidence of a valid equilibrium.

### 3.6 Explicit assumptions

Every result records the formulation, control semantics, smoothing parameters, tolerances, solver, initial-point strategy, and scenario set used to produce it.

### 3.7 Simple first, scalable second

The first backend should favor transparency and correctness. Performance work should be guided by measured profiles and should preserve the same public semantics.

## 4. Conceptual architecture

```text
Case data
    |
    v
Input adapters and normalization
    |
    v
Data/model validation
    |
    v
Compiled study
    |
    +--> Physics evaluator
    |
    +--> Formulation builder --> Solver backend
    |
    +--> Contingency evaluator --> Screening/cut policy
    |
    v
Standardized result
    |
    v
Independent equilibrium validator
    |
    v
Validation report and provenance
```

The central dependency direction is:

```text
domain -> compile -> physics/formulation -> backend/algorithm -> results -> validation/reporting
```

The domain layer must not depend on any layer to its right.

## 5. Proposed source layout

```text
src/
├── DroopOPF.jl
├── domain/
│   ├── case.jl
│   ├── network.jl
│   ├── buses.jl
│   ├── branches.jl
│   ├── generators.jl
│   ├── loads.jl
│   ├── controls.jl
│   ├── curves.jl
│   ├── contingencies.jl
│   └── studies.jl
├── io/
│   ├── native.jl
│   ├── matpower.jl
│   ├── psse.jl
│   └── powersystems.jl
├── validation/
│   ├── findings.jl
│   ├── data_validation.jl
│   ├── model_validation.jl
│   ├── equilibrium_validation.jl
│   └── reports.jl
├── compile/
│   ├── indices.jl
│   ├── topology.jl
│   ├── controls.jl
│   ├── scenarios.jl
│   └── sparsity.jl
├── physics/
│   ├── power_balance.jl
│   ├── branch_flows.jl
│   ├── control_response.jl
│   ├── residuals.jl
│   └── derivatives.jl
├── formulations/
│   ├── acopf.jl
│   ├── scopf.jl
│   ├── control_encoding.jl
│   └── model_builder.jl
├── backends/
│   ├── interface.jl
│   ├── jump.jl
│   ├── direct_nlp.jl
│   └── examodels.jl
├── algorithms/
│   ├── interface.jl
│   ├── full_enumeration.jl
│   ├── screening.jl
│   ├── constraint_generation.jl
│   └── decomposition.jl
├── results/
│   ├── states.jl
│   ├── results.jl
│   ├── traces.jl
│   └── provenance.jl
└── reporting/
    ├── text.jl
    ├── markdown.jl
    └── serialization.jl

ext/
├── DroopOPFJuMPExt.jl
├── DroopOPFPowerModelsExt.jl
├── DroopOPFPowerSystemsExt.jl
└── DroopOPFExaModelsExt.jl
```

This is a logical layout. The project should remain one package until the public interfaces and dependency boundaries have stabilized.

## 6. Domain model

### 6.1 Case and study

Separate reusable network data from a particular optimization study.

```julia
struct Case
    id
    base_power
    base_frequency
    network
    generators
    loads
    controls
    metadata
end

struct Study
    case
    operating_condition
    contingencies
    formulation
    algorithm
    options
end
```

`Case` is the physical/data object. `Study` specifies what is being solved.

### 6.2 Generator

The generator stores physical capability, dispatch, cost, availability, and references to controls. It does not store a solver expression.

```julia
struct Generator{T}
    id
    bus_id
    available::Bool
    p_limits::Tuple{T,T}
    q_limits::Tuple{T,T}
    apparent_power_limit::Union{Nothing,T}
    initial_p::T
    initial_q::T
    ramp_up::Union{Nothing,T}
    ramp_down::Union{Nothing,T}
    base_power::T
    control_ids::Vector
    metadata
end
```

The optimized base dispatch should be represented separately from the input initial point when the study is solved.

### 6.3 Response curve

Store the physical curve in canonical knot form.

```julia
struct PiecewiseLinearCurve{T}
    breakpoints::Vector{T}
    values::Vector{T}
    extrapolation::Symbol  # :clamp, :linear, :error
end
```

The curve validator enforces ordering, finiteness, expected monotonicity, and endpoint behavior.

Do not store ReLU triples as primary user data. They are derived during compilation.

### 6.4 Droop control

The control attachment describes how a curve relates to generators and network signals.

```julia
struct DroopControl{T}
    id
    generator_ids::Vector
    input_quantity::Symbol       # :frequency, :voltage_magnitude
    input_location::Symbol       # :system, :bus, :terminal, :island
    input_reference::T
    input_units::Symbol          # :Hz, :pu
    output_quantity::Symbol      # :active_power, :reactive_power
    output_mode::Symbol          # :incremental, :absolute
    output_units::Symbol         # :MW, :MVAr, :pu
    curve::PiecewiseLinearCurve{T}
    response_limits::Union{Nothing,Tuple{T,T}}
    activation_stage::Symbol     # :primary, :secondary, ...
    enabled::Bool
    metadata
end
```

For generator volt-var response, the canonical relationship is:

```text
V[g,c] = voltage at the control location for generator g in scenario c
Q[g,c] = response(control[g], V[g,c]; P[g,c])
```

The response is evaluated against the active-power-dependent reactive capability of the generator. Frequency droop can use the same abstraction later with `input_quantity=:frequency` and `output_quantity=:active_power`.

### 6.5 Measurement location

The input signal must explicitly identify its scope:

- `:system`: one coherent system-wide signal, such as frequency;
- `:bus`: a local signal attached to a bus;
- `:terminal`: a device-terminal signal;
- `:branch_terminal`: a branch endpoint signal;
- `:remote_bus`: a voltage signal at an explicitly remote bus;
- `:island`: a signal indexed by the island created by a contingency;
- `:parameter`: an externally supplied scenario value.

If the formulation does not represent the requested signal, validation must fail early rather than silently substituting another signal.

### 6.6 Contingency and scenario overlays

Contingencies are deltas over a base case.

```julia
struct Contingency
    id
    outages
    control_overrides
    metadata
end

struct ScenarioOverlay
    unavailable_generators::Vector{Int}
    unavailable_branches::Vector{Int}
    active_controls::Vector{Int}
    parameter_overrides
    island_map
end
```

An outaged generator must have zero output and an inactive droop control. Its control equation must not remain active with a zero multiplier.

## 7. Compilation model

Compilation transforms user-facing data into numerically efficient structures.

```julia
struct CompiledCase{T}
    network_index
    generator_index
    load_index
    topology
    admittance_data
    sparse_patterns
    generators
    controls
    base_parameters
end

struct CompiledStudy{T}
    case::CompiledCase{T}
    scenarios
    formulation
    algorithm
    options
end
```

Compilation performs:

1. ID resolution;
2. integer indexing;
3. unit and per-unit normalization;
4. topology construction;
5. branch and bus incidence construction;
6. control-to-generator and control-to-signal maps;
7. curve encoding preparation;
8. scenario overlay construction;
9. Jacobian/Hessian sparsity analysis;
10. pre-solve validation.

The compiled case should be reusable across multiple operating points with the same topology.

## 8. Physics layer

The physics layer must be usable without JuMP.

Required pure or allocation-controlled interfaces include:

```julia
power_balance(case, state, scenario)
branch_flows(case, state, scenario)
control_response(case, state, scenario)
equilibrium_residual(case, state, scenario)
operating_margins(case, state, scenario)
```

For a scenario (c), the equilibrium residual should include at least:

```text
active-power balance
reactive-power balance
droop/control equations
regulated-voltage or reference equations
stage-coupling equations
```

The physical evaluator is also the foundation of the independent validator.

## 9. Formulations and encodings

The formulation specifies variables and equations; the backend specifies how they are represented and solved.

```julia
struct ACFormulation
    voltage_coordinates::Symbol  # :polar, :rectangular, :iv
    branch_model::Symbol
    control_encoding
end

struct ControlEncoding
    method::Symbol                # :exact_pwl, :softplus, :complementarity
    epsilon
    continuation
end
```

The proof of concept should implement:

- polar or rectangular AC power flow;
- exact PWL control replay;
- softplus control encoding;
- explicit base and contingency states.

Epsilon is a numerical parameter. It is not a physical property of the generator.

## 10. Backend interface

Backends should implement a small interface:

```julia
abstract type AbstractBackend end

build_model(backend, compiled_study)
set_initial_point!(backend, model, state)
solve_model!(backend, model)
extract_state(backend, model)
solver_metadata(backend, model)
```

The first backend should be JuMP plus Ipopt or MadNLP. Later backends may use direct NLP callbacks, ExaModels, or specialized native solvers.

Public domain and result types must not depend on JuMP.

## 11. Algorithm interface

Algorithms orchestrate master solves, contingency evaluation, and cut generation.

```julia
abstract type AbstractSCOPFAlgorithm end

struct FullEnumeration <: AbstractSCOPFAlgorithm end

struct ConstraintGeneration <: AbstractSCOPFAlgorithm
    evaluator
    ranking_policy
    max_iterations::Int
end

solve(study::Study)
solve(study::Study, algorithm::AbstractSCOPFAlgorithm)
```

The algorithm layer should use replaceable components:

- `ContingencyRanker`;
- `ContingencyEvaluator`;
- `ViolationDetector`;
- `CutGenerator`;
- `MasterProblem`;
- `ScenarioSolver`;
- `TerminationPolicy`.

The first implementation is full enumeration. Constraint generation and parallel screening follow after correctness is established.

## 12. Results

Results must be stable across backends.

```julia
struct ScenarioState{T}
    scenario_id
    voltages
    generator_p
    generator_q
    frequency_deviation
    control_outputs
    branch_flows
end

struct SCOPFResult{T}
    base_state::ScenarioState{T}
    scenario_states::Vector{ScenarioState{T}}
    objective
    solver_status
    algorithm_trace
    provenance
end
```

The result should preserve component IDs or a reversible mapping to IDs. It should not require users to inspect solver variables.

## 13. Validation and reporting

Validation is layered:

### Data validation

- schema and type checks;
- referential integrity;
- units and base consistency;
- curve ordering and plausibility;
- control attachment checks;
- contingency consistency.

### Model validation

- every requested signal exists;
- every scenario has a valid topology;
- every regulated location has a defined voltage policy;
- every generator has valid operating limits;
- no unconstrained balancing source exists accidentally.

### Equilibrium validation

- independent active/reactive residuals;
- branch flows and limits;
- generator limits;
- droop equality residuals;
- exact-versus-smoothed curve error;
- deadband leakage;
- saturation consistency;
- voltage-control response and capability consistency;
- scenario and island status.

Use structured findings:

```julia
struct Finding
    code
    severity
    scenario_id
    component_id
    quantity
    value
    limit
    units
    message
end
```

Suggested codes:

```text
E.DATA.UNKNOWN_REFERENCE
E.DATA.INVALID_CURVE
E.MODEL.MISSING_SIGNAL
E.PF.ACTIVE_POWER_RESIDUAL
E.PF.REACTIVE_POWER_RESIDUAL
E.CTRL.DROOP_RESIDUAL
E.CTRL.EXACT_CURVE_VIOLATION
E.SCENARIO.ISLANDING_UNSUPPORTED
W.CTRL.SMOOTHING_GAP
W.CTRL.NEAR_BREAKPOINT
W.NUM.ILL_CONDITIONED
I.CTRL.SATURATED
I.SCENARIO.BINDING_CONTINGENCY
```

Use `ERROR`, `WARNING`, and `INFO` rather than a single Boolean. Reports should be serializable to JSON and readable as Markdown.

## 14. Performance and scale-up

The performance roadmap is:

1. avoid `Dict{String,Any}` in numerical loops;
2. use integer indices and concrete arrays;
3. precompute sparse patterns;
4. reuse base-case topology and symbolic factorizations;
5. evaluate independent contingencies in parallel;
6. add constraint generation;
7. add ExaModels/MadNLP backend;
8. investigate GPU and distributed execution.

Do not expand every contingency into one monolithic model by default. Keep full enumeration as a correctness oracle.

## 15. Dependency strategy

The core package should remain lightweight where practical.

Likely optional integrations:

- JuMP/MathOptInterface for reference modeling;
- Ipopt for the first nonlinear solver;
- MadNLP for Julia-native sparse NLP;
- PowerModels for compatibility and reference cases;
- PowerSystems for richer typed system data and time series;
- ExaModels for later high-throughput derivative evaluation.

Use Julia package extensions or separate adapter modules so users do not need every ecosystem package to load the core domain model.

## 16. Testing architecture

### Unit tests

- curve values, derivatives, and limits;
- units and scaling;
- ID resolution;
- scenario overlay application;
- topology and island detection;
- residual calculations.

### Integration tests

- base AC OPF;
- scalar droop sharing;
- one generator outage;
- one line outage;
- exact curve replay;
- epsilon continuation;
- intentional infeasibility.

### Differential tests

Compare, where possible:

- independent physics evaluator versus model expressions;
- JuMP backend versus direct evaluator;
- exact curve versus smooth curve;
- DroopOPF results versus PowerModels/MATPOWER reference results.

### Regression tests

Every bug fix should add a minimal case or a focused property test.

## 17. Architectural references

The design is informed by:

- [PowerModels.jl](https://github.com/lanl-ansi/PowerModels.jl): separation of problem specifications and network formulations;
- [PowerModelsSecurityConstrained.jl](https://lanl-ansi.github.io/PowerModelsSecurityConstrained.jl/dev/components/): contingency filters, cut generation, and scenario-stage solvers;
- [BMOPFTools smooth droop encoding](https://github.com/frederikgeth/BMOPFTools.jl/blob/main/docs/src/relu_softplus_encoding.md): exact PWL curves with smooth solver encodings;
- [BMOPFTools validation workflow](https://github.com/frederikgeth/BMOPFTools.jl/blob/main/docs/src/tutorial_end_to_end.md): structured findings, provenance, and re-validation;
- [ExaGO SCOPFLOW](https://github.com/ORNL/ExaGO/blob/develop/docs/web/scopflow.md): two-stage contingency decomposition;
- [ExaPF.jl](https://exanauts.github.io/ExaPF.jl/stable/): differentiable and backend-oriented power-flow kernels;
- [MadNLP.jl](https://madsuite.org/MadNLP.jl/stable/): Julia-native sparse NLP and linear-solver interfaces.

## 17a. Transformer/shunt planning boundaries

[ROADMAP.md](ROADMAP.md) owns implementation status for M5-M10; [TRANSFORMER_SHUNT_PLAN.md](TRANSFORMER_SHUNT_PLAN.md)
defines the validation slices and required reporting/visualization bundles.
M5 fixed-transformer physics and all M6 fixed-shunt/bank slices are implemented;
M7 base-case tap, simple-bank and joint droop optimization is implemented; M8-M10 remain planned. The confirmed
[pre-M5.1 architecture review](TRANSFORMER_SHUNT_PLAN.md#pre-m51-architecture-review--confirmed)
records the starting decisions approved by the user on 2026-09-18.

- Data retains physical parameters, legal tap/bank positions, availability,
  reference settings and AVR measurements/targets. Do not infer bank steps from
  aggregate MATPOWER shunt admittance.
- The optimization problem selects fixed, continuous-optimized or AVR-controlled
  transformer modes, fixed/free shunts, sharing and corrective permissions.
- Formulations implement the same AC physics with continuous equipment relaxation
  as the main path. Optional discrete/enumerated/MINLP paths have explicit support
  checks. AVR needs interior target and correctly directed saturation regimes;
  deadband equilibrium selection is declared, not silently optimized as autonomy.
- Independent validation recomputes electrical results, continuous bounds or legal
  positions as appropriate, availability, exact AVR regimes and scenario coupling.
  Report relaxation/recovery status separately from physical implementability.

Preserve M1-M4 constructors and schemas through defaults or versioned migration.
Reuse existing scenario and droop-design machinery. Distinguish before-tap-response
and AVR-settled security stages with explicit dispatch and equipment permissions.
These steady states do not simulate intervening dynamics. Initial-position-driven
settling, timers, dwell, hunting and operation counts require a later sequential
runner. Continuous displacement is not a count. Multiple simultaneous AVRs require
an explicit coordination contract before support is claimed.

Every slice includes machine-readable results, a readable report and explanatory
visuals with independent numerical acceptance. Reporting is part of implementation,
not an optional final-stage task. No broad public-class rewrite is required merely
to preserve these conceptual boundaries.

M6.1 represents fixed bus admittance as `FixedShunt` records in `ACNetwork.shunts`,
separate from constant-power loads and branch charging. Ybus construction and
independent current-based validation each account for the shunt once. Study schema
v4 preserves fixed shunts and explicit banks; v1/v2 migrate to no shunts, and
v1-v3 migrate to no banks. Bank positions,
optimization policies and automatic shunt controls are not inferred from GS/BS.

### Decision gates after M5.1

- Before M7, settle supplied/initial/solved setting ownership with stable equipment
  IDs, and separate physical metric evaluation from objective/constraint selection.
- Before M8, specify controller-conflict handling and deadband equilibrium selection.
- Before M9, declare shared/recourse permissions by equipment and response stage;
  keep contingency identity separate from period identity.
- Before operating-point replay, distinguish exact fixed observations from
  tolerance-based reconciliation and report every permitted adjustment.

Across these gates, report solver termination, AC feasibility, control-policy
compliance and discrete implementability separately. These gates do not expand
M5.1 or prescribe a generic framework ahead of its use cases.

## 18. Architecture decision rules

When choosing between implementations:

1. preserve physical meaning over solver convenience;
2. prefer a pure evaluator over duplicated solver expressions;
3. prefer an adapter over a hard dependency;
4. prefer a small vertical slice over speculative generality;
5. prefer explicit diagnostics over silent fallback behavior;
6. benchmark before introducing a new backend;
7. require tests for every new formulation or control mode.

### M6 bank state ownership

`ShuntBank` stores immutable step admittances, explicit legal count tuples,
current and nominal states, and availability. `with_bank_state` returns a new
validated device. `ACNetwork.banks` owns the supplied equipment state; M6 builders
hold it fixed in every scenario. Ybus aggregates its admittance while independent
validation sums individual step currents. Fixed shunts and banks share a unique
equipment ID namespace and must not duplicate the same physical admittance.
No bank switching trajectory, automatic control or bank optimization is inferred.
This preserves the boundary between physical data, optimization policy and validation.

### M7.1 tap settings contract (implemented)

- Data: `Branch.tap_ratio` is the supplied physical setting; it is never overwritten by a solve.
- Problem: `TapControl` selects optimized branches and explicit positive bounds. Omitted branches are fixed. Equal bounds fix a selected ratio. The supplied ratio is the default start; a start outside bounds requires an explicit replacement. A nominal reference affects metrics only.
- Formulation: the smooth base-case NLP computes terminal powers with variable inverse tap ratios, including charging, fixed phase shifts and both-terminal ratings. Fixed Ybus builders remain the established path for existing solves.
- Results: `TapOPFResult` records every branch ratio, the policy and the ordinary AC OPF result. Versioned result JSON supports replay; no input mutation or implicit rounding occurs.
- Validation: reconstruct the network at solved ratios and use M5/M6 independent currents and powers. Solver success, policy compliance and physical validity are distinct. `tap_design_metrics` reports supplied/nominal deviations, branch active losses and shunt active consumption without altering the objective.

This slice supports the existing smooth NLP and its optimizer factory; it does not
add a complementarity tap-design encoding. Phase shift and droop parameters stay
fixed. Equipment decision sharing across contingencies remains M9.

### M7.2 simple-bank contract (implemented)

`ShuntControl` is problem configuration keyed by installed bank ID; imported fixed
shunts cannot be selected. Only one nonzero step susceptance is supported. Legal
counts define a continuous interval; positive B is capacitive and negative B is
inductive. Optional narrower bounds must lie inside this interval. Initial B is a
numerical start (default supplied state); nominal B is a metric reference (default
bank nominal state). Neither silently changes the baseline objective.

The smooth base-case builder removes selected supplied admittances from constant
Ybus before adding variable G(B)V² and −BV² consumption. G=(Gstep/Bstep)B, so G
cannot be optimized independently. All taps, phases, droop curves and unselected
equipment remain fixed. `ShuntOPFResult` holds solved B separately. Independent
replay replaces selected banks with equivalent fixed shunts, preserving IDs and
avoiding double counting; this is an evaluation case, not an edit to installed data.
Solver, physical and policy statuses remain separate. Fractional counts are metrics,
not legal positions, schedules or switching counts. Joint controls are M7.3; SCOPF
equipment sharing is M9. Heterogeneous optimization is explicitly behind the later
simple-bank/transformer/droop scaling gate.

### M7.3 joint design contract (implemented)

`optimize_joint_design` accepts separate lists of `TapControl`, `ShuntControl` and
`DroopControl`. A selected droop has independently bounded slope, reference and
lower/upper deadband width; omitted fields keep supplied values. As in M3, the
total deadband must stay positive. Supplied values are default starts, and an
explicit start is required when bounds exclude them. The joint path reuses M3's
parameter helpers and the existing smooth droop expressions, together with the
M7 variable-tap terminal equations and simple-bank G/B mapping. It does not add a
new objective or a hidden nominal-design penalty.

`JointDesignResult` retains the ordinary AC result, all branch ratios, selected
bank susceptances, selected droop settings and their policies. Input data remain
unchanged. `with_joint_settings` reconstructs all families before independent
equilibrium validation. Policy checks cover fixed equipment and each selected
parameter bound. Metrics recompute objective components and physical losses.
Versioned JSON preserves results and policies. Existing standalone entry points
continue to work. Multi-start experiments are an evidence runner, not an implicit
change to the optimizer or a global-optimality certificate.

The research comparison uses all eight fixed/free combinations and matched
conditional benefits. Retain every start, failure and parameter spread; differences
in benefit with equipment freedom represent interactions, not additive isolated
attribution. M7 is base-case only. `Study` inputs are explicitly rejected until M9.

### Scaling-first scope revision (2026-09-20)

Transformer AVR and its M9.3 staged-security comparisons are deferred alongside
complex-bank optimization. The active controls remain fixed or OPF-optimized taps,
single-step-type banks and existing droop curves. First measure joint base-case
construction, solve, extraction and independent validation; then add M9.1 shared
preventive and M9.2 bounded corrective equipment policies. Scaling remains an
experimental gate, not an assumption established by the M7 three-bus studies.
The joint solver exposes a private observational measurement hook; it does not
alter equations, objectives, result semantics or solver options. Benchmark runners
own synthetic fixtures, timing aggregation and failure retention. Public-case and
contingency scaling are still required before selecting a new scaling algorithm.

### S1 model-change and formulation-review contract

S1 is the dedicated reliability/scaling milestone before equipment SCOPF. Begin
with an explicit mathematical description of the implemented joint model and an
equation-to-code/validator mapping. Keep data, problem configuration, formulation,
solver execution and independent validation distinct in the diagnosis.

User instruction: do not change equipment models without telling the user first.
Before implementing a physical-model correction or change, explain the equation,
assumption or capability change and its consequences. Do not silently alter the
objective, add regularization, relax equipment limits or loosen physical validation.
Numerical experiments must record their starts, solver settings, smoothing and
any equivalent variable/objective scaling; interpret residuals in original units.
The [formulation contract](docs/src/joint_formulation.md) documents the implemented
model and does not authorize new physical models. AVR and complex-bank optimization remain deferred.

### S1 derivative representation

The existing smoothed design curve is now composed from scalar softplus
operators and ordinary arithmetic. This preserves exact sparse Hessian support
in the legacy JuMP nonlinear evaluator when droop parameters are free, including
the shared M3 builder. The former five-argument registered function disabled
Hessian availability and caused Ipopt to use limited-memory approximation.
This is an equivalent numerical representation: no control law, physical limit,
objective or smoothing width changes. Independent exact-curve replay remains
separate. Diagnostics and benchmark reporting stay in examples, using the private
observational hook; they add no domain-model dependencies.


### S1 experiment ownership and public-network gate

Experiment runners own deterministic control subsets, starting states/designs,
solver options, continuation and synthetic public-case overlays. The core physics
is unchanged. Each attempt retains its start, policy, source study, native residual
convention and independent validation. MadNLP and Ipopt residuals are labelled
separately. Process high-water memory is not attributed to individual cases;
pilot timing is not a performance guarantee.

Smoothing calibration is an example-level policy, not a new default. A uniform
curve-error bound uses the minimum allowed slope and Q scale; reducing the error
can increase numerical stiffness. Public cases expose weak local design
sensitivities and solver/start variation. Equivalent scaling and primal/dual
restart support are next; penalties or equipment changes require separate review.


S1 numerical probes and failure localization remain in examples: `s1_scaling_probe.jl` varies solver scaling only; `s1_failure_details.jl` produces physical-unit equipment locations without changing the core validation report schema or acceptance decisions. `s1_audit_retained.jl` checks category agreement against the independent validator on historical evidence. Explicit variable normalization and primal/dual restart state are still pending architectural work.


S1 restart experiments keep numerical seeds separate from physical designs. `examples/s1_warm_start.jl` captures finite primal values and JuMP/MOI constraint/bound multipliers. It checks a model-layout signature, explicit formulation context and array dimensions before applying any values. These seeds are same-formulation Ipopt experiments, not portable solutions across changing equipment, smoothing, topology, periods or contingencies. Builder start records explicitly identify persisted seeds that override them. The optional example-runner hook owns numerical initialization; independent validation retains sole authority for physical acceptance. No core model/API or physical equation changes are introduced.


The experimental `examples/s1_restart_policy.jl` runner owns bounded recovery, outside the physical builders. It accepts the first independently validated result; otherwise a finite compatible seed after selected numerical failures can receive one multiplier-reset attempt. Converged-but-invalid results stop for diagnosis. There is no automatic solver switch, smoothing change, constraint relaxation or objective polishing. Context hashes cover physical case data, declared controls, smoothing, solver identity/version, and are combined with layout and finite-value guards.

The runner shares iteration and cooperative wall-time budgets across attempts. Callbacks can stop iterations at deadlines, but construction, validation and an in-progress solver step are not forcibly preempted; overruns are reported. Ipopt resets constraint/bound dual starts through its warm initializer. MadNLP resets constraint multipliers with `dual_initialized=true` and rebuilds bound multipliers using its native initialization. Full saved-bound-dual restoration in MadNLP, cross-model transfer and a public core API remain outside this increment. Attempt records preserve both solver termination and independent physical/policy validation.


S1 now offers opt-in controller coordinates through `optimize_joint_design(...; control_normalization=:bounds)`. A shared affine helper maps free droop parameters, tap ratios and bank susceptances from unit intervals into the existing physical expressions. Fixed settings bypass the transformation. Returned designs, independent validators and serialized physical result schemas are unchanged. The default remains `:none`. Experiment metadata records coordinate maps; restart context hashes include the coordinate mode, preventing mismatched seed reuse. Solver-bound pushes and raw stationarity norms are coordinate-dependent and must be interpreted accordingly. No equipment law or objective changes accompany this option.


### S1 staged initialization boundary

`examples/s1_staged_initialization.jl` composes existing joint-design solves in two independent experimental workflows: fixed controls → free equipment → free joint design, or nominal → intermediate → target demand. Temporary preparation policies restrict the original design domain; they do not change equipment equations. Load continuation changes only demand, preserving dispatch and droop references. All stages share a cooperative wall deadline and iteration budget, including the final bounded restart policy.

Only independently validated stages with settings inside the strict initialization domain supply physical primal seeds. Changed formulations receive no transferred duals. Unsuccessful stages preserve the last accepted seed. Restricted-stage feasible points are recorded separately; final acceptance still requires a solve of the full target problem. The default optimizer API and restart policy are unchanged. Stage diagnostics retain actual free-controller counts, seed lineage, failure details and budget charges. The [staged evidence](docs/src/s1_staged.md) compares each workflow with its frozen direct-solve baseline.


### S1 solution-quality diagnostics

`examples/s1_kkt.jl` reads the solved JuMP model to reconstruct physical-coordinate Lagrangian-gradient terms, complementarity and inequality-dual signs. The original native-plus-physical acceptance rule remains authoritative; diagnostic quality is a separate report. `s1_kkt_geometry.jl` rebuilds the same formulation and evaluates retained final-point Jacobians without solving, checking variable and regular-constraint layouts before reading saved multipliers. It reports near-parallel saturated-droop/active-Q-bound rows and cancellation-sensitive multiplier contributions without claiming exact rank deficiency.

Hypothetical positive row scaling is analyzed through the corresponding inverse multiplier transformation; it is not applied to a solver. Any future numerical treatment must retain physical validation and account for transformed tolerances. Local numerical dependence must be investigated before adopting blanket row equilibration. No equipment constraints are removed or changed by this diagnostic layer. See the [stationarity evidence](docs/src/s1_kkt.md).

### Experimental implied droop-Q bounds

`optimize_joint_design(...; droop_q_bounds=:implied)` provides an opt-in numerical formulation for S1 experiments. For available generators with an attached volt-var controller, it omits the generator-Q variable bounds already implied in exact arithmetic by the smoothed saturation and the validated nesting of controller capability inside generator limits. Unattached and unavailable generators retain their ordinary bounds. The `qg` variable, droop equality, power balance, objective, smoothing and result schema remain unchanged.

The default is `:explicit`. Model metadata records the selected mode and generator IDs whose bounds were omitted. Restart-context hashes include the mode so a seed cannot cross formulations silently. Independent physical validation remains mandatory and catches generator/control-limit excursions, including floating-point endpoint effects. The [S1 comparison](docs/src/s1_implied_q.md) shows mixed reliability, so this option is not promoted into normal execution or M9.

### Experimental reduced droop-Q formulation

`optimize_joint_design(...; droop_q_formulation=:reduced)` is a second opt-in
S1 formulation. For each available generator with an attached volt-var
controller, it eliminates the generator-Q variable and droop equality and
substitutes the same smoothed response into reactive-power balance and the
reactive objective term. Unattached and unavailable generator-Q variables remain
explicit. Extracted results reconstruct the eliminated Q values, so result and
validator interfaces stay unchanged.

This substitution is valid only after the existing case checks establish that
controller capability is nested inside generator capability. The reduced model
therefore has no separate controlled-generator Q bound; it cannot be combined
with `droop_q_bounds=:implied`. The formulation changes numerical initialization,
objective representation and derivative sparsity even though it preserves the
physical feasible set and objective on the declared domain. Model metadata and
restart-context hashes record the mode.

The explicit formulation remains the default. Independent validation still
checks reconstructed Q, AC balance, equipment limits and the exact droop curve.
The [paired S1 evidence](docs/src/s1_reduced_q.md) improves MadNLP but regresses
Ipopt and loses one prior MadNLP success, so reduced space remains experimental
and is not used by M9.
