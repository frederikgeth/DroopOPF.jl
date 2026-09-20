# Data model

```@meta
CurrentModule = DroopOPF
```

## Network and operating devices

`Bus`, `Branch`, `Load`, and `ACNetwork` describe the balanced AC network in
per-unit quantities. A `Generator` is attached to a network bus and carries
active/reactive limits, availability, and initial values.

```julia
network = ACNetwork(
    [Bus(1; reference = true), Bus(2)],
    [Branch(1, 1, 2; resistance = 0.01, reactance = 0.1,
            thermal_limit = 5.0)],
)
generator = Generator(
    1, 1;
    p_min = 0.0, p_max = 2.0,
    q_min = -1.0, q_max = 1.0,
    initial_p = 0.5,
)
```

## Volt-var droops

`VoltageSchedule` stores the reference voltage and deadband. `VoltVarDroop`
adds a positive voltage-per-reactive-power slope, a reactive reference inside
the deadband, and a `ReactiveCapability`.

```julia
control = VoltVarDroop(
    VoltageSchedule(1.0; v_db_low = 0.99, v_db_high = 1.01),
    0.05,
    0.0,
    ReactiveCapability(p_min = 0.0, p_max = 2.0,
                       q_min = -1.0, q_max = 1.0),
)
```

The exact curve is available through `droop_curve(control)` and evaluated with
`droop_response(control, voltage; p = active_power)`. The active-power range
on the control is enforced for its attached generator.

## Attachments

`GeneratorControlAttachment` connects one generator to one control and gives
the regulated location. M1 permits one static attachment per generator.

```julia
attachment = GeneratorControlAttachment(
    1, 1, RegulatedLocation(:bus, 1),
)
```

This explicit attachment layer leaves room for plant-level, remote-bus, and
system-level control semantics in later milestones.


## M5.1 transformer data contract

`Branch` accepts `tap_ratio=1` and `phase_shift=0`. The complex tap is on the
declared from side: `a = tap_ratio * cis(phase_shift)`. Ratio is dimensionless,
finite and strictly positive; phase is finite and in radians. Existing keyword
and typed positional constructors retain unity/zero defaults. Network/case
conversion, control attachment and contingency copies preserve both settings.

MATPOWER `TAP=0` becomes unity; `SHIFT` is converted once from degrees to radians.
No physical tap bounds or legal positions are inferred from those fields.
M6.1 imports nonzero bus `GS`/`BS` as aggregate fixed shunts (see below).

M5 introduced study schema v2 with both transformer settings required; M6.1
introduced v3 with an explicit fixed-shunt list; M6.2 writes v4 with banks. The reader migrates
line-only v1 studies to unity/zero and rejects contradictory transformer metadata
labelled v1. Unchanged result/report document kinds retain schema v1. Older
readers reject v2, rather than silently losing transformer physics.

M5.2–M5.4 support fixed ratios and fixed phase shifts in AC evaluation,
OPF, SCOPF and existing bounded droop design. Unavailable branches contribute
no current while retaining supplied settings. Tap optimization, AVR and switched
shunts belong to later milestones.

Run `julia --project=. examples/m5_1_transformer_data.jl /tmp/m51-evidence`
from the repository root to create study JSON, expected/actual numerical evidence,
a Markdown report and an SVG showing the from-side convention. The synthetic
fixture is not a measured operating point. No AC feasibility is claimed.


## Fixed transformer electrical model (M5.2–M5.4)

For series admittance `y = 1/(r + j*x)`, total branch charging `b`, and
from-side complex tap `a = tau * exp(j*phi)`, the optimizer assembles:

```text
Yff = (y + j*b/2) / |a|²       Yft = -y / conj(a)
Ytf = -y / a                  Ytt = y + j*b/2
```

It applies `|Sf| <= rating` and `|St| <= rating` separately. Both the smooth
JuMP formulation (Ipopt/MadNLP) and complementarity formulation (CCOpt) use the
same terminal-limit builder, including transformer-outage exclusion. Phase
shifts make the off-diagonal entries different; they must not be symmetrized.

Physical validation follows a separate calculation. With `Uf = Vf/a` and
`J = y*(Uf - Vt)`, it computes `If = (J + j*b/2*Uf)/conj(a)` and
`It = -J + j*b/2*Vt`, then `Sf = Vf*conj(If)` and `St = Vt*conj(It)`.
Bus balances sum these terminal powers rather than reuse optimizer Ybus.
Both terminal powers are positive **into** the branch; their sum is net branch
absorption. Charging is included once at each internal terminal, with the
from-side contribution transformed by the tap.

Hand-calculated current/power fixtures, scalar polar sweeps, individual terminal
overload tests and intentionally corrupted settings check the two implementations.
Synthetic OPF/SCOPF studies check exact droop residuals, scenario coupling,
outages, JSON replay and preservation under bounded droop optimization. These
are steady-state tests, not dynamic or global-optimality certificates.

For the complete evidence bundle, run from the repository root:

```sh
PYTHON=/path/to/python-with-matplotlib julia --project=. examples/m5_transformer_workflow.jl /tmp/m5-evidence
```

The Python environment needs Matplotlib (tested with 3.9.4); it is a plotting-only
dependency, not a Julia package dependency. The workflow writes numerical JSON,
per-solver reports, ratio/phase reference plots, both-terminal loading panels,
voltage profiles, exact-droop plots and residual plots. Failed runs remain in the
JSON/report and cause a nonzero exit. Existing line-only M1–M4 tests remain part
of the regression gate. No three-winding or separate magnetizing branch model
is introduced. M6.1 adds MATPOWER aggregate fixed GS/BS; switched-bank data are
a separate later capability.


The M5 evidence declares proportional-regime initial states rather than flat
deadband starts. The latter can stall even on a feasible study. For CCOpt, the
example requests `ProportionalRelaxationUpdate(sigma_min=1e-12)`,
`tol=acceptable_tol=1e-9` and `bound_relax_factor=0`;
its default relaxation floor left exact-droop errors above the 1e-5 acceptance
tolerance. These are example-specific solver settings, not equipment parameters
or relaxed acceptance criteria. Diagnostic failures are retained with the evidence.


## Fixed bus shunts (M6.1)

`FixedShunt` is network equipment, separate from `Load` and branch charging:

```julia
shunt = FixedShunt(8, 10; conductance=0.02, susceptance=0.1, available=true)
network = ACNetwork([Bus(10; reference=true)], Branch[]; shunts=[shunt])
```

IDs and bus references must be positive; IDs are unique within the shunt list.
Admittance is finite and in per unit on the case base. Conductance G must be
nonnegative; susceptance B may have either sign. Positive B is capacitive.
Complex terminal consumption is `S = (G - j*B)*|V|²`: positive P consumes active
power, negative Q injects reactive power. Several distinct devices may share a
bus and their contributions sum once. `available=false` contributes zero while
preserving supplied data. An empty list preserves the previous network model.

The optimizer adds `G+j*B` to the bus diagonal in Ybus. The independent evaluator
`shunt_powers(network, state)` computes `V*conj((G+j*B)*V)` per device in
`network.shunts` order. `power_balance` sums these powers alongside branch terminal
powers. Bus shunts do not enter `branch_flows` or duplicate line charging.

MATPOWER GS is MW consumed at unit voltage; BS is MVAr injected at unit voltage.
Import divides both by baseMVA, with no sign reversal: `G=GS/baseMVA`,
`B=BS/baseMVA`. Nonzero aggregate rows become one fixed record using the bus ID
as shunt ID; zero rows add none. No bank identity, legal step, nominal schedule
or automatic controller is inferred. Negative GS is rejected because this passive
equipment model does not represent active-power injection.

Study JSON v3 requires `network.shunts`; each record includes ID, bus ID, G, B
and availability. Readers retain v1/v2 support with empty shunts and reject
nonempty shunts misleadingly labelled with an older schema. New writers use v4
even when the list is empty, so old readers fail explicitly. Other document kinds
keep their existing versions. Numeric promotion, case/control copies and existing
branch/generator contingency overlays preserve fixed shunts. Dedicated shunt
contingencies are not introduced in M6.1.

Run the evidence workflow with Python/Matplotlib available:

```sh
PYTHON=/path/to/python-with-matplotlib julia --project=. examples/m6_1_fixed_shunts.jl /tmp/m61-evidence
```

It generates a GS/BS conversion table, expected/computed P(V) and Q(V) curves,
availability and round-trip checks, and deliberate omission/double-count/sign
errors. A one-bus OPF checks safe use of the shared Ybus path. Switched-bank
states (M6.2) and the complete OPF/SCOPF comparison bundle (M6.3) are implemented; see [M6 evidence](https://github.com/frederikgeth/DroopOPF.jl/blob/transformers/artifacts/m6/report.md).

## Supplied switched-bank states (M6.2–M6.3)

```julia
bank = ShuntBank(201, 30;
    step_susceptances=(0.02, -0.01),
    step_conductances=(0.001, 0.0005),
    legal_states=((0,0), (1,0), (2,0), (0,1), (1,1)),
    state=(1,0), nominal_state=(1,0))
changed = with_bank_state(bank, (2,0))
network = ACNetwork(buses, branches; shunts=fixed_shunts, banks=[changed])
```
Each state is a tuple of nonnegative integer counts for the corresponding step
admittances. Legal combinations must be explicitly supplied, nonempty and unique;
both current and nominal states must be legal even when the bank is unavailable.
Metadata are copied into immutable tuples. Unavailability produces zero admittance
without erasing the installed state. `bank_admittance` returns aggregate G+jB;
`bank_powers` independently computes consumption P+jQ by summing step currents.
Positive B is capacitive, so Q is negative consumption. Fixed shunts and banks
share a unique ID namespace. Do not represent the same physical aggregate in both.
MATPOWER GS/BS remains fixed admittance and does not infer bank identities or states.

Study schema v4 requires `network.banks` and preserves all metadata. Readers
migrate v1-v3 to empty banks and reject nonempty banks mislabeled as old schemas.
Existing branch/generator contingencies preserve supplied bank states. M6 uses
fixed states in OPF, preventive/corrective SCOPF and droop design. Optimization
of equipment is M7; a bank state is not an automatic switching policy or trajectory.

## Continuous transformer tap design (M7.1)

```julia
policy = [TapControl(11; lower=0.95, upper=1.05, nominal=1.0)]
result = optimize_taps(case, policy; initial_state=state, smooth_epsilon=1e-5)
report = validate_tap_design(case, result)
physical_case = with_tap_settings(case, result.taps)
metrics = tap_design_metrics(case, result)
write_tap_design("tap-design.json", result)
reloaded = read_tap_design("tap-design.json")
```

Bounds are required; no range is inferred from imported taps. Branch IDs must be
unique, known and available. Omitted branches remain at their supplied ratios.
Set `lower == upper` to fix a selected device, and supply `initial` if the supplied
ratio is outside the bounds. Initial values are numerical starts; `nominal` is a
positive reference for reporting, defaulting to the supplied ratio, and need not
lie in the optimization envelope. Neither introduces a penalty in the objective.

The baseline objective remains generator dispatch deviation. Phase shifts, shunts
and droop curves stay fixed. Ratios enter nonlinear balances and both-terminal
thermal constraints; input case data remain unchanged. Results are continuous
relaxations, without discrete-position recovery or switching-count interpretation.
`report.physical` evaluates the reconstructed physical network; `policy_valid`
separately checks bounds and fixed settings. A failed solve can have no state or
ratios; physical validation is then unavailable and overall validity is false.

The public entry point accepts a base `Case`; a `Study` is rejected until M9 adds
scenario policy coupling. The current implementation uses the smooth encoding
with Ipopt by default and supports the existing optimizer-factory interface.
See [M7.1 evidence](equipment_optimization.md) for sweeps and comparisons.

## Simple continuous shunt design (M7.2)

```julia
bank = ShuntBank(201, 30; step_susceptances=(0.02,),
    step_conductances=(0.001,), legal_states=((0,), (1,), (2,), (3,)), state=(1,))
# After adding bank to case.network.banks:
policy = [ShuntControl(201)] # B bounds default to [0, 0.06] pu
result = optimize_shunts(case, policy; initial_state=state)
report = validate_shunt_design(case, result)
metrics = shunt_design_metrics(case, result)
physical_case = with_shunt_settings(case, result.susceptances)
write_shunt_design("shunt-design.json", result)
reloaded = read_shunt_design("shunt-design.json")
```

A reactor uses negative step B, e.g. −0.02 gives an interval [−0.06, 0]. G is tied
to B through their common fractional count; here G=0.001(B/Bstep). Banks with
multiple step types or zero step B are rejected when selected, as are unavailable
or unknown banks and fixed-shunt IDs. Unselected heterogeneous banks remain fixed.

Optional `lower`, `upper`, `initial` and `nominal` are all B in pu. Bounds must
lie in the legal-count envelope; equal bounds fix B. The default initial B is the
supplied bank setting, so narrowing bounds past it requires an explicit start.
The default nominal B comes from the bank's nominal state. Nominal B must lie in
the physical envelope but may lie outside a narrower optimization interval.

Taps, phase shifts and droop settings stay fixed; multiple simple banks can be
selected independently. The baseline dispatch objective remains unchanged.
Metrics include fractional count, B deviations, G, active consumption, reactive
injection and branch losses. The result is explicitly continuous, not a recovered
switching position. `with_shunt_settings` creates an evaluation case by replacing
selected banks with equivalent fixed shunts; the original case retains bank metadata.
Policy bounds are checked separately by `validate_shunt_design`. JSON stores
settings and policy; retain the input study alongside it for reproducible replay.

[Validation evidence](equipment_optimization.md) includes capacitor/reactor
sweeps and plots. Heterogeneous optimization is post-scaling backlog; the gate
requires evidence that simple banks, transformers and droops scale adequately first.

## Joint equipment and droop design (M7.3)

```julia
result = optimize_joint_design(case;
    tap_controls=[TapControl(11; lower=0.95, upper=1.05)],
    shunt_controls=[ShuntControl(201)],
    droop_controls=[DroopControl(2; slope_bounds=(0.04, 0.10))],
    initial_state=state)
report = validate_joint_design(case, result)
physical_case = with_joint_settings(case, result)
metrics = joint_design_metrics(case, result)
write_joint_design("joint-design.json", result)
reloaded = read_joint_design("joint-design.json")
```

Omit a control list to keep that family fixed; select devices independently within
each list. `DroopControl` additionally accepts `v_ref_bounds`,
`deadband_low_bounds`, `deadband_high_bounds` and `initial::DroopSettings`. Missing
bounds fix a parameter to its supplied value. Bounds preserve the M3 positive-slope,
positive-reference and positive-total-deadband contract. No free-knot curve family
is introduced. Multiple attached available droop controls may be selected.

The objective is identical across fixed/free configurations. Reports distinguish
solver success, parameter/equipment policy compliance and reconstructed physical
validity. Ratios and bank settings remain continuous relaxations. See
[M7 results and visualizations](equipment_optimization.md) for the complete grid,
multi-start variability, objective components and matched conditional benefits.
