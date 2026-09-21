# Implemented joint AC OPF formulation

This S1.1 contract documents the existing M7 `optimize_joint_design` base-case
model. It uses balanced steady-state AC equations. Security coupling remains M9;
automatic tap control and complex-bank optimization remain deferred. Continuous
ratios and bank admittances are relaxed decisions, not certified switch positions.

## Quantities and ownership

Powers/admittances use the case per-unit base; voltage magnitudes are per unit and
angles are radians. Generator P/Q are injections, loads consume P/Q, and branch
terminal powers are positive from a bus into a branch.

| Quantity | Meaning | Treatment |
|---|---|---|
| ``v_i,\theta_i`` | Bus voltage magnitude and angle | Operating variables |
| ``p_g,q_g`` | Generator injections | Operating variables; unavailable units zero |
| ``\tau_\ell,\phi_\ell`` | From-side ratio and phase | Ratio fixed unless selected; phase fixed |
| ``G_i^F,B_i^F`` | Fixed shunts and unselected banks | Available supplied admittance |
| ``B_k,G_k`` | Selected simple bank | Continuous B; G determined by B |
| ``m_c,r_c,d_c^-,d_c^+`` | Slope, reference, two deadband widths | Each fixed or independently bounded |
| ``q_c^0,\underline q_c,\overline q_c`` | Deadband Q and saturation levels | Supplied controller data |

`Case` owns physical data. `TapControl`, `ShuntControl` and `DroopControl`
select free parameters and bounds. Omitted parameters retain supplied settings;
equal bounds fix selected parameters. `initial_state` and policy initial values
are numerical starts, not new objective references. Results are reconstructed as
physical data before independent validation.

## Transformer and line powers

For an available branch from f to t, define

```math
y=(R+\mathrm{j}X)^{-1},\quad y^c=\mathrm{j}b^c/2,\quad
a=\tau e^{\mathrm{j}\phi},\quad V_i=v_i e^{\mathrm{j}\theta_i}.
```

The terminal admittances are

```math
\begin{bmatrix}I_f\\I_t\end{bmatrix}=
\begin{bmatrix}
(y+y^c)/\tau^2 & -y/\overline a\\
-y/a & y+y^c
\end{bmatrix}
\begin{bmatrix}V_f\\V_t\end{bmatrix}.
```

For either terminal i, opposite bus j, self coefficient ``G_s+\mathrm{j}B_s``
and mutual coefficient ``G_m+\mathrm{j}B_m``, the builder imposes

```math
\begin{aligned}
P_{\ell,i}&=v_i^2G_s+v_iv_j[G_m\cos(\theta_i-\theta_j)+B_m\sin(\theta_i-\theta_j)],\\
Q_{\ell,i}&=-v_i^2B_s+v_iv_j[G_m\sin(\theta_i-\theta_j)-B_m\cos(\theta_i-\theta_j)],\\
P_{\ell,i}^2+Q_{\ell,i}^2&\leq\overline S_\ell^2,\quad i\in\{f,t\}.
\end{aligned}
```

The positive tap ratio appears inside these coefficients, including the from-side
charging divided by ratio squared. Ratings apply at both terminals. Unavailable
branches contribute zero. There is no ideal voltage-ratio equality across the
complete series-impedance branch.

## Fixed shunts and simple banks

A shunt consumes ``S^{sh}=(G-\mathrm{j}B)v^2``: positive B supplies Q, negative
B absorbs Q, and nonnegative G consumes P. Selected bank k has one nonzero step:

```math
n_k=B_k/b_k^{step},\quad G_k=n_k g_k^{step},\quad
\underline B_k\leq B_k\leq\overline B_k.
```

The interval lies within the extrema of legal count times step susceptance,
including reversed ordering for reactors. Relaxed count need not be a legal
integer. G/B move together; selected supplied admittances are removed before
their variable replacements are inserted. Unselected banks retain their supplied
state. Bank Q remains proportional to voltage squared.

## AC balance and limits

Let ``\mathcal G_i`` denote generators at bus i and ``\mathcal E_i`` its
incident branch terminals. Include all available shunts:

```math
\begin{aligned}
G_i&=G_i^F+\sum_{k\text{ at }i}G_k,\quad B_i=B_i^F+\sum_{k\text{ at }i}B_k,\\
\sum_{g\in\mathcal G_i}p_g-P_i^D&=\sum_{\ell\in\mathcal E_i}P_{\ell,i}+G_iv_i^2,\\
\sum_{g\in\mathcal G_i}q_g-Q_i^D&=\sum_{\ell\in\mathcal E_i}Q_{\ell,i}-B_iv_i^2.
\end{aligned}
```

Voltage magnitudes obey supplied bounds. Angles lie in ``[-\pi,\pi]``; exactly
one reference angle is fixed to zero. Available generators obey P/Q boxes.
Droop-controlled P additionally obeys the intersection with controller P
capability. Q follows the curve below while retaining generator Q bounds.
Unavailable generators have zero P/Q and no active droop equation. The current
base-case solver requires one reference bus; it does not create island slacks.

## Exact and smoothed droop

For controller c, use voltage at its regulated bus, ``L_c=r_c-d_c^-`` and
``H_c=r_c+d_c^+``. The exact response used in validation is

```math
q_c^{raw}(v)=q_c^0+\frac{[L_c-v]_+-[v-H_c]_+}{m_c},\quad
q_c^{exact}(v)=\min\{\overline q_c,\max\{\underline q_c,q_c^{raw}(v)\}\}.
```

Here ``[z]_+=\max(z,0)``. Stored slope has units voltage/reactive power; outside
deadband and saturation, ``dq/dv=-1/m``. Slope/reference are positive, widths
nonnegative, total deadband strictly positive, and the lower edge positive.
Zero total deadband and independently movable saturation knots are outside the
current design family.

The optimizer uses ``s_\epsilon(z)=\epsilon\log(1+\exp(z/\epsilon))``, evaluated
using stable `log1pexp`:

```math
\begin{aligned}
\widetilde q_c^{raw}(v)&=q_c^0+
\frac{s_{\epsilon_v}(L_c-v)-s_{\epsilon_v}(v-H_c)}{m_c},\\
\widetilde q_c(v)&=\underline q_c+
s_{\epsilon_{q,c}}(\widetilde q_c^{raw}-\underline q_c)-
s_{\epsilon_{q,c}}(\widetilde q_c^{raw}-\overline q_c),\\
q_g&=\widetilde q_c(v_{\mathrm{regulated}(c)}),\\
\epsilon_{q,c}&=\epsilon_r\min(q_c^0-\underline q_c,\overline q_c-q_c^0).
\end{aligned}
```

The joint API sets voltage epsilon and relative reactive epsilon to
`smooth_epsilon` (default ``10^{-5}``; S1 explicitly uses ``10^{-6}``).
The two resulting widths have different physical units. Smoothing is a declared
numerical approximation whose discrepancy from the exact curve must validate.

The free-parameter builder composes two scalar softplus operators with arithmetic
so JuMP retains exact sparse Hessians. This is algebraically the same response
as the direct evaluator; it changes derivative availability, not the curve.

## Unchanged objective

```math
\min J=\sum_g[(p_g-p_g^{initial})^2+10^{-3}(q_g-q_g^{initial})^2].
```

References are generator input data; unavailable generator terms are constant.
There are no design, movement or loss penalties. Reporting a quantity does not
make it an objective. Positive whole-objective scaling preserves minimizers but
changes numerical KKT scales; experiments must retain the original-unit J.

## Convergence and independent validation

Physical feasibility and solver convergence are separate. For equalities c,
inequalities h and variable bounds, stationarity measures

```math
\nabla J+\nabla c^\mathsf T\lambda+\nabla h^\mathsf T\mu-z_L+z_U.
```

Complementarity measures multiplier times inequality/bound slack. Physical
residuals can be small while stationarity or complementarity remain large.
Iteration limits are retained as failed optimization attempts. Existing joint
validation accepts local, almost-local or optimal termination only together with
policy and physical validity; reports distinguish full local convergence from
acceptable-level stopping.

The diagnostic callback records Ipopt primal/dual measures, native unscaled
constraint/bound/stationarity/complementarity residuals, barrier parameter, step
lengths, regularization and restoration flags. Native "unscaled" follows the
solver API; it does not undo a separately requested whole-objective multiplier.
See [Ipopt output definitions](https://coin-or.github.io/Ipopt/OUTPUT.html).

Independent branch checks form ``V'_f=V_f/a``,
``I_f=[y(V'_f-V_t)+y^cV'_f]/\overline a`` and
``I_t=y(V_t-V'_f)+y^cV_t``, then ``S_i=V_i\overline I_i``.
This current-based calculation is separate from the real terminal expressions.
Relaxed banks become equivalent fixed admittances; droops replay exact curves.

| Contract | Builder | Independent check |
|---|---|---|
| Transformer powers and both ratings | `_branch_admittances`; `_add_tap_network!` | `branch_flows` in `physics.jl` |
| Bank range and G/B relation | `_shunt_policy`; `_shunt_variables!` | `with_shunt_settings`; `shunt_powers`; `bank_powers` |
| AC balance and operating bounds | `_build_acopf_model`; `_add_tap_network!` | `power_balance`; `validate_equilibrium` |
| Fixed/free droop and smoothed response | `_joint_droop_policy`; `_smooth_droop_value` | Exact response in `validate_equilibrium` |
| Selected settings and fixed devices | `joint_design.jl` extraction | `validate_joint_design` and equipment-policy validators |
| Objective | `jump.jl` | `joint_design_metrics` recomputation |

Default tolerances are AC balance ``10^{-6}``, exact droop ``10^{-5}``, operating
limits ``10^{-6}``, unavailable generation ``10^{-8}`` and joint setting policy
``10^{-6}``. S1 does not weaken these. Continuous feasibility is distinct from
legal discrete implementation.

## Public-case scope and change control

The MATPOWER adapter imports core AC data, fixed ratios/phases, ratings and
aggregate bus shunts. It does not import cost curves or enforce branch
angle-difference limits. Public baselines use the project dispatch-deviation
objective, not the published PGLib cost optimum. Reports separately audit source
angle bounds at the returned state. Controllers and bank capabilities require
documented study overlays, rather than inferred measurements.

Any proposed equipment-equation, capability or control-law change must be
explained to the user before implementation. Numerical diagnostics do not
authorize a physical model change.


## S1 example-level smoothing budget

Softplus differs from the positive-part function by at most epsilon times log(2).
Applying the triangle inequality to the two deadband terms, and then the
1-Lipschitz exact clipping map and its two smoothed terms, gives

```math
|\widetilde q(v)-q^{exact}(v)|
\leq 2\log(2)\left(\frac{\epsilon_v}{m}+\epsilon_q\right).
```

With the joint API, epsilon_v=epsilon and epsilon_q=epsilon times Q scale.
The public experiment uses the largest coefficient across controls and each
selected slope's lower bound. It budgets 1e-6 pu curve error within the unchanged
1e-5 exact-droop tolerance. Numerical constraint residuals still require separate
validation. This conservative example policy leaves the default unchanged and
can produce stiff derivatives. It is an approximation bound, not a convergence
certificate; see [extended evidence](s1_extension.md).


## Optional equivalent controller coordinates

With `control_normalization=:bounds`, each free controller setting uses

```math
u_j = \ell_j + w_j z_j,\qquad w_j=h_j-\ell_j>0,\qquad 0\leq z_j\leq1.
```

The physical bounds and starting point map bijectively through this affine
transformation. Equal bounds remain fixed without division by zero. This applies
to selected droop parameters, tap ratios and bank susceptances; generator P/Q,
voltage magnitudes and angles retain their existing coordinates. Bank conductance
continues to follow the same conductance/susceptance ratio.

For the combined decision vector, write `x = a + D z`, where operating-variable
entries of diagonal `D` are one. The implemented expressions satisfy

```math
\widetilde c(z)=c(a+Dz),\quad \widetilde f(z)=f(a+Dz),\quad
J_z=J_xD,\quad \nabla_z^2 L=D^T\nabla_x^2 L D.
```

No residual or objective scaling is introduced here. Raw solver stationarity is
coordinate-dependent; physical validation always reconstructs physical settings.
Solver bound-push distances are also expressed in the chosen coordinates.
Saved numerical seeds require a matching normalization mode and layout. The
result schema and all independent acceptance tolerances remain unchanged.
