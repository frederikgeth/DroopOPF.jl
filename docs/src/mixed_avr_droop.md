# Mixed AVR and volt–var droop studies

`Generator(...; s_rated=S)` declares a positive apparent-power rating in per-unit
on the **case system MVA base**. Omission (`nothing`) preserves the historical
rectangular capability. An explicit rating adds `P²+Q² ≤ S²` in each optimized
AC state; it never replaces P/Q bounds. The setting survives Case conversion,
contingencies, retained islands and study JSON (rated studies use schema 11).
PSS/E MBASE is not automatically interpreted as a verified nameplate rating.
For capability-clipped droop and individual AVR controls with Q intervals spanning
zero, the clipped response plus `|P|≤S` already enforces the circle algebraically.
The builder omits a duplicate circle row in those cases to avoid a dependent
saturation Jacobian. Other units retain explicit circle inequalities. Independent
replay checks the circle for every rated unit regardless of numerical encoding.

`reactive_limits(g,p)` returns the intersection of the supplied Q interval and
`[-sqrt(S²-p²), sqrt(S²-p²)]`. AVR releases voltage regulation at these effective
limits. A volt–var curve retains its designed reference, slope and deadband,
but its delivered response clips to the effective capability. Several AVR units
regulating the same location share the same normalized position in their
currently available reactive intervals. Their target must be consistent.

This is a steady-state control and capability model. The labels AVR and droop
do not instantiate synchronous-machine dynamics, a grid-following PLL, a
grid-forming controller, current priority or renewable availability. Detailed
inverter capabilities remain P3 work. The circle is an apparent-power limit;
it does not impose the voltage-dependent current envelope of a real converter.

## Deterministic allocation

`mixed_reactive_controls(case; avr_fraction=.30, ratings, voltage_targets)` ranks
online, positive-Pmax units by descending Pmax and ascending ID. The AVR count
rounds to nearest integer, half upward. Remaining online units retain their
supplied attached volt–var curves. Offline records stay offline. The caller must
provide ratings for every eligible unit and targets for exactly the selected AVR
units. No device rating is inferred by this helper.

Explicit mixed assignments can be combined with smooth free droop design in
`optimize_joint_design`, `optimize_droop_parameters` and
`optimize_multi_period`. Stable control IDs refer to legacy attachments; a
selected free curve must match the explicit assignment for that generator.
Exact complementarity supports fixed mixed curves and P-dependent saturation;
free mixed-curve design currently uses the smooth formulation. The frozen feasibility certificate gate (including rational LP and global graph
escalation) explicitly rejects rated cases until its P-dependent graph is extended.
This avoids applying an obsolete voltage-only droop hull to clipped capability.
Ordinary AC/SCOPF native solves and their physical replay support the ratings.
The optional legacy voltage-only droop predictor also returns an unsupported
guard for rated cases and routes them to exact assessment.

## Multi-period security

`optimize_multi_period_security(studies; duration_hours, ramp_limits,
angle_limits, droop_controls, ...)` couples preventive active dispatch by supplied
pu/hour ramp rates and uses one shared designed curve per selected controller.
Each period has its own base and declared outage states. Equipment follows the
Study selections, bounds, timing and movement budgets. Unselected equipment stays
fixed. No initial/terminal dispatch, outage trajectories, storage or commitment
are inferred. Normal base bounds and full demand always apply.

- `response=:limit_aware` uses the production saturating participation model.
- `response=:s2_proportional` explicitly uses the saved S2 proportional equality.
  It does not silently turn into a saturated response.
- `s2_emergency=true` selects the specific S2 comparison policy: outage voltage
  bounds extended by 0.05 pu, branch MVA limits multiplied by 1.1, DR up to 1%
  of each positive load, shedding up to 10 MW per outage, combined relief up to
  10% per load, and proportional reactive relief. These are declared assumptions,
  not universal security defaults or transient guarantees.
- Emergency solves sequentially minimize total shedding, total DR, then
  duration-weighted base loss energy. Earlier optima are retained within
  `1e-8` system-base pu in the aggregate objective. These remain local NLP stages.
- AVR targets are fixed by default. Optional `avr_bounds=Dict(id=>(lo,hi))`
  schedules a preventive target per period, shared across its contingencies;
  `avr_movement_per_hour` bounds changes between period starts. This parameter
  is an explicit study assumption, not a manufacturer ramp specification.
  Units at one regulated location share one exact target, using intersected bounds.
  An unscheduled AVR at that location holds the common target fixed.
- Fixed-base evaluation freezes the common curves, states and equipment, then
  solves listed outage recourse with a feasibility objective; it does not minimize
  the relief of each accepted response. It is a security assessment of a candidate,
  not a replacement for jointly optimizing all required constraints.

Accept only native success **and** `validate_multi_period_security(studies,r).valid`.
Replay independently reconstructs equipment, load relief, original-network
currents, exact controls, apparent limits, response, angles, temporal ramps and
loss energy. `write_multi_period_security` / `read_multi_period_security` preserve
results. For external audit, retain the input Study files and campaign contract
as well: a result's stored temporal policy is not an independent specification.

## 500-bus campaign

The driver is `examples/p2_mixed_avr_500.jl`. It writes a fresh campaign and does
not resume the paused S2 work. The reference has 90 records: 51 online positive
Pmax units, hence 15 AVR and 36 droop units; 39 offline records remain offline.

The exploratory ratings are explicitly assumed `S=Pmax/0.95`, not verified source
ratings. Fixed AVR targets use nominal S2 saved generator-bus voltages. Droop
bounds retain the calibrated 2–8% full-Q-span slopes, reference ±0.02 pu and fixed
zero deadband. The equipment policy retains 131 corrective taps and 11 continuous
banks with S2 absolute bounds and no extra movement cap. Settled corrective
availability is assumed; device delays and discrete bank recovery are unqualified.

The temporal profile is five one-hour periods at 90/100/105/100/90% demand, scaling
both P and Q at every load. Preventive ramps are assumed at 25% of each generator's
active capability range per hour. A separate AVR scheduling sensitivity permits
±0.02 pu around the fixed target within normal bus bounds, with ≤0.01 pu/hour
movement. The connected 389-outage catalogue and structural island exclusions
are reported separately. Security cannot be inferred from a valid base trajectory.

See the campaign report for actual executed stages, accepted results, failed
attempts and outstanding qualification. Numerical failure is not an infeasibility
proof. Neither this extension nor its base-operation results close P2.

The repository campaign ledger, `artifacts/p2_mixed_avr_500_20261022/REPORT.md`, distinguishes
native AC passes, necessary fixed-dispatch exclusions and numerical leftovers.
The 14-bus 125-state normal-limit mixed study passes. The 500-bus accepted base
profile is not a qualified security-constrained preventive design. The fixed-curve
five-period reference is assembled from native independently optimized periods
with verified ramps; its bounded coupled-optimizer retries did not qualify.

## Reserve-aware preventive dispatch

Loss-only base dispatch can leave participating generators at Pmax. The optional
`objective_policy=:reserve_loss` inserts a reserve stage after shedding/DR and
before loss. For each participating online unit with effective active interval
`[lo, hi]`, it imposes `Pg + (hi-lo)*h <= hi` and maximizes the common `h` across
all periods. The loss stage retains that locally achieved reserve level.
`objective_policy=:reserve` stops after the reserve stage; `:loss` retains the
existing default. This normalized headroom preference is not a generator cost
curve, an explicit reserve-delivery guarantee, or an outage-security certificate.

```julia
result = optimize_multi_period_security(studies;
    droop_controls=controls,
    objective_policy=:reserve,
    avr_bounds=avr_bounds,
    avr_movement_per_hour=0.01,
    response=:s2_proportional,
    s2_emergency=true)
```

Reserve stages and their attained values survive JSON round trips. The Julia
validator and the independent campaign audit recompute headroom from the physical
base states and reject loss polishing that violates the retained reserve level.
Numerically zero nonnegative shedding/DR optima are fixed at zero before later
stages to avoid a nearly dependent aggregate constraint; failed stricter solves
remain failures, not accepted approximations.

Frozen-base assessment may encode different supplied AVR targets in each period,
provided every other reactive-assignment field matches. These are fixed inputs
to outage evaluation, not new corrective AVR degrees of freedom. Qualify the
parent preventive schedule against its bounds and hourly movement limit, then
verify that every outage scan uses the same parent targets, curves and base
states. Frozen scans do not independently optimize or qualify a new schedule.

The fresh continuation driver is `examples/p2_mixed_avr_reserve.jl`; its evidence
ledger is `artifacts/p2_mixed_avr_reserve_20261023/REPORT.md`. Bounded joint masters
are followed by exhaustive frozen-candidate AC assessment. All 389 connected
outages must pass all five periods for full qualification; subset resource
objectives do not establish full-catalogue resource optimality.

An optional `reserve_generator_outages=[...]` dispatch target requires each
surviving participant to have room for its share of the named lost generator's
entire base output plus `reserve_margin_pu` (default zero), using the declared
surviving participation weights and movement caps. It uses effective active
bounds and leaves the equipment, circle, voltage and thermal bounds unchanged.
This stricter target assumes no relief for active replacement and does not cover
changes in network losses; it is not a replacement for an AC outage solve.
The campaign contract records this option, and the independent Python audit
checks it separately from physics. Result-only replay cannot recover additional
input policies that were not retained with the campaign contract.

`objective_policy=:feasibility` is available for a separate constrained witness
without resource or loss optimization. A feasible shared design is not a
resource-optimal design. Keep feasibility, reserve and loss-polishing attempts
in separate evidence folders and report which objective actually converged.

For a joint master with corrective equipment, `initial_equipment[t]` may include
`scenarios=Dict(:base => (taps=..., shunts=...), :outage => (...))`.
Each scenario uses its own coherent equipment starting values; omitted scenarios
fall back to the period entry. Unknown scenario keys are rejected. This option
changes numerical initialization only; it does not add corrective controls or
relax movement budgets, absolute bounds, or preventive sharing constraints.

A complete cross-attempt primal warm start can also supply one dictionary per
period through `initial_avr_targets`, `initial_relief` and
`initial_balancing_power`. Relief entries are `(dr=..., shed=...)` vectors over
the original loads, keyed by outage ID; AVR targets are keyed by scheduled
generator ID. Unknown IDs, nonfinite data and inconsistent targets at a shared
regulated location are rejected. Individual starts are clipped to variable
bounds; all original physical and temporal constraints are still enforced.
The initial state does not become a valid operating point merely because it
was retained across attempts. Inspect all constraint residuals, including AVR
and capability relations, as well as power balance.

## P2 policy rerun

The current P2 mixed-control rerun uses `examples/p2_mixed_limit_aware.jl`.
It explicitly selects `response=:limit_aware` and `s2_emergency=false`, default
capability-range participation, original voltage/thermal bounds, and full load
without DR/shedding. The effective-range weights equal the former Pmax weights
for this particular zero-Pmin data set; saturation redistribution changes the law.

The selected 131 taps retain their absolute supplied +/-5% envelope and may move
at most 0.025 of supplied ratio from each period's preventive base. The 11 banks
remain continuous within their legal susceptance envelopes, with a two-section
movement budget. Each has one section, so its absolute range is the tighter bound.
This is an assumed 120-second settled sensitivity; it does not qualify immediate
zero-movement security, manufacturer delays or discrete switching. The mixed
15 AVR/36 droop split, assumed apparent circles, five-hour profile and latest
shared curve/AVR scheduling bounds remain in force.

The additional proportional-share reserve guard and S2-specific rational capacity
filter are not applied. Historical exact-S2 drivers and sealed results retain
that historical policy. Fresh results are written to
`artifacts/p2_mixed_limit_aware_20261023`; the original S2 study stays paused.

The completed scan passes 386/389 connected outages across all five periods,
including all 51 generator outages. Lines 21 and 36 and transformer 562 remain
numerically unresolved. The base candidate retains 21.580884% minimum upward
headroom and no generator reaches Pmax in any base period; five-hour base loss
energy is 178.13534899 MWh. Its AVR schedule passes bounds and movement checks,
but full security qualification remains open. See the
[P2 policy report](research.md).


### Targeted P2 recovery under original limits (2026-10-23)

The [targeted recovery](research.md) found a common five-period design for
line 21, line 36 and transformer 562 with no rating, voltage, capability or
equipment-budget relaxation. Preventive dispatch, shared droop and the AVR
schedule were reoptimized with a feasibility objective. The prior reserve-aware
solution supplied initialization; its minimum individual headroom was not
retained as a constraint. The selected design has 2.811439% minimum individual
headroom and 1083.766 MW aggregate peak Pmax-minus-Pg headroom.
The report records the subsequent exhaustive frozen-design validation separately
from rejected exploratory solves. This does not establish loss/resource
optimality, discrete switching feasibility or transient security.

Final frozen-design validation: **389/389 connected outages accepted across all
five periods**, with independent Python audit, unchanged-policy identity and
current-source Julia replay of all 390 selected result files. The five-period
connected steady-state AVR schedule is qualified within this declared scope.
