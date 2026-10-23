# P3 multi-period droop design

The initial multi-period capability solves one deterministic sequence of AC
operating periods in a single sparse nonlinear model. A single set of reactive
voltage-droop parameters is shared across all periods. Each period has its own
active/reactive dispatch and voltage state. Equipment stays at the supplied
fixed settings throughout the horizon.

This is an initial implementation of P3-04. P2 remains open, and the original
S2 campaign remains paused. Multi-period outage recourse, storage, commitment,
equipment scheduling and dynamic trajectories are separate extensions.

## Time and objective contract

Cases must share the same ordered network, equipment settings, generators,
controls, attachments, power base, frequency and load identities. Only load
powers may vary. All original voltage, thermal and generator limits remain
active, with optional explicit branch-angle bounds.

For period `t`, `duration_hours[t]` is both its energy weight and the elapsed
start-to-start time to period `t+1`. The last duration weights energy only.
There is no initial or terminal ramp boundary, cyclic closure or interpolated
trajectory. Inputs represent period operating points with a piecewise-constant
energy accounting convention.

The objective is the sum of `duration_hours[t] * base_power * (sum(pg[t]) -
sum(load_p[t]))`, in MWh. This is active network energy loss, including shunt
conductance losses. It is not generation cost or a storage energy balance.

For generator `g`, `ramp_limits[g] = (up, down)` specifies nonnegative rates in
pu/hour on the case power base. Between consecutive period starts:

```math
-r_g^{down}\Delta t \le P_{g,t+1}-P_{g,t} \le r_g^{up}\Delta t.
```

Omitted generators have no inter-period ramp restriction. Zero rates freeze
active output across periods. These planned dispatch ramps do not replace the
library's automatic contingency-response policy and do not establish dynamic
frequency performance.

## API

```julia
study = MultiPeriodStudy(period_cases;
    duration_hours=[1., 1., 2.],
    ramp_limits=Dict(generator_id => (0.2, 0.1)),
    angle_limits=Dict(branch_id => (-0.5, 0.5)))
result = optimize_multi_period(study;
    droop_controls=[DroopControl(1;
        slope_bounds=(0.02, 0.08), v_ref_bounds=(0.98, 1.02))],
    initial_states=period_initial_states)
audit = validate_multi_period(study, result)
```

Slope bounds are in physical pu-voltage / pu-reactive-power units, not percent.
Omitted droop fields remain fixed. Empty `droop_controls` fixes all curves.
The first implementation uses the existing smooth volt-var family; the normal
independent validator also checks exact PWL droop residuals. Native convergence,
all AC states, design bounds, ramp constraints, branch-angle constraints, period
losses and the total energy objective must pass independently. Solver-reported
local optima do not establish global optimality or design uniqueness.

## Initial network campaign

Run into a fresh output directory:

```sh
OPENBLAS_NUM_THREADS=1 julia --project=. examples/p3_multi_period.jl /fresh/output
python3 -B examples/audit_p3_multi_period.py /fresh/output
python3 examples/plot_p3_multi_period.py /fresh/output
```

The plotting command requires Matplotlib and NumPy. The Python audit replays
complex-current AC physics separately from the Julia optimization implementation.
Inputs, warm starts, policies, source hashes, native statuses and every state are
saved by the example. It compares supplied fixed curves and shared designed
curves under identical profiles and equipment settings.

The 22 October 2026 campaign uses five one-hour periods:

| Network | Ordered demand factors | Fixed curves, MWh | Shared design, MWh | Loss reduction |
|---|---|---:|---:|---:|
| Synthetic 3-bus | 90, 110, 95, 100, 90% | 2.74757 | 2.70002 | 1.73% |
| ARPA-E S1 14-bus | 90, 100, 110, 100, 90% | 3.31966 | 2.84483 | 14.30% |
| ARPA-E S1 500-bus | 90, 100, 105, 100, 90% | 158.09748 | 83.11411 | 47.43% |

All six solves terminated `LOCALLY_SOLVED`; Julia validation and independent
Python replay accepted all 30 period states. These are finite sampled profiles,
not continuous demand-range or N−1 qualification. No emergency limits, demand
response or shedding are used. Network data retain S1's Pmin=0 and symmetric-Q
study assumptions.

All taps and banks remain fixed at the S1 supplied reference settings. Banks
retain continuous reference susceptance values; no discrete switching claim is
made. Generator ramps are assumed at 25% of active capability range per hour;
the synthetic generator 7 instead has zero movement to exercise coupling.
They are sensitivity assumptions, not verified manufacturer ramp data.
Droop slopes/references are shared across all five periods: the public cases
use 2–8% voltage span across the full reactive capability and reference ±0.02 pu;
the synthetic case uses 0.5–2 times supplied slopes and reference ±0.02 pu.
Deadband widths remain supplied and fixed.

Detailed evidence and three figures are retained in
`artifacts/p3_multi_period_20261022_v2/REPORT.md`. The large percentage reduction
is relative to the supplied fixed curves under the same ramp constraints; it
is not a comparison with independently retuned hourly curves or a global bound.

## Mixed AVR and contingency recourse extension

The base-operation API above retains its fixed-equipment scope. The separate
`optimize_multi_period_security` API supports mixed AVR/droop controls, apparent
capability circles, outage recourse, explicit Study equipment policies and optional
preventive AVR scheduling. See [Mixed AVR and droop studies](mixed_avr_droop.md)
for the model contract, declared S2 comparison settings and qualification limits.
