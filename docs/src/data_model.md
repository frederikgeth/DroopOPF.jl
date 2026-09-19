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
states (M6.2) and the complete OPF/SCOPF comparison bundle (M6.3) are implemented; see [M6 evidence](../../artifacts/m6/report.md).

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
