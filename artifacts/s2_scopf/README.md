# S2 equipment-aware SCOPF qualification

The consolidated, artifact-generated scorecard, expanded tables, and figures
are in [qualification_report.md](qualification_report.md). Its machine-readable
source is `qualification_scorecard.json`.

S2 is separate from the frozen S1 base-case reliability investigation. It uses
the pinned PGLib v23.07 IEEE-118/300 fixtures, three terminal AVRs selected by
the released M8 Q-headroom rule, one recorded transformer, one non-islanding
line outage, and one low-impact generator outage per network. The stage worker
is `examples/s2_scopf_qualification.jl`; the resumable parent runner is
`examples/s2_scopf_orchestrator.jl`.

| Network | Solver | Direct M9.1 | Fixed seed | Staged M9.1 | M9.3 immediate / settled |
|---:|---|---|---|---|---|
| 118 | Ipopt | valid, `LOCALLY_SOLVED` | valid | valid | valid / valid |
| 118 | MadNLP | valid, `LOCALLY_SOLVED` | valid | valid | invalid (`ITERATION_LIMIT`) / invalid (`ITERATION_LIMIT`, power balance) |
| 118 | CCOpt | valid, `LOCALLY_SOLVED` | valid | valid | valid / valid |
| 300 | Ipopt | valid, `LOCALLY_SOLVED` | invalid, `TIME_LIMIT` | not run | direct-anchored: valid `ALMOST_LOCALLY_SOLVED` / physically valid but status-rejected `ITERATION_LIMIT` |
| 300 | MadNLP | valid, `LOCALLY_SOLVED` (checkpointed rerun) | external 180 s wall timeout | not run | direct-anchored: invalid / invalid (`ITERATION_LIMIT`) |
| 300 | CCOpt | physically valid, rejected `SLOW_PROGRESS` status (checkpointed rerun) | external 180 s wall timeout | not run | direct-anchored: invalid `ITERATION_LIMIT` / valid `ALMOST_LOCALLY_SOLVED` |

The IEEE-300 later-stage interruptions are runtime/checkpointing failures, not
infeasibility claims. Their original interruption records are retained. The
checkpointed reruns recovered the direct MadNLP and CCOpt evidence shown above.
The runner writes result/report files immediately after each completed stage.
The parent now starts every stage in a fresh Julia process, reuses independently
valid prerequisites, enforces a real wall clock even during non-interruptible
solver factorization, and records `*-process.json`, `*-worker.log`, and
`orchestration.json`. The isolated retry reconfirmed Ipopt's fixed-seed
`TIME_LIMIT` result as invalid. MadNLP and CCOpt produced no fixed-seed artifact
within 180 seconds and were terminated and classified explicitly as wall
timeouts, not infeasibility.

## IEEE-300 direct-witness recovery lane

This separate lane initializes the fixed-equipment problem from every scenario
of the direct M9.1 witness, rather than initializing only its base state from
the FreeQ anchor. It does not replace the declared fixed-seed lane.

| Solver | Outcome |
|---|---|
| Ipopt | invalid `TIME_LIMIT`; AVR and thermal residuals disappeared, but base and contingency power-balance residuals remained |
| MadNLP | external 180 s wall timeout; no result artifact |
| CCOpt | external 180 s wall timeout; no result artifact |

Thus direct-witness seeding alone does not unlock the IEEE-300 staged path.
CCOpt was allowed to use its direct point because independent replay established
physical validity even though its solver status was `SLOW_PROGRESS`; that status
remains rejected for qualification acceptance.

## Contingency-count homotopy and direct-anchored M9.3

For Ipopt, both contingency orders were tested on the unchanged final model.
The line-only fixed-equipment stage was independently physical but status
rejected; the generator-only stage was valid `LOCALLY_SOLVED`. Adding the second
contingency in either order ended at `TIME_LIMIT`, with only the line-outage
power-balance check remaining invalid. These are retained basin diagnostics and
do not replace the declared staged result.

M9.3 does not logically require the nominal-equipment staging lane when a direct
equipment-aware M9.1 base result already exists. A separate direct-anchored lane
therefore fixes that accepted base state and equipment setting, then solves the
immediate and corrective-settled policies independently. All three IEEE-300
solver assessments now have persisted paired artifacts. “Assessment complete”
means both results were assembled and reported; it does not mean both passed.

The accepted Ipopt base tap was about `1e-8` below its nominal lower bound while
inside the declared independent validation tolerance. The response study's
control envelope includes that exact saved base value so fixed-base replay is
well-defined; the setting and `0.005` corrective movement budget are unchanged.

This is an initial S2 matrix, not a completed reliability gate. Direct and
staged outcomes are reported separately, and no S1 score is changed.

## Frozen initial scorecard and expansion

The initial six-cell IEEE-118/300 scorecard is now frozen. The bounded
IEEE-300 Phase-I balance restoration does not close the staged lane: Ipopt
returns a positive-slack local result (maximum slack `0.001961` pu), followed by
an invalid exact retry; MadNLP and CCOpt produce no artifact within the external
180-second limit. None is an infeasibility certificate.

The phase-3 IEEE-118 expansion contains 29 completed cells covering tap-only,
shunt-only, joint and two-transformer-plus-shunt control; preventive and bounded
corrective timing; AVR and mixed AVR/Volt–VAr assignments; independent holdout
outages; and a +3% load profile with nominal control parameters retained. The
frozen direct matrix accepts 25/29 cells: Ipopt 14/15, MadNLP 7/7, and CCOpt
4/7. A bounded same-model warm retry from each retained scenario-state witness
recovers the physically valid Ipopt holdout to `LOCALLY_SOLVED`, giving 26/29
with declared retries. Stricter CCOpt retries retain the other three failures;
their exact-droop replay remains outside tolerance in the generator outage.
Original and retry artifacts are both retained and classified in the
consolidated report. The shunt is an
explicit continuous overlay replacing fixed shunt 34 at its identical supplied
state, not a claim that PGLib supplied a switchable bank.
