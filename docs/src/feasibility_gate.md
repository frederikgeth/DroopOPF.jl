# Feasibility before droop replacement

```@meta
CurrentModule = DroopOPF
```

Use `qualify_droop_replacement` before accepting a proposed set of fixed droop
curves for S1. It checks the calibration point, then the source and candidate
models at every required demand factor. All candidate curves are present
together. A point that passes each generator separately does not establish that
the combined system is feasible.

| Decision | Evidence | Accept replacement? |
|:--|:--|:--|
| `feasible` | An operating point independently satisfies the original AC equations, exact droops and bounds within the frozen tolerances | Yes, if every required condition passes |
| `certified_infeasible` | A replayable global necessary-condition contradiction | No |
| `unresolved` | Neither a validated point nor a certificate | No |

Feasibility does not require an optimal objective or a successful optimizer
termination code. An iteration-limited result can contain a valid witness.
Conversely, `LOCALLY_INFEASIBLE`, a failed multistart campaign, and a positive
local Phase-I objective do not prove that no feasible operating point exists.

## Contract and independent replay

`FeasibilityProblem` copies and fingerprints the entire case: topology,
availability, demand, generator limits, voltage and thermal limits, exact droop
knots, fixed equipment settings, selected equipment bounds, optional branch
angle limits and all validation tolerances. Changing any of these requires a new
qualification. Mutation of a frozen snapshot raises an error. Solver settings
and the search objective are recorded with attempts; they do not change the
physical feasible set.

`write_feasibility_result(path, problem, result)` saves the full contract and
evidence. `read_feasibility_result(path, problem)` requires the expected contract,
rejects stale scope, and replays the saved witness or certificate before reuse.

Taps and shunts default to their fixed source settings. A witness must include
the actual settings of selected equipment. Only selected banks may move; their
optimization is continuous susceptance optimization, not discrete switching.
The checker reconstructs those settings, then checks AC balance, both branch
terminals, voltage, generator P/Q, unavailable generation, exact droop Q,
controller P limits, reference angles and supplied branch angle limits.

`Branch` does not currently store angle-difference limits. Supply source-case
limits through `angle_limits=Dict(branch_id => (min_radians,max_radians))` when
they belong to the required problem. These limits are enforced in the local
search as well as independent replay.

## Usage

```julia
qualification = qualify_droop_replacement(source_case, candidate_case;
    calibration_state = source_opf_state,
    load_factors = (1.0, 0.9),
    initial_states = [source_opf_state, source_90_state],
    witnesses = Dict("source/0.9" => [FeasibilityWitness(source_90_state)]),
    problem_options = (angle_limits = source_angle_limits,),
)
write_droop_qualification("qualification.json", qualification)
accepted_case = require_qualified_replacement(qualification)
# Downstream S1 analysis uses accepted_case; this line is unreachable on failure.
```

The calibration checks are replay-only: a local solve cannot hide a droop curve
that misses the intended source point. Subsequent checks replay supplied points
first, run analytical exclusion checks, and then optionally attempt a constant
zero-objective local feasibility search. The search changes no droop parameters
or unselected equipment. Set `search_options=(solve_missing=false,)` for an
evidence-only replay.

`require_qualified_replacement` rechecks every witness and fingerprint before
returning a copy of the candidate. Do not bypass it in an acceptance workflow.
Low-level case constructors and solve functions remain available for diagnostics
and intentionally infeasible experiments; they are not acceptance APIs.

To qualify one individual replacement or a cumulative sequence, construct that
candidate and call this same precursor at each step. Qualification of a previous
candidate does not transfer to a changed set of curves.

## What can currently be certified globally

The built-in certificate path uses exact rational arithmetic on stored input
numbers and includes the declared feasibility tolerances. It checks:

- Active generation capacity versus demand in every connected component. It
  ignores passive losses and shunt consumption, making this a necessary bound.
- Reachable exact droop-Q intervals over allowed regulated-bus voltages.
- Nodal reactive-power balance using these intervals, fixed/selected shunt
  bounds and the maximum reactive flow allowed by each terminal's thermal rating.

These are conservative outer bounds: a contradiction excludes all original
feasible operating points. Certificates store their exact rational lower and
upper bounds and are recomputed when reused. A solver's status is never imported
as a certificate.

The default analytical path is incomplete. Optional
[global escalation](global_feasibility.md) adds a sparse outer LP with exact
certificate replay, verified voltage-bound tightening, a sparse SOC relaxation,
and bounded numerical global search with all droop regions. These backends are
opt-in through `lp_options` and `global_options`; routine feasible-point replay
does not launch them. An inconclusive backend or unsupported equipment scope
remains unresolved. Solver-reported global bounds alone do not qualify as
independently verified certificates.

## Current 14-bus reproduction

Run `examples/s1_arpae14_feasibility_gate.jl` to qualify the corrected four-percent
droops, with and without deadband, at 100% and 90% demand. The script uses fixed
source taps/shunts for acceptance and preserves the saved source solutions. It
also replays the existing free-equipment witnesses under their own contracts and
checks that they cannot pass the fixed-equipment gate. Results, frozen inputs,
witnesses and attempt records are written to
`artifacts/s1_arpae14_feasibility_gate/`.

The reproduced results are:

| Model | 100% demand, fixed equipment | 90% demand, fixed equipment | 90% demand, saved free-equipment witness |
|:--|:--|:--|:--|
| Source AC OPF, no droop replacement | Feasible | Feasible | Not required |
| Fixed 4% droops with deadband | Feasible | Unresolved | Feasible |
| Fixed 4% droops without deadband | Feasible | Unresolved | Feasible |

Both candidate replacements are blocked for the combined 100%/90% fixed-equipment
scope. No global infeasibility certificate has been obtained for either 90%
case. Free-equipment witnesses are rejected under the fixed-equipment contract.

This precursor qualifies independent S1 equilibria. Separate scenario witnesses
do not establish a common preventive dispatch or shared equipment setting for
S2. A coupled SCOPF qualification requires the corresponding shared/corrective
control policy and movement budgets; this implementation does not claim that
certificate and the example starts no SCOPF runs.

## API

The canonical docstrings are in the [API reference](api.md):

- [`FeasibilityProblem`](@ref)
- [`FeasibilityWitness`](@ref)
- [`FeasibilityResult`](@ref)
- [`DroopQualification`](@ref)
- [`feasibility_fingerprint`](@ref)
- [`validate_feasibility_witness`](@ref)
- [`check_feasibility`](@ref)
- [`verify_feasibility_result`](@ref)
- [`write_feasibility_result`](@ref)
- [`read_feasibility_result`](@ref)
- [`qualify_droop_replacement`](@ref)
- [`require_qualified_replacement`](@ref)
- [`write_droop_qualification`](@ref)
