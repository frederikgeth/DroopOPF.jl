# Solver formulations

Read [the physical curve](volt_var.md) before choosing its numerical encoding.
Both encodings below aim at the same supplied control law. They differ in how
corners are represented, not in the meaning of equipment capability.

## Symbols used here

`V` is measured voltage, `Vref` reference voltage, `Qref` deadband reactive output,
`Qraw` unsaturated request and `slope` positive voltage-per-reactive-power slope.
Voltage and power quantities use their native pu units. ``\epsilon>0`` denotes a
numerical smoothing width; ``z`` is a scalar input in the same units as that
width. ``u,w`` below are auxiliary hinge value/slack, also in those units.

## Smooth nonlinear programming

`solve_opf` encodes the positive-part terms in the volt-var graph with stable
softplus functions based on `LogExpFunctions.log1pexp`. The mathematical
positive-part approximation is

```math
s_\epsilon(z)=\epsilon\log(1+\exp(z/\epsilon))
\ \longrightarrow\ \max(z,0)\quad\text{as }\epsilon\to0^+.
```

Here ``s_\epsilon`` is the smooth hinge, ``\log`` the natural logarithm and
``\exp`` the exponential. The implementation uses a stable evaluation instead
of forming a potentially overflowing exponential directly. Ipopt is the default:

```julia
ipopt_result = solve_opf(case; smooth_epsilon = 1.0e-3)
```

MadNLP receives the same JuMP model and can be selected through the optimizer
factory:

```julia
using MadNLP
madnlp_result = solve_opf(
    case;
    optimizer_factory = MadNLP.Optimizer,
    smooth_epsilon = 1.0e-3,
)
```

The voltage smoothing width is in per-unit voltage. By default, reactive
smoothing is a relative fraction of each control's available reactive range;
`smooth_reactive_epsilon` can override it with an absolute per-unit width.

## Exact complementarity formulation

`solve_opf_complementarity` uses MathOptComplements and CCOpt. Each voltage
hinge is represented as a nonnegative complementarity pair: ``u\ge0``,
``w=u-z\ge0`` and ``uw=0`` imply ``u=\max(z,0)``. This is often written
``0\le u\perp w\ge0``; the perpendicular symbol means zero product here.
Reactive clipping
is represented by the Karush–Kuhn–Tucker (KKT) conditions for projection of the raw droop value
onto the control's reactive interval.

When both deadband widths are fixed at exactly zero, the raw response is
`Qraw = Qref + (Vref - V) / slope`. The model omits the two voltage-hinge
pairs and their four auxiliary variables; the two Q-projection pairs remain.
This applies to fixed curves and to designs with free slope/reference and fixed
zero widths. Positive or variable widths retain the general hinge formulation.
The smooth backend uses the same affine raw response and retains its reactive
saturation smoothing. This is algebraically equivalent to subtracting the two
voltage softplus terms, including derivatives.

`ccopt_encoding_audit` marks these controllers with
`voltage_hinges_eliminated=true`; their hinge errors are zero by construction.
Raw-response, projection and independent exact-droop errors remain reported.


```julia
ccopt_result = solve_opf_complementarity(case)
```

The exact formulation has no smoothing parameter. CCOpt may report
`ALMOST_LOCALLY_SOLVED` after its homotopy; use the independent equilibrium
report and `complementarity_residual_max` to assess the result.

## Comparing solutions

Ipopt and MadNLP should usually agree closely because they solve the same
smoothed NLP. CCOpt solves the exact PWL graph, so compare physical residuals,
objectives, operating regimes, and state differences rather than expecting
bitwise equality. The reproducible comparison is:

```sh
julia --project=. examples/m1_solver_comparison.jl
```

See [Solver compatibility](https://github.com/frederikgeth/DroopOPF.jl/blob/main/SOLVER_COMPATIBILITY.md)
for recommended starting tolerances.

## Solver compatibility

| Capability | Ipopt | MadNLP | CCOpt |
|---|---|---|---|
| Single-case OPF | smooth, tested | smooth, tested | exact, tested |
| Fixed-curve SCOPF | smooth, tested | smooth, tested with a validated warm start | exact, tested |
| Single-controller parameter design | smooth, tested | smooth, tested with a validated warm start | use the multi-controller exact API instead |
| Reconstructed fixed curve | smooth re-solve available | smooth re-solve available | exact re-solve, tested |

The fixed-curve SCOPF/droop design fixture is nonconvex and MadNLP can select an infeasible local point
from its default start at the tight `1e-5` smoothing width. The compatibility
test therefore warm-starts MadNLP from the independently validated Ipopt fixed-curve SCOPF
states. Both smooth solvers then validate and reach the same droop design objective, but
their optimized parameter values need not match because the design is weakly
identifiable.

The single-controller `optimize_droop_parameters(study, control_id; ...)`
overload rejects `CCOpt.Optimizer`: its parameterized model is a smooth NLP.
The multi-controller overload accepts
`optimize_droop_parameters(study, controls; encoding=:complementarity, ...)`
for an exact CCOpt design. Omit `optimizer_factory` in exact mode. The same
encoding can be selected on `optimize_droop_security`; its final scenario
assessments retain the master's encoding. Nonzero deadbands and saturation
remain explicit complementarity constraints, and exact design still requires
independent physical and policy validation. Shared exact design currently uses
the case attachments; explicit `reactive_assignments` are rejected on this
parameterized exact path. After reconstruction with
`with_droop_settings`, use `validate_droop_design` for exact PWL state replay,
which is independent of all three solvers, or use
`solve_scopf(...; encoding=:complementarity)` for a CCOpt exact
fixed-curve re-solve. Solver termination alone is never the acceptance test;
the resulting state must pass `equilibrium_report`.
