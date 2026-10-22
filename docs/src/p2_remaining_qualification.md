# Remaining P2 qualification attempts

The subsequent [open-gate continuation](p2_open_gates.md) records newer CI,
capacity-filter, initialization and full-objective work. Outcomes below describe
this earlier sealed campaign.

The 22 October 2026 continuation attempts the remaining held-out, initialization,
ranking/filtering, comparative performance and regression gates. Fresh outputs
live in `artifacts/p2_remaining_qualification_20261022`; the final `REPORT.md` and
`RESULTS.json` distinguish passage, bounded evidence and unresolved work.
Original S2 and preceding sealed P2 evidence remain separate.

## Frozen-controller evaluation

The 14-bus controller comes from the accepted five-demand full master. Evaluation
demands are 92.5/97.5/102.5/107.5%, with all 24 connected outages at each demand.
The 500-bus controller is the accepted common S2 controller through 106.25%;
evaluation demands are 92.5/97.5/102.5/105.625%, with all 389 connected outages at
each demand. Curves are never retuned on these points. Preventive dispatch may
adapt to each demand, and the exact S2 corrective continuous equipment contract
remains available. This evaluates curve generalization under declared corrective
control, rather than fixed-equipment operation.

The 500-bus policy permits the original S2 emergency limits, DR and up to 10 MW
shedding per outage. The 14-bus policy retains normal limits and no relief. Both
retain absolute selected-equipment bounds without extra movement budgets and
S2's stored proportional response equation. The production limit-aware default
is unchanged. Acceptance requires native solver success and independent
original-network AC, exact-droop, equipment, response and relief replay.

## Measurements and scope

Initialization tests use deterministic mixed samples (10 outages on 14 buses and
11 on 500 buses), and rotate flat voltage, validated base, neighbouring outage
and matching accepted outage starts. The matching state is a strong numerical
reference, not unseen-start evidence. All comparisons retain the same fixed base,
curves and constraints. One warm-up is excluded and three repetitions retained;
failed calls remain in the timing denominator. Wall time includes build, solve,
serialization and independent replay. Process peak RSS is cumulative, while Julia
allocation counts are cumulative allocations rather than resident memory.

Matched enumeration comparisons use the complete 14-bus connected catalogue and
a deterministic mixed 12-outage subset on the full-size 500-bus network. A separate
500-bus 12-outage experiment compares full and progressive fixed-curve designs,
including every scan cost. These bounded references do not establish equivalence
of full-catalogue free-curve optimization or a universal speedup.

Filtering under corrective equipment and the S2 proportional response lies outside
the response guard's existing qualification contract. Advisory decisions are
recorded, but operational routing retains every exact solve. All-pass references
contain no failure examples from which to estimate failure recall. Any relief
ranking measurement is descriptive of the saved witnesses, not minimum required
relief or a certified failure predictor.

A bounded fixed-curve resource pilot attempts shedding, DR, normalized emergency
departures and then base loss on five outages. Earlier accepted resource totals
bound later stages. This is distinct from exhaustive multi-demand priority
optimization. Numerical failures remain unresolved and are retained.

The local Julia 1.12 and compatible Julia 1.10 checks are reported separately from
remote Ubuntu CI. A manifest built for a different Julia version is not treated
as a source regression. ExaModels and distributed decomposition remain conditional
engineering choices; no backend is added merely to bypass numerical failures.

## Outcome

All four held-out demands passed on each network. Combined with the original
training evidence, identical curves are qualified at nine sampled demands:
225 states on 14 buses and 3,510 on 500 buses. The 500-bus set retains S2's
shedding allowance; the 14-bus set permits no relief.

Three fresh exhaustive 500-bus evaluations passed 389/389 outages each. A repeated
native numerical error required singleton evaluation and a base-start fallback.
Total active wall times, including deferred recovery segments, were approximately
328/324/325 seconds. A physically valid point with native numerical failure was
never counted as accepted.

All three measured repetitions passed both full/progressive references: the
14-bus five-demand free-curve loss design, and the fixed-curve 500-bus 12-outage
feasibility reference. Full enumeration was faster in these design references:
median 11.60 versus 18.28 seconds on 14 buses, and 8.27 versus 10.62 seconds in
the 500-bus subset. The latter is not a 389-outage joint-optimization comparison.
The 14-bus local objective differences were about 0.000006%; this is numerical
agreement of local solutions, not a global optimality proof.

Matching-scenario, base and neighbouring starts passed all measured trials.
Flat starts passed on 14 buses but failed the 500-bus batch and singleton retry
budgets. A separately recorded base-start fallback recovered all three failed
workflows; its timings include failed flat calls. Pure flat initialization remains
unqualified. A missing neighbouring-transformer start was repaired by filling
missing settings from the preventive base; the aborted original measurements
remain archived and the comparison was restarted.

Routing diagnostics screened zero outages on both networks. All-pass references
cannot establish failure recall. Filtering remains optional and receives no new
predictive guarantee. The five-outage resource pilot completed shedding, DR,
emergency-proxy and loss stages with native/physical acceptance and independently
checked earlier-resource caps. It does not complete exhaustive multi-demand
resource/loss optimization or certify minimum relief.

Both local Julia versions passed 3,147 regression checks. The independent fresh
campaign replay verified 951 accepted and 92 unresolved native attempts, retaining
failed intermediate designs. Six deliberate evidence corruptions were rejected.
Remote Ubuntu CI has not run. P2 remains open for broader predictive and full
resource-objective qualification; ExaModels and distribution remain conditional.

## Reproduce

In a compatible Julia project environment, choose a fresh absolute output path
before importing the runner:

```julia
ENV["P2_QUALIFICATION_OUTPUT"] = "/absolute/path/to/fresh-p2-qualification"
include("examples/p2_remaining_qualification.jl")
pq_remaining_run()
```

The runner never launches work on import and refuses an existing campaign root.
It requires the retained exact S2/P2 training inputs. Set the same environment
variable for `examples/audit_p2_remaining_qualification.py`,
`examples/p2_ranking_measurements.py`, `examples/p2_combined_coverage.py`,
`examples/test_p2_remaining_audit.py`, and
`examples/report_p2_remaining_qualification.py`. Runtime snapshots distinguish
preparation repairs and deferred recovery from the initial execution.
