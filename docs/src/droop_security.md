# Droop design with contingency addition

## Physical and acceptance contract

The design variables are selected controllers' positive slopes (pu voltage per
pu reactive power), voltage references (pu), and nonnegative lower/upper
deadband widths (pu). One setting vector is shared by the base and every
training outage. Reactive capability and deadband output remain supplied data.
The existing saturated Volt–VAr law, AC balance equations, operating limits and
base schedule-deviation objective are unchanged. Each scenario has independent
AC states; an outaged generator has zero P/Q and no active controller equation.
Active response follows the Study participation/redispatch policy. Selected
taps and shunts retain their preventive/corrective bounds and movement budgets.

The smooth design NLP uses the existing SCOPF builder. Independent validation
reconstructs exact physical curves and checks the design bounds, AC physics,
outage availability and inter-scenario coupling. Fixed design bounds must
reproduce fixed-curve SCOPF; no contingencies must reproduce base-case design.
Multiple local optima may exist: objective agreement is an experimental check,
not a global-optimality assertion.

Contingency addition starts from a declared subset, solves a shared design,
recomputes screening at the new base/settings, assesses required outages, and
adds unresolved omitted outages. Solver rejection is unresolved evidence, not
proven infeasibility. Screening alone never permits successful termination:
every eligible outage receives a full AC audit at the final design. Islanding
entries remain explicit exclusions from the joint design and prevent a full
network N-1 claim. Iteration limits, failed masters and unresolved training
outages remain unsuccessful outcomes.

For controller j, with slope m_j, reference v_j and half-widths d_j^- and d_j^+,
the independently replayed response is

```math
Q_{j,c}=\operatorname{clip}\!\left(Q_j^0+
\frac{[v_j-d_j^- - V_{j,c}]_+}{m_j}-
\frac{[V_{j,c}-v_j-d_j^+]_+}{m_j},\ Q_j^{\min},Q_j^{\max}\right).
```

All design parameters are shared over c. The base objective remains

```math
\min \sum_g \left[(P_{g,0}-P_g^{\mathrm{initial}})^2
+10^{-3}(Q_{g,0}-Q_g^{\mathrm{initial}})^2\right].
```

For preventive active response, surviving generators obey
`P[g,c] = clip(P[g,0] + alpha[g,c]*signal[c], L[g,c], U[g,c])`,
with capability-aware weights renormalised over survivors and saturation allowing
remaining participants to take over. Zero-weight units hold base output. Corrective mode instead enforces the declared redispatch bounds.
The final audit holds the complete base AC state and base equipment settings
fixed; it never reoptimises a different base separately for each outage.

## API and reproducible runs

```julia
catalog = contingency_catalog(case)
base_study = Study(case; participation=participation)
controls = [DroopControl(1; slope_bounds=(0.04,0.08)),
            DroopControl(2; slope_bounds=(0.04,0.10))]
result = optimize_droop_security(base_study, controls;
    catalog, max_rounds=5, batch_size=1,
    initial_states=Dict(:base=>validated_base),
    solver_kwargs=(;smooth_epsilon=1e-5,
        optimizer_attributes=Dict("max_iter"=>1000,"max_cpu_time"=>30.0)))
write_droop_security("security.json", result)
```

Use `optimize_droop_parameters(study, controls)` for the corresponding full
training-set design. `validate_droop_design(study, design)` returns `valid`,
`policy_valid`, and the ordinary independent `report`. The scalar M3 interface
remains available and now preserves equipment policy during reconstruction and
held-out evaluation. Attached legacy droops and explicit reactive assignments
cannot be combined in this design interface; unsupported combinations reject
rather than silently dropping a controller policy.

`DroopSecurityResult.eligible_accepted` covers the supplied eligible catalog.
`full_n1_accepted` additionally requires the complete network catalog and no
excluded islands. A successful result contains a final exhaustive audit; a
failed master contains its validation outcome and never receives an inferred
security pass. `on_iteration` can checkpoint the entire round after assessment.
Independent assessment errors are retained, and added IDs use deterministic
error/violation ordering. The algorithm adds scenario constraints, not linear
cuts or a decomposition with convergence/global-optimality guarantees.

`sparse_balance=true` opts smooth OPF/SCOPF into omitting exact-zero admittance
terms even with droop controls. It changes expression sparsity, not equations.
Legacy controlled-case defaults remain unchanged because solver trajectories
can be sensitive to numerical representation. The public runner declares this
option and bounded solver settings in its protocol. Time limits apply during
optimization, not package loading or model construction.

The plotting runner requires Matplotlib. Public exhaustive campaigns use the
existing input-fingerprinted checkpoints; a changed case, source, policy or
solver budget requires a new directory. The subsequent design trace is retained
round-by-round but is not automatically resumable. Fresh design runs must use
fresh evidence directories if prior results are to be preserved.

To assess only branch contingencies (lines and transformers), retain the
original runs and use separate directories:

The branch-only catalog retains islanding branch outages in the exhaustive
campaign and excludes generator outages entirely. The joint design still
handles only connected outages. A successful eligible branch audit therefore
does not imply full-network N-1 acceptance. `retained/` saves the valid master
with the largest training set, then most independently accepted outages, then
lowest objective. Its acceptance manifest lists the exact coverage; a later
rejected master never replaces this candidate with an invalid design.
`optimized-study.json` and `master-result.json` use the public `read_study` and
`read_scopf_result` interfaces. The replay example verifies their round trip,
independently revalidates every saved accepted outage, and checks that all
witnesses use the identical retained base state. The comparison report also
checks that the original evidence files have not changed against the saved
`verification/pre-branch-preservation.json` manifest (run it from the repository
root).
The optional `--prior` replay exports accepted branch witnesses from an earlier
fixed-base campaign separately. It verifies matching study/base inputs and
revalidates the saved states; it does not re-solve them or count them as new
successful attempts.

## Initial measured evidence

The three-bus reference accepted all five N-1 outages. Two shared slope variables
converged in two design rounds: one line outage was added and all five outages
were independently audited. Full enumeration and iterative objectives differed
by approximately 2.1e-12. Cold-start rejection is retained separately from the
declared proportional-region base initialization.

The unchanged filter was then evaluated on 168 actual-droop outages across
24 inputs. It missed five unresolved discovery outages and seven held-out
outages (six lines and one transformer); all twelve missed states failed
physical replay. This **does not qualify screening as a security certificate**.
Held-out accepted states covered deadband, proportional response and Q-max
saturation; no accepted Q-min saturation point occurred in this partition.
The final exhaustive audit is therefore a required algorithmic acceptance gate.

See `artifacts/droop_security/reference/report.md` and
`artifacts/droop_security/filter/report.md` for saved inputs, numerical results,
iteration figures, filter coverage, ranking-budget curves and control regimes.

At half of each held-out input's evaluation budget, the diagnostic ranking
found 7/15 unresolved line outages and 11/21 generator outages; it has not yet
demonstrated useful prioritisation. See `artifacts/droop_security/report.md` for
the complete evidence and remaining qualification gates.
