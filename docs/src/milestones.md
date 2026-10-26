# Milestones and validation

Choose a label to see its report, validation tables or available figures. **M** labels describe library capabilities; **S** labels describe study campaigns; **P** labels describe development priorities. They overlap and are not independent experiments to add together.

Implementation, numerical acceptance and research closure are separate. Historical results retain their original policies and dates.

## Capability milestones

| ID | What it does | Status / scope | Report | Tables | Figures |
| --- | --- | --- | --- | --- | --- |
| M1 | Solve base AC dispatch with supplied reactive-response curves. | Implemented; declared small-case evidence | [Report](@ref evidence-m1-report) | [Tables](@ref evidence-m1-tables) | — |
| M2 | Couple base and outage equilibria with an explicit active-response policy. | Implemented; declared small-case evidence | [Report](@ref evidence-m2-report) | [Tables](@ref evidence-m2-tables) | — |
| M3 | Optimize declared droop parameters shared across training scenarios. | Implemented; declared bounded-family evidence | [Report](@ref evidence-m3-report) | [Tables](@ref evidence-m3-tables) | — |
| M4 | Measure repeated-start behavior, diagnostics and small public-case reproducibility. | Implemented; bounded robustness evidence | [Report](@ref evidence-m4-report) | [Tables](@ref evidence-m4-tables) | — |
| M5 | Represent fixed transformer ratios, phase shifts, availability and terminal ratings. | Implemented; declared equipment-physics evidence | [Report](@ref evidence-m5-report) | [Tables](@ref evidence-m5-tables) | — |
| M6 | Represent fixed shunts and supplied legal bank states. | Implemented; declared equipment-physics evidence | [Report](@ref evidence-m6-report) | [Tables](@ref evidence-m6-tables) | — |
| M7 | Choose selected continuous taps, simple-bank susceptance and bounded droop parameters. | Implemented; synthetic base-case comparisons | [Report](@ref evidence-m7-report) | [Tables](@ref evidence-m7-tables) | [Figures](@ref evidence-m7-figures) |
| M8 | Model an automatic transformer voltage-regulation equilibrium with limits. | Implemented; bounded static-control tests | [Report](@ref evidence-m8-report) | [Tables](@ref evidence-m8-tables) | — |
| M9 | Coordinate preventive equipment, automatic response and bounded corrective recourse. | Implemented; declared synthetic policy evidence | [Report](@ref evidence-m9-report) | [Tables](@ref evidence-m9-tables) | — |
| M10 | Assess catalogues, compare control modes and close bounded physics/reproducibility gates. | Declared scope complete; general qualification remains separate | [Report](@ref evidence-m10-report) | [Tables](@ref evidence-m10-tables) | — |

## Study campaigns

| ID | What it does | Status / scope | Report | Tables | Figures |
| --- | --- | --- | --- | --- | --- |
| S1 | Test base-operation droop/equipment optimization across control families and demand samples. | Historical declared scope closed; new deadband sensitivity separate | [Report](@ref evidence-s1-report) | [Tables](@ref evidence-s1-tables) | — |
| S2 | Design one controller across training demands/outages and test it on held-out demands. | 14-bus declared scope closed; original 500-bus campaign paused | [Report](@ref evidence-s2-report) | [Tables](@ref evidence-s2-tables) | — |

## Development priorities

| ID | What it does | Status / scope | Report | Tables | Figures |
| --- | --- | --- | --- | --- | --- |
| P0 | Establish the smallest executable model-to-independent-validation workflow. | Implemented; declared proof-of-concept scope | [Report](@ref evidence-p0-report) | [Tables](@ref evidence-p0-tables) | — |
| P1 | Make studies repeatable, diagnosable and serializable. | Implemented; declared small-case workflow evidence | [Report](@ref evidence-p1-report) | [Tables](@ref evidence-p1-tables) | — |
| P2 | Improve larger security studies while retaining complete final AC qualification. | Broader P2 open; latest declared connected-catalogue design qualified | [Report](@ref evidence-p2-report) | [Tables](@ref evidence-p2-tables) | [Figures](@ref evidence-p2-figures) |
| P3 | Add multi-period, data-adapter and mixed-control capabilities as qualified slices. | Selected slices implemented; broader extensions open | [Report](@ref evidence-p3-report) | [Tables](@ref evidence-p3-tables) | — |

## Sharing and provenance

Use the [reports](validation_reports.md), [tables](validation_tables.md) and [figure gallery](validation_figures.md) separately. The [evidence register](validation_evidence.md) records source identities and the portable sharing format. Full research archives remain private; a dash means no figure is bundled for that label. Historical figure sets remain private.
