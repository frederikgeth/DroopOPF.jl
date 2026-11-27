# Preparing a solver start and preventive dispatch

A numerical starting point helps a solver converge. A preventive dispatch sets
what equipment will actually do. DroopOPF keeps those two operations explicit.
Neither a seed nor a converged solver status alone establishes security.

## Initialization and acceptance checks

1. Complete the [source-data checks](case_io.md).
   Freeze the study contract before choosing a seed. Record the controls and
   equipment that may change, the objective, allowed preventive dispatch,
   movement limits, shared parameters, and the training and held-out cases.
2. Prefer a replay-qualified same-contract state. When testing a new demand,
   first solve the frozen schedule if one exists. Use its qualified equilibrium
   and nearby qualified states as deterministic seed candidates. Map voltages
   and outputs by equipment ID, shift angles to the target reference and
   check availability, limits and control settings in the target case.
3. Use saved-profile or flat starts as fallbacks. If no suitable seed is
   available, try fixed-control feasibility or a loss-only AC OPF as a
   preparatory solve. Use the resulting primal values to initialize the target
   model. Keep any freer dispatch, temporary guards, or relaxations in a
   separate preparation record. Record seed provenance, solver status, residuals,
   iterations and objective for each attempt.
4. Compare a local candidate with a known feasible baseline under the same
   constraints and objective. If the candidate is worse or unresolved, retry
   from the qualified baseline or a nearby state before selecting the best
   replay-qualified result. If the baseline violates extra search guards, report
   that distinction before comparing objectives.
5. Qualify under the declared physical and control limits. Independently replay
   AC balance, voltage and angle bounds, both branch terminals, effective
   capability, active response, equipment and frozen settings. Treat numerical
   failure as unresolved. Any infeasibility certificate must match the case,
   demand, and limits it claims to exclude.

If the study needs operating headroom, declare its metric, target and state
scope separately from the original limits. Measure its economic cost and
verify the achieved headroom in replay. Where a study evaluates a dispatch
schedule between its knots, include interior points near binding equipment.
Keep frozen-schedule results separate from demand-specific redispatch, even
when all controller parameters are shared.

## Numerical starting points

Without an `initial_state`, the AC builder starts voltage magnitudes at 1 pu,
angles at zero radians, and generator active/reactive power at their stored initial
values. With an `ACState`, it uses the supplied voltage, angle, active and reactive
vectors in case order. These are primal starts; no dual multipliers are supplied.
Common-frequency solves otherwise start frequency at the case nominal value.

`prepare_initialization` copies a supplied state, shifts all angles to the numerical
reference, and evaluates the declared controller laws. For solved frequency it
uses bounded scalar bisection at the guessed voltages and estimated losses:

```math
\sum_i P_i(f;\widehat V)=P_D+\widehat P_{\rm loss}.
```

Here `i` indexes generators, `f` is frequency in Hz, `P_i` is the saturated active
response in system-base pu, `V̂` is guessed voltage in pu, `P_D` is total active
load, and `P̂_loss` is estimated active network loss on the same power base.
A missing bracket is returned explicitly. It does not prove AC infeasibility.
The projected state need not satisfy AC balance; always solve and validate it.
For numerical recovery, `solve_common_frequency(...; objective_policy=:feasibility)`
uses a zero objective with the same constraints; its default `:dispatch` policy
retains the dispatch-distance objective.

```julia
seed = prepare_initialization(case, plants, responses;
    state=previous_state, frequency_bounds=(58.0, 62.0),
    loss_estimate=estimated_loss_pu, provenance=:previous_ac)
result = solve_common_frequency(case, plants, responses;
    frequency_bounds=(58.0, 62.0),
    initial_state=seed.state, initial_frequency_hz=seed.frequency_hz)
report = validate_common_frequency(case, result)
```

The numerical example bounds must be replaced with the study's declared bounds.
A conventional outage OPF can supply a fallback seed. Its unrestricted dispatch
is not an accepted controlled-outage result; the final solve must enforce the
original frozen response contract.

## Preventive dispatch and reserves

`design_preventive_dispatch(...; objective=:reserve)` explicitly changes preventive
active references. It retains reactive curves, frequency gains and equipment.
The nominal base AC state is solved jointly with a common symmetric reserve
fraction `η` of each available responder's effective active range `ΔP_i`:

```math
r_i=\eta\Delta P_i,\qquad
\underline P_i\le P_i^0-r_i\le P_i^0+r_i\le\overline P_i.
```

`r_i` is upward and downward reserve, `P_i^0` is preventive output, and the lower
and upper bounds are effective active-power limits. All powers use system-base
pu. The objective maximizes `η`, bounded between zero and one half. Both reserve
endpoints must respect apparent-power and inverter current capability at the
base reactive output and voltage. Reserve also cannot exceed frequency gain
(in system pu/Hz) times the smaller allowed deviation from nominal frequency.
Zero-gain resources receive no primary-response reserve credit.

A supplied `reserve_fraction_target` holds that fraction and minimizes normalized
preventive redispatch instead. This is a feasible reserve target, not a claim
that the maximum reserve has been found.

These are local base-point capability margins. They do not certify delivery
through a congested network, energy duration, a frequency nadir or stability.
The caller must subsequently freeze the chosen references and assess outages.

## Security-aware preventive references

With `objective=:security` and explicit branch `contingencies`, the same API couples
the base and supplied outage states through common preventive active references.
It minimizes squared active redispatch normalized by each generator's source
active range (with a 0.001 pu numerical denominator floor). Gains and reactive
curves stay fixed. Solved-frequency scenarios obey saturated primary response;
prescribed-frequency scenarios retain free conventional OPF dispatch, so these
are different operating policies. Neither allows equipment movement here.
The security objective defaults to a zero common reserve fraction. Set
`reserve_fraction_target` explicitly when a positive local reserve floor must
also be enforced.

`validate_preventive_dispatch` checks native convergence, each AC/controller state,
angle bounds and reserve endpoints. A bounded set of design contingencies is not
full security qualification: freeze each candidate and check the complete required
catalogue, retaining one common policy across its accepted states.


Shared static witnesses may now select explicit `tap_controls` and `shunt_controls`.
Their continuous settings are tied across every demand and outage; selected outaged
branches have no electrical tap variable in that state. Unselected equipment stays
fixed. Validate with the identical control lists. This is preventive sharing, not
corrective movement or discrete-bank qualification. Supply legal bank metadata and
qualified same-contract starts; retain fixed-equipment baselines for comparison.


## Choosing an initialization and design objective

Use the [workflow flowcharts](design_workflow.md) to declare the physical
contract, numerical start, objective priorities and candidate review criteria.
The ordinary OPF/joint builder minimizes weighted squared dispatch deviation.
Reserve or loss objectives require an explicitly selected supporting API.
A preparatory state needs target-contract replay before it becomes an accepted
operating point. Record controls, equipment movement, state scope and seed origin.

## Strict staged joint design

Local qualification, 27 November 2026. Use the opt-in API for a single snapshot:

    r = optimize_staged_joint_design(case;
        reserve_generator_ids=[1, 2],
        droop_controls=selected_droops,
        tap_controls=selected_taps,
        shunt_controls=selected_banks,
        initial_state=seed,
        hessian="exact",
        initialization_max_iterations=3000,
        initialization_max_seconds=1200.,
        max_iterations=3000,
        max_seconds=1200.)

Only explicitly supplied controls and equipment bounds are available. Existing
optimize_joint_design retains its original dispatch-distance objective and
behavior. The staged API uses cold zero-objective feasibility, maximum common
symmetric Q-box reserve, zero-objective feasibility with that reserve retained,
then active-loss minimization. The last objective is total system-base Pg;
with fixed load its minimizer is the loss minimizer. Each stage separately
reports loss_mw, including fixed shunt consumption in the net balance.

The reserve metric is the minimum of (Qg-Qmin)/(Qmax-Qmin) and
(Qmax-Qg)/(Qmax-Qmin) across explicitly selected available generators.
Select only nonzero Q ranges. This is source generator Q-box reserve:
tighter droop or apparent/current capability may limit it further and are
still enforced, but do not redefine this metric. AVR references retain their
supplied native reactive-assignment policy. This API does not reproduce the
work-machine CLI's CSV classification, AVR scheduling, RMPCT plant sharing,
capability preparation or PowerModels model import. Those are separate
consumer policies, not implicit changes to core controls or data.

The same model survives all stages. Every primal variable is copied by identity
to its next start, including selected droop, equipment and auxiliary values.
After reserve initialization, the reserve auxiliary is fixed to zero and its
requirement is represented by the retained fixed floor. No dual warm start is
claimed. Initialization and design use the same Hessian,
tol 1e-8, constraint tolerance 1e-10, zero numerical bound relaxation, bound/slack
push and fraction values 1e-9, and disabled acceptable-level early stopping.
Model residuals must be <=1e-10; native converged/feasible status and unchanged
independent physical replay are also required. Reports retain requested and
actual first-iterate residuals, final residuals and all starts/returned primals.

The reserve floor is computed once as max(0, initialized_reserve - 1e-8).
A zero floor adds no duplicate Q-limit rows. Physical limits and existing
replay defaults are not widened. Each stage has its own budget. Failure stops
the sequence and returns accepted=false; the last attempted result is not
an accepted fallback. Check the wrapper's acceptance, not just the last solver
status or validate_joint_design in isolation.

Synthetic coverage exercises variable taps, banks and droop parameters,
full primal transfer, budget failure, corrupted returned physics, invalid
selections and finite log1pexp derivatives near saturation. Larger public
single-snapshot runs use fresh outputs and source-bound inputs. Historical
states are numerical hints that require new target-contract replay. Report the
accepted reserve floor and the evaluated demand/outage scope explicitly.

Use validate_staged_joint_design(case, r) to independently recheck the complete
sequence, original-limit replay, common reserve floor and handoff ledger.
The per-stage result.opf.objective records that stage's objective (zero, reserve,
or total Pg). The older joint_design_metrics objective comparison assumes the
ordinary dispatch-distance objective; use stage.loss_mw for staged loss reporting.
The reusable API is local and opt-in; no package release or consumer dependency
pin update has been made.

```@meta
CurrentModule = DroopOPF
```

```@docs
optimize_staged_joint_design
validate_staged_joint_design
```
