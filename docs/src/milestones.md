# Milestone and evidence index

Implementation, numerical qualification and research closure are separate statuses.
The [release scope](release_scope.md) records the current supported boundaries.
Original campaign policies remain attached to their results; later success does
not rewrite an earlier failure or migrate historical S2 results to P2 semantics.

| Milestone | Documentation / evidence | Status and boundary |
|---|---|---|
| M1–M4: OPF, SCOPF, droop design and robustness | [SCOPF](scopf.md), [droop design](droop_optimization.md), [robustness](robustness.md) | Historical implementation milestones completed within their declared small-case scope |
| M5–M6: transformer and shunt models | [Data model](data_model.md) | Implemented static equipment models; original numerical evidence archived |
| M7: continuous equipment and joint droop design | [Equipment studies](equipment_optimization.md), [selected figures](validation_evidence.md) | Synthetic base-case comparisons; continuous settings, local solutions |
| M8–M9: equipment control and coordinated security design | [Data model](data_model.md), [SCOPF](scopf.md) | Steady-state control models and declared security policies; discrete actions and dynamics remain separate |
| M10: contingency assessment and comparative evidence | [Assessment workflow](scopf.md), [security design](droop_security.md) | Complete for declared assessment/comparison scope; not general network security certification |
| S1: convergence and scale | [Release scope](release_scope.md), archived S1 closeout | Closed within declared sampled 14/500-bus base-operation scope |
| S2: shared security design | [Release scope](release_scope.md), archived S2 reports | Declared 14-bus scope closed; original 500-bus campaign paused |
| P1: research workflow | [Validation](validation.md), [robustness](robustness.md) | Implementation and declared small-case workflow evidence retained |
| P2: scaling and qualification | [Mixed controls](mixed_avr_droop.md), [latest reference report](validation_evidence.md) | Latest mixed 500-bus design passes all 389 connected outages at five periods; broader P2 remains open |
| P3: extended models | [Multi-period](multi_period.md), [PSS/E](psse.md), [mixed controls](mixed_avr_droop.md) | Implemented slices; native RAW v36 export qualification, storage, detailed GFL/GFM and dynamics remain open |

## Evidence structure

Each submilestone should identify its scope and assumptions, model equations,
runnable example, machine-readable results, readable report and specified
figures/tables. Acceptance separates native solver termination, physical replay,
operating limits and control-policy compliance. A numerical failure is unresolved
unless separate evidence establishes infeasibility under the stated contract.

Sealed campaigns additionally record input/source hashes and output manifests.
Historical layouts vary; not every early milestone has the same folder template.
The [research archive guide](research.md) explains how to recover full records.

For future reports, record the date, source revision, input identity, network and
contingency coverage, objective, control sharing, movement/timing assumptions,
acceptance tolerances, rejected attempts, independent replay and remaining gates.
Keep new campaigns separate when any physical or information policy changes.

## Documentation maintenance

Update this index and the release scope when qualification changes. Keep historical
outcomes labelled by campaign; link current summaries to compact evidence with
provenance. Package CI and documentation builds establish software integrity,
not renewed acceptance of every archived large-network experiment.
