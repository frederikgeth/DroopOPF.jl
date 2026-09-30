# Future work

This is the canonical register for capabilities deliberately deferred beyond
the implemented steady-state scope. Historical milestone and reliability
reports retain their contemporary findings, but new forward-looking work should
be recorded here instead of creating another future-work file.

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

## Filtering qualification and scale

M10 now has a coverage-checked assessment pipeline around conservative routing:
structural island detection, exact evaluation of generator outages, a
base-voltage guard, and DC LODF prediction for connected branch outages.
Numerical uncertainty falls back to exact AC evaluation. Deterministic audit
IDs can force selected screened cases through exact AC assessment, and audit
failures invalidate pipeline completion. Small-network tests verify every
route, separate and combined rankings, persistence, exact-baseline mode, and
screened-case auditing.

Before an operational deployment, thresholds must be frozen on training data
and evaluated on separate networks and operating points, with unresolved-case
recall, false-screen counts, runtime, and fallback rates reported. Useful later
extensions include AC sensitivities, voltage/reactive-risk features, monitored
element subsets, explicit line/transformer classification, generator-outage
screening features, remedial-action screening, constraint generation, process
parallelism, and auditable threshold/version persistence. IEEE-118 and
IEEE-300 belong only to those reliability and robustness campaigns, never the
unit suite.

## Equipment and optimization extensions

Deferred equipment scope includes discrete transformer taps, switched-shunt
integer selection, complex bank configurations, richer transformer AVR, and
explicit switching sequences. Other longer-term work includes multi-period
operation, storage and unit commitment, additional data adapters, distributed
decomposition, and global-optimality or infeasibility certificates.

## Open qualification gates

The S1 solver/start reliability gate remains open under its frozen acceptance
contract. S2 has an initial bounded public scorecard, while broader
equipment-aware SCOPF qualification and response-time evidence remain active.
Those evidence records belong in their existing S1/S2 reports; this page tracks
the outstanding capability categories without duplicating their scorecards.
