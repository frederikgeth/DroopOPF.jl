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

## 18. Architecture decision rules

When choosing between implementations:

1. preserve physical meaning over solver convenience;
2. prefer a pure evaluator over duplicated solver expressions;
3. prefer an adapter over a hard dependency;
4. prefer a small vertical slice over speculative generality;
5. prefer explicit diagnostics over silent fallback behavior;
6. benchmark before introducing a new backend;
7. require tests for every new formulation or control mode.
