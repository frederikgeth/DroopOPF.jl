# Optional global feasibility escalation

```@meta
CurrentModule = DroopOPF
```

A second-order cone (SOC) models a Euclidean-norm inequality; positive
semidefinite (PSD) constraints model nonnegative quadratic forms. SOS2 means
special ordered set of type 2: at most two adjacent interpolation weights may be
nonzero, allowing an exact piecewise-linear (PWL) graph. Symbols for the
certificate and lifted-voltage equations are defined below.

Global analysis extends the existing three-outcome gate. It does not replace it.
Only an independently checked AC point produces `feasible`; a replayable
certificate produces `certified_infeasible`; all other outcomes are `unresolved`.

The scalable policy is to replay known points first, attempt local feasibility,
then escalate selected unresolved cases. Do not make full global search a
mandatory cost for every candidate, demand condition or contingency.

## Implemented layers

| Layer | Model/evidence | Can establish feasibility? | Can certify infeasibility? |
|:--|:--|:--|:--|
| Existing gate | Original AC/PWL replay and analytical bounds | Yes | Yes, for supported analytical contradictions |
| Sparse outer LP | Voltage-square envelopes, edge-product SOC support cuts, terminal thermal cuts, full droop convex hull | No | Yes, with exact rational Farkas replay |
| Cycle PSD cuts | Bounded-size matrix blocks with shared fill products and exact rational support cuts | No | Yes, through the same rational LP certificate checker |
| LP bound tightening | Min/max selected voltages, exact weak-duality bounds, rebuilt square/droop envelopes | No | Yes, if the refined LP yields a replayable contradiction |
| Sparse SOC relaxation | Edge products, voltage-square envelopes, full droop convex hull | No | Numerical evidence only in this implementation |
| Global search | Rectangular AC equations, lifted edge flows, exact SOS2 droop regions | Yes, after original-model replay | Numerical solver evidence only; complete search-tree proof verification is not implemented |

All models include generator availability, the study P/Q bounds, fixed source
taps/shunts, both branch-terminal ratings and the frozen feasibility tolerances.
Selected/free equipment is explicitly unsupported by these global backends;
the gate records that limitation rather than freezing it silently. The verified
LP currently requires zero branch phase shifts, which both imported test cases
satisfy. It deliberately omits angle windows and rank-one constraints, so its
feasible set contains the original feasible set. Optional cycle PSD cuts strengthen
consistency between edges while retaining a valid outer relaxation.

The SOC/global models include supplied edge angle windows within (-pi/2,pi/2).
Other windows are recorded as omitted. Edge angles are periodic, and one gauge
is chosen per island; original unwrapped angles and reference requirements are
always rechecked on returned points. Consequently these restrictions can be an
outer representation of the original angle contract. They cannot exclude an
original feasible point by silently selecting a droop region.

Global search uses thermal-current bounds and shortest-path angle bounds to
narrow rectangular voltage coordinates, with numerical outward padding. These
numerical bounds are not themselves accepted as exact certificates.

## Symbols and geometric meaning

A linear program (**LP**) optimizes a linear function under linear constraints.
This outer LP contains every original feasible AC point; excluding the outer
set therefore excludes the original set. The reverse implication does not hold.
In the certificate below, ``x`` is an LP decision vector, ``A`` its inequality
coefficient matrix, ``b`` its right-hand-side vector, ``l,u`` finite componentwise
bounds, ``y`` a nonnegative multiplier vector, and ``i`` a vector-coordinate index.
``A^\mathsf T`` denotes transpose. Certificate margin ``m`` is a scalar, unrelated
to the droop slope also written ``m`` on control pages.

In the voltage lift later below, ``V`` is the complex bus-voltage vector,
``W=VV^*`` its lifted outer-product matrix, ``*`` conjugate transpose, and ``z``
a complex test vector. Positive semidefinite (**PSD**) means ``z^*Wz\ge0`` for
every ``z``. This ``z`` is not branch impedance. The LP's real decision vector
contains real and imaginary components of such voltage-product quantities.

## What makes an LP certificate independently checkable

For the outer LP `Ax <= b`, with finite box bounds `l <= x <= u`, the LP solver
suggests nonnegative multipliers `y`. The checker computes, using exact rational
arithmetic on stored inputs,

```math
m = \sum_i \min\{(A^\mathsf{T}y)_i l_i,
                        (A^\mathsf{T}y)_i u_i\}-b^\mathsf{T}y.
```

If `m > 0`, every point in the box contradicts the weighted inequalities. This
remains valid when the numerical multiplier vector has a stationarity residual:
the box correction accounts for it instead of assuming it is zero.

Network admittances for zero phase shifts are constructed rationally from stored
R, X, charging and tap data. Physical PWL knots are retained. SOC and thermal
support directions are checked to have norm at most one. Floating-point LP rows
are rounded outwards over their finite boxes. A certificate reader reconstructs
the mathematical relaxation and verifies its positive rational contradiction;
it does not trust HiGHS's infeasibility status.

Voltage-bound tightening uses the corresponding weak-duality formula with the
objective coefficient included. Each improved bound has its own multiplier
proof. Bounds are rounded outwards to a dyadic grid to control arithmetic size.
Every proof is replayed before rebuilding the droop graph's convex hull on a
narrower domain. The ledger's displayed floating-point bounds are not evidence.

`verified_feasibility_voltage_bounds` can supply these bounds to a subsequent
global search. They apply to the original strict problem: passing them to a
model that relaxes bus voltage is rejected. Use `max_relaxation=0` for that search.

## Bounded cycle strengthening

Pass `psd_clique_limit=8` to `certify_feasibility_lp` to enable cycle strengthening.
The default remains zero for compatibility with earlier ledgers. A deterministic
minimum-degree elimination builds small cliques and shared auxiliary voltage
products for fill edges. Elimination stops if the next clique would exceed the
limit (supported limits: 3–32). Any remaining dense core is left relaxed. Parallel
circuits share their bus-voltage products, with conjugation for reversed edges.

For a physical voltage vector, the lifted matrix is `W = V V*`, so every principal
block is positive semidefinite. At an LP solution, negative eigenvectors suggest
cuts of the form `z* W z >= 0`. The vector is quantized to rational components;
**every** such vector gives a valid cut, whether or not it is an accurate
eigenvector. Replay reconstructs its exact rational coefficients and the clique
from the network. Numerical eigenvalues are never accepted as proof.

This also covers cycles longer than triangles by introducing shared fill
products. It does not impose rank one or complete cycle consistency. Cuts are
added only as needed and obey the existing round/time budgets. Bound-tightening
stages and saved certificates retain the clique configuration, so they rebuild
the same sparse variables and inequalities. Older ledgers still reconstruct the
original model with no cycle extension.

```julia
lp = certify_feasibility_lp(problem; optimizer_factory=HiGHS.Optimizer,
    psd_clique_limit=8, time_limit=60.0, max_rounds=100,
    bound_tightening_rounds=3, bound_bus_limit=16)
```

## Optional solver environment

The optional solvers are installed separately from the main package.

The optional environment uses HiGHS for LP search and SCIP for global search.
SCIP supports spatial branch-and-cut for bounded MINLPs; this provides numerical
global search, not an independently replayable nonlinear search-tree certificate
in DroopOPF. See [SCIP's problem classes](https://www.scipopt.org/doc/html/WHATPROBLEMS.php)
and [the Julia interface](https://github.com/scipopt/SCIP.jl).

```julia
result = check_feasibility(problem;
    initial_states = [source_state],
    lp_options = (optimizer_factory=HiGHS.Optimizer,
                  time_limit=30.0, bound_tightening_rounds=2),
    global_options = (optimizer_factory=SCIP.Optimizer,
                      target_bus=8, time_limit=60.0),
)
```

To reuse verified bounds explicitly:

```julia
lp = certify_feasibility_lp(problem; optimizer_factory=HiGHS.Optimizer,
    time_limit=30.0, bound_tightening_rounds=2)
if lp.status == :unresolved
    global_analysis = solve_global_feasibility(problem;
        optimizer_factory=SCIP.Optimizer, target_bus=8, max_relaxation=0.0,
        voltage_bound_result=lp, time_limit=60.0)
end
```

Budgets cap LP refinement rounds, bound-tightening rounds, the number of buses
selected for tightening, and solver time. Model compilation/construction and
independent proof replay have additional overhead. Solver bounds, candidate
points, controls, scope fingerprints and failed attempts remain in the ledgers.

## Interpreting incomplete calculations

A time limit, zero lower bound or positive local relaxation value does not
certify infeasibility. A feasible outer relaxation is not an AC witness.
Sparse construction does not establish tractable global solution time.
Retain the model contract, solver outcome, failed attempts and independently
replayed proof or witness for each calculation.

## API

```@docs
build_global_feasibility_model
seed_global_feasibility!
solve_global_feasibility
certify_feasibility_lp
verified_feasibility_voltage_bounds
```
