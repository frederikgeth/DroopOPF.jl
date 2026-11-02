# Notation, signs and units

Symbols are defined locally in teaching pages. This reference brings them together
and maps the mathematical quantities to the API. Older technical pages sometimes
use another spelling; those aliases are listed explicitly below.

## Devices, conditions and states

| Symbol | Meaning |
|---|---|
| ``b``; ``\mathcal B`` | Bus index; set of buses. |
| ``g``; ``\mathcal G``; ``\mathcal G_b`` | Generator index; set of generators; generators connected to bus ``b``. |
| ``\ell``; ``f,t`` | Branch index; its declared from and to buses. In branch equations ``t`` is an endpoint, not a time index. |
| ``j``; ``\mathcal J`` | Controller index; controller set. In complex-number expressions, the roman symbol ``\mathrm j=\sqrt{-1}`` is the imaginary unit. |
| ``c``; ``\mathcal C``; ``c=0`` | Contingency/scenario index; declared scenario set; base state. |
| ``k``; ``\mathcal T``; ``\Delta t_k`` | Chronological period index; ordered period set; period duration/start-to-start interval in hours. Older pages use ``t`` for the period index. |
| ``x``; ``x_c``; ``x_{k,c}`` | AC state ``(v,\delta,P,Q)``; state in scenario ``c``; state in period ``k``, scenario ``c``. This is a steady-state vector. |
| ``\theta`` | Selected controller/equipment design parameters; not a bus angle. |

Device IDs are positive identifiers, while state vectors use case ordering.
A subscript identifies a device or condition, not a new multiplication.

## Electrical quantities

| Symbol | Meaning and unit | API field / convention |
|---|---|---|
| ``S_{base}`` | System three-phase apparent-power base, MVA | `case.base_power` |
| ``f_{base}`` | Nominal frequency, Hz | `case.base_frequency`; not a frequency-dynamics model |
| ``v_b,\delta_b`` | Bus voltage magnitude, pu; voltage angle, rad | `vm`, `va` |
| ``\widetilde V_b=v_b e^{\mathrm j\delta_b}`` | Complex bus voltage phasor, pu | Reconstructed from `vm`, `va`; technical branch pages also write `Vf`, `Vt`. |
| ``P_g,Q_g`` | Generator active/reactive injection, pu | `pg`, `qg`; positive means injected into the network. |
| ``P_b^L,Q_b^L`` | Aggregate active/reactive consumption at a bus, pu | Sum of `Load.p`, `Load.q`; positive means consumption. |
| ``S=P+\mathrm jQ`` | Complex power, pu | ``|S|`` is apparent-power magnitude. |
| ``I_f,I_t`` | Currents into a branch at its two terminals, pu | Both point from their bus into the branch. |
| ``S_f,S_t`` | Complex powers into a branch, pu | ``S_f=\widetilde V_f\overline{I_f}``, likewise at ``t``. |
| ``r_\ell,x_\ell,z_\ell,y_\ell`` | Series resistance, reactance, impedance and admittance, pu | ``z_\ell=r_\ell+\mathrm jx_\ell``, ``y_\ell=1/z_\ell``. |
| ``b_\ell^{ch}`` | Total branch charging susceptance, pu | `Branch.charging`; half at each internal terminal. |
| ``\tau_\ell,\phi_\ell,a_\ell`` | Positive tap ratio; phase shift, rad; complex tap | `tap_ratio`, `phase_shift`; ``a_\ell=\tau_\ell e^{\mathrm j\phi_\ell}`` on the from side. |
| ``G_s,B_s`` | Bus-shunt conductance/susceptance, pu | Positive ``G_s`` consumes active power; positive ``B_s`` injects reactive power. |
| ``Y`` | Complex nodal admittance matrix, pu | Maps bus phasors to net outgoing current. |
| ``\underline z,\overline z`` or ``z^{min},z^{max}`` | Lower/upper bound on a real quantity ``z`` | Context supplies its units; a bar on a complex phasor/current instead means conjugation. |

Complex conjugation is also written `conj(z)` or ``z^*``; conjugate transpose is
``(\cdot)^H`` or, in the global-feasibility page, ``(\cdot)^*`` on a vector/matrix.
``|z|`` denotes absolute value or complex magnitude. ``\|z\|_\infty`` is the largest
absolute component of a vector. ``\sum`` sums the indexed quantities.

## Reactive control and design

| Symbol | Definition |
|---|---|
| ``v^m_{j,c}`` | Voltage magnitude measured by controller ``j`` in scenario ``c``; it may differ from the voltage at the generator bus. |
| ``v_j^{ref}``; ``d_j^-,d_j^+`` | Voltage reference; nonnegative lower/upper deadband widths, pu voltage. |
| ``v_j^-=v_j^{ref}-d_j^-``; ``v_j^+=v_j^{ref}+d_j^+`` | Lower/upper deadband edges, pu voltage; code `v_db_low`, `v_db_high`. |
| ``m_j`` | Positive droop slope in pu voltage per pu reactive power; code `slope`. The proportional gain magnitude is ``1/m_j``. |
| ``q_j^0`` or ``Q_j^0`` | Reactive output inside the deadband, pu; code `q_ref`, legacy `q_at_deadband`. Superscript 0 here is a curve parameter, not the base scenario. |
| ``q_j^{raw}`` | Unsaturated response of a controller, pu reactive power. |
| ``Q_g^-(P),Q_g^+(P)`` | Effective reactive limits at active output ``P``, including supplied capability restrictions. |
| ``S_g^{rated}`` | Optional generator apparent rating, pu on the system base; code `s_rated`. |
| ``[z]_+=\max(z,0)`` | Positive-part function, also called a hinge. |
| ``\operatorname{clip}(z,L,U)=\min(U,\max(L,z))`` | Projection of ``z`` into the real interval ``[L,U]``. |
| ``\epsilon_v,\epsilon_Q`` | Numerical smoothing widths for voltage/reactive response; not deadband widths or physical-limit relaxations. |

The droop-security page writes ``V_{j,c}`` for measured voltage, ``v_j`` for the
reference and ``Q_{j,c}`` for the attached generator's reactive output. Its slope
``m_j`` has the same convention as above. The solver guide's `Qraw`, `Qref`,
`Vref`, `V`, `slope` are respectively ``q^{raw},q^0,v^{ref},v^m,m``.

## Response, time and objectives

| Symbol | Definition |
|---|---|
| ``P_{g,0}``, ``P_{g,c}`` | Base/outage active output of generator ``g``, pu. |
| ``\alpha_{g,c}`` | Nonnegative response weight normalized over eligible survivors in ``c``; dimensionless. |
| ``\lambda_c`` | Common active-response request signal, pu active power; code `balancing_power`. After clipping, it need not equal total delivery. |
| ``L_{g,c},U_{g,c}`` | Effective active lower/upper bounds after capability and declared movement restrictions, pu. |
| ``r_g`` | Symmetric base-to-outage redispatch allowance, pu; not a rate. |
| ``r_g^{up},r_g^{down}`` | Planned inter-period active-output ramp rates, pu/hour. |
| ``P_g^{initial},Q_g^{initial}`` | Supplied generator reference outputs in the default dispatch-deviation objective, pu. |
| ``J`` | Optimization objective, with units specific to the selected objective. |
| ``E_{loss}`` | Duration-weighted active network energy loss, MWh. |
| ``h`` | Dimensionless minimum normalized upward headroom in reserve-aware studies. |

## Per-unit conversion and signs: a worked check

Per unit (**pu**) is a physical quantity divided by its declared base. On a
``100`` MVA power base, ``50`` MW active demand is ``0.50`` pu and ``20`` MVAr
reactive demand is ``0.20`` pu. Generator ``Q=+0.20`` pu injects 20 MVAr; load
``q=+0.20`` pu consumes 20 MVAr. A capacitive shunt injects reactive power, so its
reactive **consumption** is negative.

For physical voltage/impedance conversion, let ``V_{base}`` be line-to-line base
voltage in kV. Then ``Z_{base}=V_{base}^2/S_{base}`` is impedance base in ohms.
``z_{pu}=z_{ohm}/Z_{base}`` and ``Y_{base}=1/Z_{base}``. A compatible three-phase
current base is ``I_{base}=S_{base}/(\sqrt3 V_{base})`` in kA. The per-unit network
constructors expect already consistent bases; `base_frequency` is not a voltage base.

Angles supplied to native constructors use radians. Thus ``30`` degrees equals
``\pi/6`` radians, where ``\pi`` is the circle constant. Importers handle their
documented source conventions; do not convert an angle twice.

If a percentage droop is defined over a full reactive range ``\Delta Q=Q^{max}-Q^{min}``,
a voltage span of 4% gives ``m=0.04/\Delta Q``. For ``\Delta Q=2`` pu, ``m=0.02``
pu voltage/pu reactive power. Always identify the span and power base before using
a percentage from another source.

## Abbreviations used in the reference pages

| Abbreviation | Meaning |
|---|---|
| AC / DC | Alternating current / direct current. The DC power-flow screening approximation estimates active flows; it is not an exact AC equilibrium. |
| OPF / SCOPF | Optimal power flow / security-constrained optimal power flow. |
| AVR / AGC | Automatic voltage regulation / automatic generation control. |
| PWL / NLP | Piecewise linear / nonlinear program (or nonlinear programming). |
| LP / SOC / PSD | Linear program / second-order cone / positive semidefinite. |
| KKT | Karush–Kuhn–Tucker optimality conditions; used to encode interval projection in complementarity formulations. |
| LODF | Line-outage distribution factor, used in approximate active-flow screening. |
| MW / MVAr / MVA / MWh | Megawatt / megavar / megavoltampere / megawatt-hour. |
| pu | Per unit: divided by the declared physical base. |
| ID | Device or scenario identifier; not necessarily its vector index. |

Use [local symbols on the global-feasibility page](global_feasibility.md#Symbols-and-geometric-meaning)
for its certificate matrices: it deliberately uses a separate LP decision vector.
