# Security-constrained AC OPF (M2)

M2 jointly optimizes one base dispatch and a fully enumerated set of line and
generator outages. Droop settings remain fixed across scenarios. Each scenario
has its own AC voltages, angles, active generation, and reactive generation.
This is a small-network reference formulation, with no screening or decomposition.

## Response contract

All active/reactive powers and redispatch limits are per-unit on `case.base_power`;
voltage magnitudes are per-unit and angles are radians. Positive P/Q means network
injection. The reference bus fixes only its angle; it does not supply unbounded
balancing power. All available generators retain their capability bounds.

Preventive mode uses a base schedule and a prescribed automatic balancing policy:

```math
P_{g,c} = P_{g,0} + \alpha_{g,c}\Delta_c,\qquad
\alpha_{g,c}=\frac{w_g}{\sum_{h\text{ available in }c}w_h}.
```

Participation weights are supplied explicitly, must be nonnegative, and are
normalized over surviving generators. Unlisted generators have zero weight.
Every contingency needs a surviving participant. The scalar `Δ` represents
active power needed for lost generation and changes in AC losses. It is **not a
frequency deviation** or a dynamic governor model. Participants must remain
within their bounds; there is no automatic redistribution when one saturates.
Optional `redispatch_limits` also bound each participant's change from base.

Corrective mode replaces this participation equation with:

```math
-r_g \le P_{g,c}-P_{g,0}\le r_g.
```

`redispatch_limits[g]` supplies the finite, nonnegative symmetric bound `r_g`.
An omitted generator has zero permitted redispatch. This represents controlled
post-contingency redispatch, without a time or ramp-rate model. Participation
weights are rejected in this mode to avoid an ambiguous policy.

In both modes:

- Unavailable generators inject zero P/Q and their droop equation is omitted.
- Unavailable branches contribute neither admittance nor flow.
- Available controlled generators obey their fixed `Q(V)` relation at the
  declared regulated bus in each scenario. No voltage setpoint is optimized.
- Generators without a droop attachment retain M1's independently adjustable Q
  within capability limits. Attach controls to every unit when autonomous
  volt-var equilibrium is the intended experiment.
- Loads, branch ratings, and voltage limits are unchanged across scenarios.
- Disconnected base networks and islanding contingencies are rejected before solving.
- Reactive capability is M1's constant Q interval with a permitted P interval;
  a curved P-dependent capability boundary remains outside this implementation.

The objective is the existing M1 base schedule-deviation objective:

```math
\min \sum_g (P_{g,0}-P_g^{\rm initial})^2
       + 10^{-3}(Q_{g,0}-Q_g^{\rm initial})^2.
```

Contingency states impose feasibility constraints without an additional cost.
Consequently, corrective dispatch can be nonunique. This is not an economic
SCOPF cost model. With no contingencies, the problem reproduces M1.

## Solve and evaluate

```julia
study = Study(case;
    contingencies = [
        Contingency(:line_22; branch_ids = [22]),
        Contingency(:generator_9; generator_ids = [9]),
    ],
    participation = Dict(7 => 1.0, 9 => 1.0),
)
result = solve(study)
report = equilibrium_report(study, result)
println(markdown_report(report))

# Assess an existing base equilibrium without changing its dispatch or voltage.
evaluation = evaluate_contingencies(study, result.states[:base])

# Alternatively, allow bounded corrective redispatch.
corrective = Study(case; contingencies = study.contingencies,
    mode = :corrective, redispatch_limits = Dict(7 => 0.8, 9 => 0.8))
corrective_result = solve_scopf(corrective)
```

IDs refer to device IDs, not array positions. State vectors retain original case
order, including zero entries for outaged generators. Results use `:base` and the
contingency IDs as dictionary keys. No state is silently treated as feasible:
a failed solve may return an infeasible iterate, or `nothing` if none is available.
During fixed-base evaluation, the supplied base is independently validated but
is not rebuilt as a redundant set of fixed equations in the NLP.

The default solver is Ipopt. `optimizer_factory=MadNLP.Optimizer` uses the same
smooth formulation. `encoding=:complementarity` selects CCOpt and the exact PWL
formulation; omit `optimizer_factory` for this encoding. Solver options are
passed through `optimizer_attributes`.

`solve_scopf_continuation(study; smooth_epsilons=[1e-2,1e-3,1e-4])` returns the
sequence of results, warm-starting all scenario states. It stops after solver
failure or a missing state. Independently validate the final result. For other
initial points, pass a dictionary through `initial_states` to `solve_scopf`.

## Independent acceptance checks

`equilibrium_report(study, result)` rebuilds the outage cases and checks AC
balance, both ends of branch flows, generator and voltage limits, exact droop
replay, disabled generators, reference angles, and response-policy coupling.
The report records tolerances and scenario-specific failures.

- `physical_valid` requires exact-curve equilibrium and all physical/coupling checks.
- `encoded_physical_valid` checks the numerical droop encoding in place of exact replay.
- `valid` additionally requires a successful solver termination. For a fixed-base
  evaluation with no contingencies there is no optimization; status is `:NOT_RUN`
  and independent feasibility alone determines validity.

The report lists exact and encoded droop residuals separately, along with their
smoothing gap. Default power/limit/coupling tolerances are `1e-6`, exact and
encoded droop tolerance is `1e-5`, and unavailable-generator tolerance is `1e-8`.
Tolerances are explicit keyword arguments. These checks certify only the
reported equilibrium to those tolerances, not global optimality, uniqueness,
transient stability, or frequency response.

## Reproducibility

Run from the repository root:

```sh
julia --project=. examples/m2_workflow.jl /tmp/droopopf-m2
```

The example writes a study, result, and validation report as JSON, plus a Markdown
report. It reloads the JSON files, independently validates the restored result,
and deliberately corrupts an outage result to demonstrate rejection.

```julia
write_study("study.json", study)
write_scopf_result("result.json", result)
write_scopf_report("report.json", report)
restored_study = read_study("study.json")
restored_result = read_scopf_result("result.json")
restored_report = equilibrium_report(restored_study, restored_result)
```

JSON documents use schema version 1 and a document-kind tag. Study files contain
all case data, contingencies, and the response policy. Result files contain
scenario states, balancing powers, solver/status, encoding, and smoothing widths.
Nonfinite diagnostics are written as JSON `null`; missing states remain `null`.
Report files are diagnostic exports; reports are regenerated from study/results,
not trusted as proof of validity. Save the Julia project/manifest alongside an
experiment when exact dependency versions matter.
