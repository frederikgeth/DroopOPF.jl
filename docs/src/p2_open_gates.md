# P2 open-gate continuation

This continuation uses `artifacts/p2_open_gates_20261022`, separate from the three
preceding sealed P2 campaigns. Its `RESULTS.json` and `REPORT.md` record the final
outcome. Existing finite-demand feasibility evidence remains valid; new numerical
methods do not retrospectively qualify an earlier failed attempt.

## Unchanged physical contract

The 500-bus case retains the exact S2 proportional-response compatibility model,
131 corrective taps and 11 continuous shunt controls, their absolute bounds and
no additional movement cap. The production limit-aware default is unchanged.
The 14-bus S1/S2 contract is unchanged. Original S2 remains paused.
A successful security witness requires native convergence and independent replay
of the original network, equipment, response, relief and operating limits.

## A necessary capacity filter

`examples/p2_s2_capacity_filter.py` derives an exact rational upper bound on the
common proportional-response signal from every surviving generator's active
bounds and movement allowance. Passive network losses are nonnegative. If the
largest possible surviving generation is below demand after conservatively
allowing all declared relief and numerical tolerances, that outage cannot be
served **with that preventive dispatch**. This is not a network-wide exclusion:
changing preventive dispatch can remove the deficit.

Unsupported response policies, explicit reactive assignments, nonpassive data
and inconclusive gaps fall back to exact assessment. The method never declares
an outage safe and does not qualify safe-outage skipping or general failure
recall. Qualification includes nine accepted demands (3,501 outage/demand pairs)
and separately validated stress dispatches. Production filtering is unchanged.

## Cold numerical preparation

The experimental sparse initializer starts outage voltages flat. It infers PV
voltage targets from preventive reactive dispatch and the inverse droop curves,
then can solve the actual saturated droop equations from that reconstructed
point. No saved post-outage state is used. The constrained native solve still
restores and enforces the original complete control and operating model.
Artificial-injection preparation is recorded separately and never accepted as a
security witness. Direct flat Ipopt failures remain failures of that method.

Repeated subset trials and a fresh connected-catalogue scan distinguish numerical
preparation from accepted physical solutions. Timings include preparation,
primary calls, retries and audits. Different budgets or methods do not support
a matched speedup claim.

## Full objective models and derivative preparation

`examples/p2_exhaustive_priorities.jl` attempts all 389 connected outages in every
objective stage: shedding, DR, normalized emergency departures, then base loss.
Each demand has its own free preventive dispatch. Previously qualified common
curves are frozen, permitting exact decomposition by demand. This is conditional
optimization; it does not establish an optimum over shared curve parameters.

A first-order evaluator avoids unnecessary exact Hessian preparation when
limited-memory optimization is selected. A scenario-partitioned evaluator
prunes each derivative graph and gathers/scatters shared variables. This remains
**one coupled NLP** with every original constraint and objective contribution.
It does not replace the model with independent outage optimizations.
Derivative, shared-expression, cross-scenario and coupled-optimum regressions
check the adapters; accepted engineering points require independent AC replay.
Interrupted preparations and unresolved native stages are retained.

## Compatibility and release evidence

Remote Ubuntu CI runs on an isolated `codex/p2-ci-20261022` branch. The snapshots
and workflow results identify exact tested commits. Test-only standard libraries
are declared explicitly for hermetic package tests. The outaged-equipment
regression uses smoothing continuation and tighter numerical convergence with
unchanged physical acceptance tolerances. No release tag or merge is published
by this qualification campaign.
