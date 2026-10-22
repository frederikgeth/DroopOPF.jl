# Current study configuration

## User update (2026-10-21)

The user replaced preventive equal-weight fixed participation with limit-aware
automatic active-power response. Use capability-range default weights among
available generators with nonzero effective active range unless actual response
weights are supplied. Enforce equipment and declared response-movement limits;
saturated generators stop moving while remaining participants take over.
Zero-weight units hold their base active output. Do not use the obsolete fixed
equal-sharing equation as the current study policy.

## Staged control configuration authorized (2026-10-21)

The user authorized staged comparisons before reassessing P2:
1. A fixed supplied-equipment / fixed supplied-droop baseline.
2. One shared droop design across training demands and outages, equipment fixed.
3. Shared droop plus selected preventive equipment settings, shared across all
   training demands and outages; zero post-outage equipment movement.
Each demand may optimize its own preventive base dispatch in all matched lanes;
this differs from historical fixed-base assessment. Use the same objective and
operating limits across lanes. Freeze designed curves and equipment for held-out demand evaluation. Do not
retune controls separately for held-out demands or individual outages.

For the initial comparison, droop slopes use 0.5–2 times supplied slopes,
references use supplied +/-0.02 pu, and deadband widths remain fixed. Selected
transformer ratios use supplied +/-5% as an explicitly assumed sensitivity
envelope, not verified manufacturer capability. Only existing simple banks with
supplied legal-count envelopes may be selected. Fixed shunts without adjustable
bank metadata remain fixed. Shunt settings are continuous relaxations.

The initial study scope is the existing bank-equipped fixture and 14/39-bus P2
cases (connected branch comparison, with full-catalog supply/cut obstructions
reported separately), with five training demands (90/95/100/105/110%) and four held-out demands
(92.5/97.5/102.5/107.5%). This is a development comparison, not general P2 closure.
Report selected devices, bounds, sharing, timing and movement budgets before runs.
The user does not require repeated equipment confirmation within this scope.

Corrective tap/shunt movement remains deferred until actionable devices, timing
and movement budgets are explicitly established. Do not infer unlimited
per-contingency equipment adjustment from this authorization. Keep operating
limits, generator capabilities and physical validation tolerances unchanged.
Historical evidence retains its original policy; use fresh campaign outputs.

Selected shunt optimization, when separately requested, is continuous susceptance
optimization, not discrete switching. Changes to selected equipment controls,
timing or movement budgets require an explicit user instruction.

## Bounded corrective reassessment authorized (2026-10-21)

The user subsequently explicitly authorized investigation and reasonable relaxation
of the restrictions, corrective equipment actions with timing/movement budgets,
and P2 reassessment. This supersedes the earlier deferral for this campaign.
Report the actual controls and assumptions; no repeated confirmation is needed
within this declared campaign. Keep physical limits and validation tolerances.

For the new bounded sensitivity study, retain the accepted shared reactive curves
without further widening their design bounds. Allow preventive equipment
scheduling separately for each known demand (including evaluation demands), then
freeze the resulting base dispatch/equipment for paired outage assessments.
This is a different information policy from frozen-equipment held-out design.
Immediate equipment movement is zero. Assumed settled availability is 60 s with
maximum tap-ratio movement 0.0125 times supplied ratio and one bank section, or
120 s with 0.025 times supplied ratio and two sections, both relative to the same
preventive base. Retain absolute supplied +/-5% tap sensitivity bounds and bank
legal-count envelopes. These are independent steady-state sensitivities, not
validated device delays, step sizes, trajectories or transient security.

Use existing bank metadata only. Continuous bank results need a separate legal
section recovery and validation. Actual manufacturer tap steps/timing remain
unverified; tap results remain continuous sensitivities. Public 14/39-bus
capacity exclusions remain applicable with unchanged demand, Pmax and ratings;
do not rerun impossible masters or silently remove requirements to declare P2
complete. Future campaigns should explicitly state their scope and controls.

## Exact S2 benchmark selected (2026-10-22)

The user explicitly replaced the P2 500-bus setup with the exact S2 data and
control configuration. Use artifacts/p2_s2_500/contract.json and verify its source
hashes with examples/p2_s2_500.py before any P2 large-case work. This benchmark
uses the S2 selected 131 corrective taps and 11 continuous banks without additional
movement budgets, 102 free shared droop parameters, stored Pmax proportional
response and the declared S2 emergency/relief contract. This explicit exact-match
instruction overrides the fixture's 60/120 s budgets and the library default
response policy for this benchmark only. Do not silently migrate saved S2
coupled states to limit-aware semantics. No new campaign was run by the alignment;
S2 stays paused and its accepted evidence must remain unchanged.

## S1/S2 P2 implementation authorized (2026-10-22)

The user asked to start P2 implementation for the S1/S2 14- and 500-bus systems.
The initial declared campaign uses the exact S2 response/control contracts:
14 buses at five joint demands (90/95/100/105/110%) with 3 corrective taps,
1 continuous bank and 10 shared droop parameters; 500 buses at the independent
105% zero-shedding checkpoint with the exact selections above. Both retain S2
absolute equipment bounds without additional movement budgets. The 14-bus
objective is nominal base loss; the initial 500-bus pilot is feasibility-only,
with later S2 resource/loss priorities still outstanding. The large master is
bounded to 12 states, with all 389 connected outages required for acceptance.
This is fresh P2 work; do not resume or modify the paused S2 campaign. See
`examples/p2_s2_campaign.jl` and `docs/src/p2_s2_implementation.md`.

## 500-bus multi-demand continuation authorized (2026-10-22)

The user asked to proceed with 500-bus multi-demand testing and match or exceed
S2's demand frontier. Fresh P2 continuation first tests shared 90/95/100/105%,
then adds 106.25%, 107.5% and 110% if exhaustive validation passes. Preserve exact
S2 equipment, shared droop bounds, proportional response, emergency limits and
DR policy. Try zero shedding first; distinguish any separate comparison using
S2's original 10 MW per-outage shedding allowance (used in its 106.25% witness).
The numerical master-state budget may grow for multiple demands; this changes
computational resources, not physical control freedom. Each accepted shared set
requires all 389 connected outages at every demand, with one common controller
and a fixed preventive base per demand. Original S2 evidence stays unchanged.

## Remaining P2 qualification authorized (2026-10-22)

The user asked to proceed with all remaining P2 work and attempt completion.
Use a fresh campaign, preserving exact S2 14/500 control semantics above.
Freeze accepted curves for held-out demands (14: 92.5/97.5/102.5/107.5%;
500: 92.5/97.5/102.5/105.625%). Demand-specific preventive dispatch and declared
corrective continuous equipment remain available within unchanged S2 bounds.
The 500-bus held-out lane uses S2's original relief allowance, including up to
10 MW shedding. No repeated equipment confirmation is required in this scope.
Attempt rotated repeated initialization and enumeration/scenario-addition
comparisons, ranking/filtering diagnostics, bounded resource/loss priorities,
and local regression/compatibility checks. Distinguish bounded subsets from
full-catalogue qualification, preserve failed attempts, and require independent
physical replay. Unsupported predictive filtering must fall back to exact solves.
Do not change physical limits or count numerical failure as infeasibility.

## Open-gate continuation recorded (2026-10-22)

The user continued all still-open P2 work. Exact S2 controls/response remained
unchanged; no repeated equipment confirmation was requested. See
`artifacts/p2_open_gates_20261022/REPORT.md` and `docs/src/p2_open_gates.md`.
The prepared cold workflow reconstructs from flat voltage and preventive PG/Q,
then performs a native constrained solve: 389/389 connected nominal outages
passed with common frozen curves/base and independent replay. Raw direct-flat
Ipopt remains distinct. Remote Julia 1.10/1.12 CI passed 3,177 checks each.

The optional rational capacity filter is specific to the exact S2 proportional,
fixed-preventive-dispatch contract. It proves necessary exclusions only; never
apply its signal bound to the production limit-aware model or call an excluded
outage/dispatch pair an unrecoverable network. General safe-skipping is not
qualified or enabled. All final accepted designs still need complete AC replay.

Full coupled resource optimization remains open. A native 389-outage model was
measured at 17.0 GiB footprint/17.1 GiB peak on the 16 GiB host. Address that
measured memory problem before repeating a monolithic campaign. Derivative
partitioning retains one coupled NLP; it is not optimization decomposition.
Stronger zero-resource level-set candidates and numerical normalization did not
produce accepted resource/loss witnesses. Do not promote their time limits to
physical infeasibility, change the S2 allowances, or count subset objectives as
full multi-demand priorities. Original S2 and all prior sealed P2 evidence remain
unchanged. Equipment normalization is supported in the original AC builder;
the current reduction prototype explicitly rejects normalized taps.
