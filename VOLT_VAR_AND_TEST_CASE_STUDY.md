# Volt-Var Control and Published Test-Case Study

**Status:** design input for M1

**Date:** 2026-09-04

**Scope:** steady-state voltage/reactive-power control of synchronous generators connected to transmission networks, and public datasets that can support DroopOPF.jl unit and integration tests.

## Executive conclusions

1. A synchronous transmission generator is normally represented as a generator plus an automatic voltage regulator (AVR)/excitation system. The physical control loop regulates a measured voltage by changing field excitation; reactive power is the network consequence, constrained by the machine capability curve and excitation/stator limiters.
2. The operational object is usually not a universal four-point `Q(V)` curve. It is a voltage schedule—target, tolerance band, and regulated location—implemented by an AVR or plant controller and bounded by a `P-Q` capability region. An explicit voltage droop may be included, but its settings are normally site- and system-operator-specific.
3. The most important differentiation is the measurement/control location: alternator terminals, generator low-voltage bus, high-voltage side of the step-up transformer, connection point/point of interconnection, or a remote transmission bus. Transformer and line impedance make these materially different models.
4. Network region matters because reactive power is local and voltage sensitivity depends on network strength, meshing, line length, local load, and the amount of nearby reactive reserve. ENTSO-E explicitly notes that more than one reactive capability profile may be appropriate within a system operator's area.
5. There are many public cases with solved or readily reproducible AC power-flow equilibria, but no broadly accepted public suite of transmission cases containing validated synchronous-generator volt-var curves, AVR settings, limiter settings, and equilibrium states together.
6. For M1, use published static cases as the network truth, add an explicitly documented synthetic droop overlay, and generate/persist DroopOPF equilibrium fixtures with provenance and independent residual checks. Treat those fixtures as DroopOPF reference data, not as published industry measurements.

## 1. What “volt-var droop” means for a synchronous generator

### 1.1 Physical interpretation

At steady state, a synchronous generator's excitation system establishes an internal field voltage. The generator exchanges reactive power with the network according to the terminal voltage, machine reactances, transformer impedance, network operating point, and active/reactive limits. A simplified control loop is:

```text
voltage schedule / reference
            ↓
 voltage error + optional droop / reactive-current compensation
            ↓
 AVR / excitation system
            ↓
 field voltage and internal emf
            ↓
 generator terminal voltage and reactive-power exchange
```

The static abstraction used by M1 can be written, with positive `Q` meaning reactive injection into the network, as:

```math
Q_g = \operatorname{clip}\left(Q_\mathrm{bias} - \frac{V_m - V_\mathrm{ref}}{m},
                               Q_\min(P_g,V_m), Q_\max(P_g,V_m)\right).
```

Here:

- `V_m` is the voltage magnitude at the agreed measurement/control location;
- `V_ref` is the voltage schedule target;
- `m > 0` is the voltage-per-reactive-power droop slope;
- `Q_bias` is the reactive output at the center of the deadband, often zero at the selected reference;
- `Q_min` and `Q_max` are operating limits, ideally dependent on active power and voltage.

This is a useful steady-state model, not a claim that the detailed AVR is literally a static `Q(V)` device. In particular, an AVR can hold voltage tightly until a limiter becomes active, after which the equilibrium is determined by a different active constraint.

### 1.2 Typical curve shape

For a simple voltage-droop controller, the curve is monotone decreasing when plotted as network reactive injection against voltage:

```text
 Q injection
     ↑       Qmax ────────────────┐
     │                            │
     │                    slope   │
     │                         ────┘
     │             deadband
     │                         ────┐
     │                    slope   │
     │                            │
     │       Qmin ────────────────┘
     └────────────────────────────────→ V
             low       Vref       high
```

The exact curve may instead be expressed as:

- constant voltage control with a tolerance band;
- constant reactive-power control;
- constant power-factor control;
- voltage control with an explicit droop;
- voltage control with reactive-current or line-drop compensation;
- a piecewise curve with asymmetric leading/lagging response;
- a controller whose effective `Q` limits change with `P`, terminal voltage, or limiter state.

PJM's generator operating manual describes voltage control as reactive output varying to maintain a reference voltage within an assigned bandwidth, up to the generator's reactive capability. It also distinguishes voltage, MVAR, power-factor, and manual modes. This is a better starting point for a transmission-generator abstraction than assuming an inverter-style curve is always present. [PJM Manual 14D, Section 7](https://www.pjm.com/-/media/DotCom/documents/manuals/archive/m14d/m14dv60-generator-operational-requirements-10-01-2022.pdf)

NERC's inverter-based-resource guideline gives a useful illustrative convention: if the scheduled voltage is 1.0 pu and the acceptable range is 0.95–1.05 pu, moving from full leading to full lagging reactive output across that range corresponds to a 5% voltage-reactive droop. That example is useful for understanding droop notation, but it should not be copied as a universal synchronous-generator setting. [NERC IBR Performance Guideline, Chapter 3](https://www.nerc.com/globalassets/who-we-are/standing-committees/rstc/irpwg/inverter-based_resource_performance_guideline.pdf)

### 1.3 Droop, deadband, and capability are different concepts

These should be separate fields in the M1 data model:

| Concept | Meaning | Typical source | M1 representation |
|---|---|---|---|
| Voltage schedule | Target/range supplied by the transmission operator | Operating rule or connection agreement | `V_ref`, lower/upper schedule limits |
| Droop | Steady-state slope relating voltage deviation to reactive response | Connection agreement, plant model, or study assumption | `m` or normalized `%` setting |
| Deadband | Voltage interval with no or reduced corrective response | Controller setting / operating agreement | Explicit low/high breakpoints |
| Capability | Feasible `P-Q` operating region of the generator and plant | Test, manufacturer data, grid-code evidence | `Q_min(P,V)`, `Q_max(P,V)` |
| Limiter | Active control/protection boundary, e.g. OEL, UEL, stator current | Excitation model and testing | Optional active-limit model |
| Regulated location | Voltage measurement/control point | Connection agreement and model | Bus/terminal/remote-bus reference |

Do not encode a capability curve as if it were a droop curve. A generator can be capable of a large reactive range while its voltage controller is configured to use only part of it in a particular operating mode.

## 2. How curves differ across a transmission network

### 2.1 Control location is the primary distinction

The same generator can have materially different `Q(V)` behavior depending on where voltage is measured.

#### Alternator terminal control

This is the traditional unit-level synchronous-machine arrangement. The AVR measures and regulates the alternator terminal voltage. It is fast and local, but the voltage at the high-voltage connection point also depends on the generator step-up transformer and the network.

AEMO describes unit-level voltage control as a long-established strategy for synchronous machines. For a machine with a step-up transformer, fast terminal-voltage response produces a voltage-droop response at the connection point because of the intervening impedance. [AEMO Technical Requirements Review, Section 3.10](https://www.aemo.com.au/-/media/files/stakeholder_consultation/consultations/nem-consultations/2022/aemo-review-of-technical-requirements-for-connection-ner-clause-526a/2023-03-03_technical-requirements-review_draft-report_final.pdf?la=en)

#### Generator bus or low-voltage side of the step-up transformer

This is a useful compromise for a plant with multiple machines. Unit AVRs may regulate their own terminals while a supervisory control or coordination rule refers to a common bus. The resulting curve includes the transformer and collector-system impedance between the controlled unit and the common bus.

#### High-voltage side / point of interconnection control

This is the most natural point for a transmission-system operator because it is where the plant exchanges power with the network. It captures the plant's transformer losses and reactive demand and makes the schedule comparable across facilities. It also makes the controller's response dependent on the local network strength and topology.

The EU Requirements for Generators code applies the synchronous-generator reactive capability requirement at the connection point and allows the system operator to specify a `U-Q/Pmax` profile for varying voltage. It also requires the generator to be able to move within that profile on appropriate timescales. [Commission Regulation (EU) 2016/631, Articles 17–19](https://eur-lex.europa.eu/eli/reg/2016/631/oj/)

#### Remote transmission-bus control

A generator may regulate a remote bus when that is agreed with the system operator. This is more system-effective in some voltage-control areas, but it increases sensitivity to line outages, changes in network impedance, and multiple controllers acting on the same bus. It should be represented explicitly as a remote measurement location, not as a property of the local generator bus.

### 2.2 Network strength and topology

The local voltage response to a reactive injection is approximately governed by a voltage sensitivity such as:

```math
\Delta V \approx S_{VQ}\,\Delta Q.
```

The sensitivity is not constant across the grid. It changes with:

- Thevenin impedance and short-circuit strength near the generator;
- the generator's electrical distance from the controlled bus;
- meshed versus radial topology;
- long transmission lines and cable charging;
- transformer tap and phase-shifting settings;
- local load composition and operating level;
- nearby generators, synchronous condensers, shunts, and FACTS devices;
- outages and islanding.

ENTSO-E explicitly identifies network meshing and the ratio of in-feed to consumption as factors in reactive capability requirements, and notes that different profiles may be appropriate in different regions of one system operator's area. It also notes that reactive production at high voltage and reactive consumption at low voltage may not be necessary in all regions. This is a capability-profile statement rather than a universal droop rule, but it is directly relevant to how we generate differentiated cases. [EU Regulation 2016/631, recital 24 and Article 18](https://eur-lex.europa.eu/eli/reg/2016/631/oj/)

### 2.3 Generator and plant characteristics

The feasible response differs by machine and operating point:

- `Q_max` is often limited by field current, over-excitation, and stator heating;
- `Q_min` is often limited by under-excitation, end-region heating, stability, or UEL action;
- both limits depend on active power, terminal voltage, cooling conditions, and machine design;
- a synchronous condenser has excitation capability but no active-power/prime-mover constraint;
- a multi-unit plant may have aggregate capability that is not the simple sum of independent rectangular unit limits;
- supervisory limits may be stricter than the physical machine capability.

WECC's generator testing requirements ask for V-curve measurements at multiple load points and for generator control, limiter, and protection curves to be superimposed on the machine reactive capability curve. They separately request line-drop/reactive-current compensation data and high-voltage-bus-controller information. This is a useful template for the fields DroopOPF should eventually support. [WECC Generating Facility Testing and Model Validation Requirements](https://www.wecc.org/sites/default/files/documents/meeting/2024/WECC%20Gen%20Fac%20Testing%20and%20Model%20Validation%20Rqmts%20v%204-23-2020.pdf)

### 2.4 Coordination between multiple controllers

Two or more generators controlling the same electrically close bus can fight, saturate, or share reactive power unpredictably. Common coordination mechanisms are:

- distinct voltage references or intentional droop slopes;
- a common regulated bus with plant-level allocation;
- reactive-current compensation;
- deadbands selected to avoid simultaneous small-signal hunting;
- separated controller bandwidths, with fast unit-level control and slower plant-level setpoint coordination;
- an explicit reactive-power-sharing rule.

AEMO stakeholder material specifically raises the risk of multiple units fighting to establish local voltage when there is insufficient impedance between them, and notes that a common controlled location can improve sharing. [AEMO stakeholder analysis for S5.2.5.13](https://www.aemo.com.au/-/media/files/stakeholder_consultation/consultations/nem-consultations/2022/aemo-review-of-technical-requirements-for-connection-ner-clause-526a/documents/appendix-a1-stakeholder-consultation-analysis-and-revised-recommendations.pdf?la=en)

For M1, this argues for modelling controller ownership and regulated locations explicitly, even if the first implementation supports only one droop controller per generator and one local bus.

## 3. Implications for the M1 model

### 3.1 Recommended M1 semantics

M1 should implement a documented steady-state controller, not pretend to be a full AVR simulation:

```text
Generator active-power decision ─┐
                                 ├─ P-dependent Q capability
Voltage at regulated location ───┤
                                 ├─ exact PWL or smooth droop response
Voltage schedule and droop ──────┤
                                 └─ Q command / equilibrium constraint
```

The first physical reference model should be an exact piecewise-linear curve with:

- positive network-injection sign convention;
- configurable `V_ref` or center deadband;
- configurable `V_db_low`, `V_db_high`;
- configurable `Q_db`;
- low- and high-voltage saturation;
- `Q_min(P)` and `Q_max(P)` capability limits;
- an explicit regulated-location identifier;
- a declared unit/base system.

The softplus encoding can then be used as a solver formulation, but all test expectations should be evaluated against the exact PWL curve and independently replayed after solving.

### 3.2 What not to infer from published cases

Do not infer the following from a MATPOWER or PGLib case unless the source explicitly says so:

- that every PV bus represents an AVR with a known droop;
- that `Vg` is the voltage controlled at the connection point;
- that `Qmin/Qmax` are measured machine capability curves;
- that a generator's reactive limits remain constant as `P` changes;
- that the case contains a validated dynamic equilibrium;
- that the case's initial voltage values are a certified solution rather than a starting point.

MATPOWER documents that a solved power-flow result includes bus voltage magnitudes/angles and generator `P/Q`, and can be saved as a solved case. That gives us a reproducible static equilibrium, but not the missing controller and machine-internal data. [MATPOWER `runpf` documentation](https://matpower.app/manual/matpower/ttrunpf.html)

## 4. Public datasets and their usefulness

### 4.1 Ranked dataset inventory

| Dataset / source | What it provides | Equilibrium status | Volt-var/AVR status | M1 usefulness | Recommendation |
|---|---|---|---|---|---|
| MATPOWER standard cases / UW PSTCA | IEEE 9/14/30/39/57/118/300-style static transmission networks; common formats and solved PF workflows | Solved PF is readily reproducible; many case files contain plausible solved values | Generally no validated AVR/droop parameters | Excellent for parser, AC equations, and small regression fixtures | **Use first** |
| PowerDynamics.jl IEEE 9- and 39-bus examples | Synchronous machine, AVR, governor, transmission lines, and explicit PF-to-dynamic initialization workflow | Yes, equilibrium is constructed and checked through initialization | Pedagogical/control parameters, not a standard industry benchmark | Best public starting point for understanding generator/control equilibrium linkage | **Use for M1 design and later cross-checks** |
| PGLib-OPF | Curated AC-OPF networks in MATPOWER format, including typical, API, and SAD variants; published OPF baselines | Reference OPF objective values; full equilibrium can be recomputed, but not a droop equilibrium | No complete synchronous AVR/droop data | Excellent for OPF regression and scale tests; not a droop ground truth | **Use after base M1 works** |
| NESTA | Extended transmission cases with reconstructed limits and optimization-oriented metadata | Static AC feasibility/OPF can be solved; not a dynamic equilibrium archive | No validated AVR/droop suite | Good for stressed operating points and data-model completeness | **Use for stress tests** |
| iTesla/RTE/PEGASE cases | Large French and European HV network snapshots in MATPOWER/QCQP form | Published data validity and reproducible PF/OPF workflows | No public complete generator control data | Good for large-network import and numerical scaling | **Use for M1 scale gate, not unit tests** |
| RTS-GMLC | Updated reliability test system, generator fleet, outages, timeseries, MATPOWER and other formats | Base PF and operational snapshots are reproducible; scenario data is rich | Public core is not a validated synchronous AVR/droop dataset | Good for later scenario generation and operational studies | **Use selectively** |
| PowerSystemsTestData | Julia-native data repository including MATPOWER, RTS-GMLC, large ACTIVSg systems, and PSSE dynamic-data folders | Depends on case; generally initialize/solve through Sienna tools | Useful dynamic model data exists, but not a universal solved-droop bundle | Good integration source for the Julia ecosystem | **Reuse adapters, inspect licenses and versions** |
| PFΔ | 859,800 solved PF instances over IEEE 14/30/57/118 and GOC 500/2000, including N, N-1, N-2 and near-infeasible samples | Explicit solved PF dataset | No droop/AVR ground truth | Excellent residual, contingency, and near-collapse validation corpus | **Use after ingestion infrastructure exists** |
| UW dynamic archive | 17-generator/162-bus, New England 30-bus, and 50-generator/145-bus dynamic cases | Includes solved PF for at least the 17-generator case; formats are old | Dynamic data is available, but control coverage and interpretation require care | Valuable historical dynamic reference; high conversion cost | **Investigate, do not make M1-critical** |

### 4.2 MATPOWER and the UW Power Systems Test Case Archive

The University of Washington archive provides classic power-flow cases and dynamic cases. Its dynamic section includes a 17-generator system with a 162-bus solved power flow, a New England 30-bus dynamic case, and a 50-generator/145-bus case. [UW Power Systems Test Case Archive](https://labs.ece.uw.edu/pstca/)

The 17-generator case is particularly relevant because the archive explicitly describes a solved 162-bus power flow and accompanying classical dynamic data. It may support a later dynamic-equilibrium cross-check, but classical machine data alone is not equivalent to a validated AVR/volt-var model. [17-generator dynamic case](https://labs.ece.uw.edu/pstca/dyn17/pg_tcadd17.htm)

### 4.3 PowerDynamics.jl as a control-equilibrium reference

PowerDynamics.jl is unusually useful for this project because its documentation makes the equilibrium construction explicit:

1. build a static power-flow model;
2. solve the power flow;
3. extract bus voltages and currents;
4. initialize machine, AVR, governor, and load states so the dynamic model reproduces those interface values;
5. verify that derivatives are zero at the initialized operating point.

Its IEEE 9-bus example uses sixth-order Sauer-Pai synchronous machines, an `AVRTypeI`, and a `TGOV1` governor. Its IEEE 39-bus tutorial contains a larger multi-machine example and shows the same power-flow-to-initialization pattern. [PowerDynamics initialization documentation](https://juliaenergy.github.io/PowerDynamics.jl/stable/initialization/), [IEEE 9-bus example](https://juliaenergy.github.io/PowerDynamics.jl/latest/generated/ieee9bus/), [IEEE 39-bus modeling tutorial](https://juliaenergy.github.io/PowerDynamics.jl/stable/generated/ieee39_part1/)

These are not substitutes for an independently published transmission operator case, but they are strong references for the distinction between a static PF equilibrium and a dynamic-machine/controller equilibrium.

### 4.4 PGLib-OPF and NESTA

PGLib-OPF is maintained by the IEEE PES Task Force on Benchmarks for Validation of Emerging Power System Algorithms. The cases are curated for a well-defined AC-OPF problem, use MATPOWER format, and publish baseline results. The repository itself cautions that applying them to other problem variants should be done with discretion. [PGLib-OPF repository](https://github.com/power-grid-lib/pglib-opf), [PGLib baseline results](https://github.com/power-grid-lib/pglib-opf/blob/master/BASELINE.md)

NESTA was created partly because older power-flow cases often omit optimization-relevant information such as thermal limits and generator capability curves. It reconstructs or extends this information from public sources. That makes NESTA useful for OPF stress testing, while its reconstructed data should be labelled as such and not mistaken for plant test data. [NESTA paper and archive description](https://arxiv.org/abs/1411.0359)

### 4.5 RTS-GMLC and Sienna test data

RTS-GMLC is valuable because it adds generator fleet and outage context to a classic reliability system. The public data includes generator active/reactive setpoints and limits, voltage setpoints, unit minimum/maximum output, branch continuous/long-term/short-term ratings, and outage-related fields. [RTS-GMLC MATPOWER case](https://github.com/GridMod/RTS-GMLC/blob/master/RTS_Data/FormattedData/MATPOWER/RTS_GMLC.m), [Sienna RTS-GMLC data description](https://github.com/Sienna-Platform/PowerSystemsTestData/blob/master/RTS_GMLC/README.md)

Use it for realistic operating/scenario generation, but do not assume that its `Q` limits are a tested synchronous-machine capability curve or that its voltage setpoint encodes droop.

### 4.6 PFΔ: solved power-flow data at scale

PFΔ is the strongest candidate for automated equilibrium residual tests once M1 has a data-ingestion layer. Its repository describes 859,800 solved power-flow instances across six systems, with original, N-1, and N-2 topology configurations, plus near-infeasible samples generated using continuation power flow. The repository also includes Julia dependencies for data generation and validation. [PFΔ repository](https://github.com/MOSSLab-MIT/pfdelta)

PFΔ does not solve the missing droop-data problem. Its value is different: it can test whether our network equations, topology overlays, bus indexing, residual evaluator, and contingency handling reproduce a large collection of static equilibria.

## 5. Recommended test-case acquisition plan for M1

### Tier 0: tiny analytical fixtures

Create and maintain small DroopOPF-owned cases with exact expected behavior:

- one generator, one load, one slack bus;
- two-bus generator-to-infinite-bus case with a transformer impedance;
- three-bus case with two generators, unequal droops, and one load;
- one local-regulated and one remote-regulated version;
- explicit deadband-edge and `Q`-saturation points.

These are the only fixtures where we should assert exact curve-region membership and hand-check the expected response.

### Tier 1: published static network + documented synthetic droop overlay

Start with:

1. MATPOWER IEEE 9-bus or the PowerDynamics IEEE 9-bus topology for the integrated M1 demonstration;
2. IEEE 14-bus for a canonical static regression case;
3. IEEE 39-bus for a multi-generator transmission case.

For each case, add a versioned DroopOPF overlay containing:

- generator-to-controller attachments;
- regulated bus/location;
- `V_ref`, deadband, droop, and `Q_db`;
- `Q_min(P)` and `Q_max(P)` assumptions;
- the rationale for each synthetic parameter;
- source case version and checksum;
- reference solver and tolerances;
- generated equilibrium values and residual summary.

### Tier 2: operating-point and stress corpus

Add PGLib/NESTA typical, API, and SAD variants; then RTS-GMLC and selected PFΔ samples. Use them to test:

- stressed voltage conditions;
- generator reactive-limit activation;
- multiple local sensitivities;
- topology and generator outage overlays;
- near-infeasible or poorly conditioned states.

Do not store a large downloaded corpus directly in the repository. Store a manifest with source URL, version/tag or commit, license, checksum, selected case IDs, and a deterministic preprocessing recipe.

### Tier 3: dynamic-equilibrium cross-check

Use PowerDynamics.jl or PowerSimulationsDynamics.jl to cross-check a small number of cases where a synchronous machine, AVR, and governor are initialized from the same static operating point. The cross-check should answer:

- Does the static droop equilibrium map to a zero-derivative dynamic state?
- Does the selected measurement point agree with the dynamic model's terminal or remote-voltage signal?
- Do the static `Q` limits agree with the dynamic excitation and limiter state?

This is a validation exercise, not an M1 dependency.

## 6. Proposed M1 test matrix

| Test family | Fixture | Main assertion |
|---|---|---|
| Curve algebra | Tiny hand-built cases | Exact PWL response, signs, slopes, deadband, saturation |
| Capability coupling | Two-bus / three-bus | `Q` limits vary correctly with `P`; no impossible dispatch |
| Local control | IEEE 9-bus | Equilibrium satisfies AC balance and each local droop equation |
| Multiple generators | IEEE 14 or 39 | Controller attachments are unambiguous; reactive sharing is reproducible |
| Remote regulation | Synthetic transformer/remote-bus case | Voltage is measured at the declared location, not the generator bus |
| Limit activation | IEEE 9/14 with tightened `Q` bounds | Droop residual and active-limit finding are both reported |
| Solver encoding | Same cases, exact PWL vs softplus | Smooth formulation converges to a point whose exact-curve replay is within tolerance |
| Independent validation | All M1 cases | Fresh residual evaluator reproduces balance, controller, capability, and voltage checks |
| Static corpus | PGLib/NESTA/PFΔ samples | Network equilibrium residuals and indexing are correct |
| Dynamic cross-check | PowerDynamics IEEE 9-bus subset | Initialized machine/controller derivatives are approximately zero |

## 7. Data-model additions implied by this study

The M1 data model should reserve these concepts even if some are initially unsupported:

```julia
struct RegulatedLocation
    kind::Symbol                 # :generator_terminal, :bus, :branch_terminal, :remote_bus
    bus_id::Int
    side::Union{Nothing,Symbol}  # :from, :to, or nothing
end

struct VoltageSchedule{T}
    v_ref::T
    v_db_low::T
    v_db_high::T
    unit::Symbol                 # :pu initially
end

struct VoltVarDroop{T,C}
    schedule::VoltageSchedule{T}
    slope::T
    q_at_deadband::T
    capability::C
    response::Symbol             # :exact_pwl or :softplus
end

struct GeneratorControlAttachment
    generator_id::Int
    controller_id::Int
    location::RegulatedLocation
    priority::Symbol             # :unit, :plant, :system
end
```

The important design choice is that `location` and `capability` are first-class objects. A `droop` field attached directly to a generator without those relations will be insufficient for remote control, step-up-transformer effects, plant aggregation, and later SCOPF overlays.

## 8. Lessons for implementation and scientific claims

- Use grid codes and operator manuals to define vocabulary, control locations, and required evidence—not to invent a single universal droop setting.
- Use published static cases for network topology and power-flow equilibria.
- Use explicit synthetic overlays for missing droop/controller information and label them clearly.
- Preserve source and transformed data separately; never overwrite the source case with generated controller data.
- Pin case versions and record checksums. Public repositories change.
- Store equilibrium fixtures in a solver-independent, normalized format rather than only as solver-specific output.
- Validate both the solver encoding and the exact physical curve. A smooth approximation is not the physical reference.
- Treat `Q` limits as operating capability, not as proof that the generator's AVR can achieve every point instantly.
- For M1, keep dynamic states out of the optimization model. Use dynamic tools only for selected initialization cross-checks.
- Publish our own small droop-equipped equilibrium cases early. The absence of a public complete benchmark is an opportunity for DroopOPF to provide one later.

## 9. Immediate actions before M1 implementation

1. Select the M1 primary demonstration topology: recommended **IEEE 9-bus**, with a two-bus analytical fixture and IEEE 39-bus as the first scale check.
2. Define the sign convention and normalized droop parameterization in the public API.
3. Add `RegulatedLocation`, `VoltageSchedule`, and capability objects before implementing the solver encoding.
4. Build a small reference equilibrium generator that solves the exact PWL model and writes residual-checked fixtures.
5. Add MATPOWER ingestion with source/version metadata; do not add large external datasets yet.
6. Create two synthetic topology/control variants: local terminal control and remote/POI control through a step-up transformer.
7. Add a comparison notebook or test report that shows voltage, `Q`, curve region, active limit, and residuals for every generator.
8. Defer PFΔ, large PGLib cases, and dynamic cross-checks until the Tier 0/Tier 1 tests are stable.

## References

- [Commission Regulation (EU) 2016/631 — Requirements for Generators](https://eur-lex.europa.eu/eli/reg/2016/631/oj/)
- [AEMC National Electricity Rules, clause S5.2.5.13 — Voltage and reactive power control](https://energy-rules.aemc.gov.au/ner/743/757157)
- [AEMO review of technical requirements for connection](https://www.aemo.com.au/-/media/files/stakeholder_consultation/consultations/nem-consultations/2022/aemo-review-of-technical-requirements-for-connection-ner-clause-526a/2023-03-03_technical-requirements-review_draft-report_final.pdf?la=en)
- [NERC VAR-001-6 — Voltage and Reactive Control](https://www.nerc.com/globalassets/standards/projects/2018-03/var-001-6_clean_02272019.pdf)
- [NERC Inverter-Based Resource Performance Guideline](https://www.nerc.com/globalassets/who-we-are/standing-committees/rstc/irpwg/inverter-based_resource_performance_guideline.pdf)
- [PJM Manual 14D — Generator Operational Requirements](https://www.pjm.com/-/media/DotCom/documents/manuals/archive/m14d/m14dv60-generator-operational-requirements-10-01-2022.pdf)
- [WECC Generating Facility Testing and Model Validation Requirements](https://www.wecc.org/sites/default/files/documents/meeting/2024/WECC%20Gen%20Fac%20Testing%20and%20Model%20Validation%20Rqmts%20v%204-23-2020.pdf)
- [MATPOWER `runpf` documentation](https://matpower.app/manual/matpower/ttrunpf.html)
- [UW Power Systems Test Case Archive](https://labs.ece.uw.edu/pstca/)
- [PowerDynamics.jl initialization](https://juliaenergy.github.io/PowerDynamics.jl/stable/initialization/)
- [PowerDynamics.jl IEEE 9-bus example](https://juliaenergy.github.io/PowerDynamics.jl/latest/generated/ieee9bus/)
- [PGLib-OPF](https://github.com/power-grid-lib/pglib-opf)
- [NESTA](https://arxiv.org/abs/1411.0359)
- [RTS-GMLC](https://github.com/GridMod/RTS-GMLC)
- [PowerSystemsTestData](https://github.com/Sienna-Platform/PowerSystemsTestData)
- [PFΔ solved power-flow dataset](https://github.com/MOSSLab-MIT/pfdelta)
