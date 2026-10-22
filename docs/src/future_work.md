# Future work

This is the canonical register for capabilities deliberately deferred beyond
the implemented steady-state scope. Historical milestone and reliability
reports retain their contemporary findings, but new forward-looking work should
be recorded here instead of creating another future-work file.

## Beyond the completed S1 study

The [S1 closeout](s1_closeout.md) covers the declared 14/500-bus study. Future work includes original-Q-limit frozen-equipment compatibility, shared controller design across multiple demands, unseen operating points, and broader source-case coverage. These tasks do not retroactively change the saved acceptance scores.

## Dynamic security

Dynamic security is future work. The current immediate and settled M9.3 stages
are independently solved steady-state equilibria; they do not represent elapsed
time or a trajectory. A dynamic-security milestone needs an explicit model and
validation contract for:

- machine rotor-angle and speed states, inertia, damping, governors, exciters,
  power-system stabilizers, and relevant protection;
- fault and switching timelines, frequency nadir, RoCoF, transient-angle
  stability, voltage recovery, and post-event control timing;
- dynamic-data provenance, initialization from a validated AC equilibrium, and
  comparison with an established time-domain simulator;
- acceptance tolerances, event-specific failure classifications, and retained
  reproducible trajectories.

No steady-state result should be labelled dynamically secure until that work is
implemented and independently validated.

## Islanding beyond retained-component balancing

The implemented M10 island-aware path deliberately balances one component. It
retains the component containing the original reference bus unless that
component is strictly smaller than another component; then it selects the
largest component and assigns its largest-`p_max` available generator bus as
the new reference. It reports all discarded buses, load, and generation
capacity.

Future extensions may balance multiple viable islands, model intentional load
shedding and black-start/reference selection, distinguish energized from dead
islands, and study restoration or reconnection. Until then, discarded islands
are unassessed—not feasible, served, or safe.

## Current automatic-response qualification

As of 21 October 2026, the intended preventive policy is limit-aware participation
with capability-range fallback weights, saturation and redistribution. The
[staged preventive comparison](p2_preventive_controls.md) adds shared droop design
and shared preventive equipment settings after the fixed baseline. Curves and
equipment freeze for held-out evaluation, with zero post-outage movement. The
fixture passes; rational capacity cuts exclude the public training requirements.
Prior fixed-participation P2 outcomes remain historical. Fresh response-model,
filtering, public-network and performance qualification is required; P2 and the
stable research release remain open. See [SCOPF policy](scopf.md).

## Filtering qualification and scale

M10 now has a coverage-checked assessment pipeline around conservative routing:
structural island detection, exact evaluation of generator outages, a
base-voltage guard, and DC LODF prediction for connected line and transformer
outages. Aggregate Q-reserve and impedance/apparent-flow escalation guards
now supplement those routes; they are heuristics, not an AC security certificate.
Numerical uncertainty falls back to exact AC evaluation. Deterministic audit
IDs can force selected screened cases through exact AC assessment, and audit
failures invalidate pipeline completion. Small-network tests verify every
route, separate and combined rankings, persistence, exact-baseline mode, and
screened-case auditing. Loaded two-bus thermal/voltage/reactive/transformer
fixtures now compare filtering with exhaustive AC results by device family,
including an unsafe-policy control that disables the voltage guard. Loaded
five-bus tests check discarded demand and reference reassignment. Generic
campaign checkpoints bind inputs, policy, code and environment and revalidate
saved states on resume; interrupted, corrupted and mismatched runs are tested.

The shared-droop scenario-addition reference now requires an exhaustive final
audit; see [Droop security design](droop_security.md). Qualification under actual
droop response found held-out false screens with the frozen guards, so stronger
local reactive/control sensitivities require new discovery and held-out evidence.
The [P2-02 opt-in response guard](p2_02_droop_guard.md) caught all twelve saved false screens and completed a frozen 24-input fresh comparison: zero new misses versus seven legacy misses, with 13.75% measured runtime savings. Its default remains disabled; general and large-network qualification remain open.

The [frozen scale comparison](p2_02_scale_guard.md) assessed 20/24 new 12/24/48-bus inputs: zero guarded misses versus 186 legacy misses across 690 assessed outages, but no net measured speedup (0.05% slower). Four high-reactive anchors remained invalid after retries. Subsequent profiling qualified the existing sparse implementation on fresh 20/28-bus and 48/96-bus cases; new numerical designs still need fresh held-out cases.

## P2 completion attempt

The [P2 completion ledger](p2_completion.md) records the 2026-10-19 twelve-step
attempt. Bounded threaded model preparation and deterministic checkpointing are
implemented and tested; native solves remain serialized. Public-network guard,
ranking, warm-start and scenario-addition outcomes are reported separately from
implementation status. The latest synthetic study covers 552 outages with zero
guard misses and an 86.34% sparse exhaustive runtime reduction within that scope.

Remaining qualification includes rejected anchors, numerical uncertainty,
public ranking/screening and the [S2-aligned 500-bus benchmark](p2_s2_500.md).
Its data and configuration are verified; [initial S1/S2 implementation](p2_s2_implementation.md) passes its declared initial scopes, with broader qualification still open. ExaModels
and distributed decomposition remain conditional. S2's paused optimisation is
not resumed by the data alignment.

The [recovery follow-up](p2_resolution.md) retains finite synthetic guard evidence
and public diagnostics; removed benchmark totals must not be reused.

## Equipment and optimization extensions

Deferred equipment scope includes discrete transformer taps, switched-shunt
integer selection, complex bank configurations, richer transformer AVR, and
explicit switching sequences. Other longer-term work includes multi-period
operation, storage and unit commitment, additional data adapters, distributed
decomposition, and global-optimality or infeasibility certificates.

## Open qualification gates

The declared S1 study is closed. Broader source-case and security reliability remains future work.

## Multi-demand S2 controller design

The [frozen nominal-controller study](s2_14bus_followup.md) passes 100/105/110%
but does not qualify 90/95% demand. The subsequent [shared multi-demand design](s2_14bus_multidemand.md)
qualifies all five training and four held-out demands on all three frozen-controller
backends. The initial [solver-design follow-up](s2_14bus_solver_designs.md) obtains the accepted free MadNLP design. The subsequent [CCOpt recovery](s2_14bus_ccopt_recovery.md) converges with scheduled relaxation and passes all four held-out points. The [declared 14-bus review](s2_14bus_review.md) is closed; earlier time limits remain recorded separately. Qualification
between sampled demands and the 500-bus S2 scale-up remain future work.
The line 7–8 event is covered only under the explicit
G5-trip and unloaded-bus8-disconnection assumption; protection and dynamic
validation remain separate work.

<!-- S2_MULTIDEMAND -->
## Shared multi-demand design follow-up

**1 accepted shared design; 27/27 frozen solver–demand combinations accepted.** The new campaign shares one controller across five demand training points and 24 connected outages, with four additional held-out demands and corrective equipment within the confirmed bounds. See the [multi-demand report](s2_14bus_multidemand.md). Historical scores and S1 closure are unchanged.
<!-- /S2_MULTIDEMAND -->

<!-- S2_SOLVER_DESIGNS -->
## Independent MadNLP and CCOpt shared-design follow-up

Accepted free multi-demand designs: **ipopt, madnlp**. The new backends optimize their own shared slopes/references from the accepted Ipopt full witness; accepted designs are independently replayed and compared with Ipopt. See the [solver design comparison](s2_14bus_solver_designs.md). Original campaign scores, rejected attempts and S1 closure remain unchanged.
<!-- /S2_SOLVER_DESIGNS -->





<!-- S2_CCOPT_RECOVERY -->
## Targeted CCOpt convergence recovery

**CCOpt recovered an accepted free multi-demand design.** The recovery starts from the accepted MadNLP full primal witness and tests proportional/scheduled relaxation without changing the physical contract. See the [CCOpt recovery report](s2_14bus_ccopt_recovery.md) for diagnostics, updated curves and held-out outcomes. Historical attempts and S1 closure remain unchanged.
<!-- /S2_CCOPT_RECOVERY -->

<!-- S2_14BUS_REVIEW -->
## 14-bus S2 review decision

The declared sampled 14-bus scope is closed. See the [14-bus review](s2_14bus_review.md). Broader S2 remains open; S1 remains closed.
<!-- /S2_14BUS_REVIEW -->

The [response diagnosis](p2_02_response_diagnosis.md) reproduced nonlinear stopping causes, identified local Q-capability conflicts at the rejected anchors and attributed the 24-bus timing gap to exact-path variation. A conservative convergence prototype had zero misses on a new four-case/128-outage comparison, but no extra screening and 2.8% slower runtime than the reference. It is retained as an experiment; production is unchanged.


The [bounded corrective reassessment](p2_corrective_reassessment.md) adds
known-demand preventive scheduling and explicitly budgeted 60/120 s equipment
sensitivity equilibria. All 27 fixture demand/stage pairs pass continuous and
legal-bank recovery, with 432 independently replayed states. Immediate equipment
remains frozen and passes. Timing and continuous taps need real device data;
public capacity exclusions and general P2 qualification remain open.
