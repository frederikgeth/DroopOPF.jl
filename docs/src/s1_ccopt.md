# S1 CCOpt pilot

CCOpt is now included as a separate S1 pilot backend. It is not included in the
frozen Ipopt/MadNLP acceptance counts. The pilot uses exact complementarity
droop with the same continuous tap, simple-bank and bounded droop-parameter
model, objective and independent validation.

The adapter records cumulative inner MadNLP iterations, final relaxed-NLP
primal and dual feasibility, complementarity feasibility, relaxation range,
model size, timing and allocations. CCOpt's MOI wrapper does not expose a
separate outer-homotopy count or budget, so the declared per-attempt budget is
1000 cumulative inner iterations and 60 native wall seconds. Final dual
feasibility is not claimed as an original-MPCC stationarity certificate.

| Configuration | Valid | Result |
|---|---:|---|
| Synthetic joint tap/shunt/droop | 2/2 | Exact solutions agree across starts |
| IEEE 118 fixed equipment, exact fixed droop | 2/2 | Both validate |
| IEEE 118 one-free-tap/bank/droop, standard accuracy | 0/2 | Solver converges, but exact-droop residual is `3.86e-5` and fails the unchanged `1e-5` gate |
| Same joint case, labelled tighter follow-up | 2/2 | Exact-droop residual falls to `3.86e-7` without changing the physical model or acceptance tolerance |
| IEEE 300 fixed equipment, exact fixed droop | 2/2 | Both validate |
| IEEE 300 one-free-tap/bank/droop, standard accuracy | 2/2 | Both validate |
| Same IEEE 300 joint case, tighter settings | 2/2 | Both validate; retained as a matched accuracy comparison |

The standard failures remain part of the evidence. The tighter follow-up uses
`tol=acceptable_tol=1e-11` and a proportional relaxation floor of `1e-14`;
it is not silently substituted into the original attempts. This establishes a
workable public-case pilot and also shows why complementarity products alone
cannot replace independent exact-curve validation.

Reproduce with:

```sh
julia --project=. examples/s1_ccopt_pilot.jl artifacts/s1_ccopt_pilot
```

The retained report and machine-readable summary are written under
`artifacts/s1_ccopt_pilot`.

## Matched control-family matrix

`examples/s1_ccopt_matrix.jl` extends the pilot to the frozen tighter accuracy
profile across fixed, single-family, pairwise and joint controls, three starts,
nominal and +5% load, and IEEE 118/300. It checkpoints after every attempt and
skips retained names when restarted. The report labels partial runs explicitly;
an interrupted run is resumed with the same command rather than discarded.

The currently retained partial matrix contains 78 of 96 attempts. IEEE 118 and
IEEE 300 nominal-load slices both validate 24/24. On stressed IEEE 118, the
fixed, droop, shunt and shunt--droop families validate 12/12, while all 12 cases
containing the selected tap are rejected: most converge numerically but miss
the unchanged exact-droop tolerance, and two reach the iteration limit. The six
completed stressed IEEE 300 fixed/droop attempts all reach the iteration limit.
The remaining stressed IEEE 300 families are not yet evidence and must not be
treated as failures.

Each retained matrix row now also records a per-controller direct exact-droop
audit. The physical criterion is `1e-5` pu. The converged stressed IEEE 118
tap-containing points miss it narrowly (`1.61e-5` to `1.70e-5`, or roughly
1.6--1.7 times the criterion); their complementarity products alone are not a
substitute for acceptance. Iteration-limited points are qualitatively different:
the current worst IEEE 118 tap--shunt flat-high iterate has `4.29e-2` pu
residual (4292 times the criterion), and the currently retained IEEE 300 +5%
fixed/droop iterates have residuals up to `3.72` pu. Those nonconverged states
are diagnostic artifacts, not candidates for overwriting or accepting.

```sh
julia --project=. examples/s1_ccopt_matrix.jl artifacts/s1_ccopt_matrix
```

## IEEE 118 placement-controlled diagnostic

The first selected IEEE 118 tap has a fixed droop at its 345-kV terminal; the
first selected bank is colocated with a different fixed droop. To avoid
confounding a placement effect with a changed network, a 12-attempt diagnostic
keeps the same overlay, +5% load, three starts, exact-complementarity model and
tight CCOpt budget, changing only the one free tap or bank location.

| One free control location | Valid | Result |
|---|---:|---|
| Tap with terminal droop (branch 8) | 0/3 | All converge but miss exact-droop acceptance by at most 1.66 times the criterion |
| Tap without terminal droop (branch 36) | 2/3 | Anchor and flat-low validate; flat-high reaches the iteration limit |
| Bank colocated with a droop (bus 59) | 3/3 | All validate |
| Bank remote from droops (bus 76) | 1/3 | Two flat starts reach the iteration limit |

This is not evidence to relocate equipment or alter topology. It identifies
placement/start sensitivity for the next numerical investigation. The retained
`artifacts/s1_ccopt_placement/report.md` contains the per-controller
exact-droop audits.

## Frozen S1 lane

`examples/s1_ccopt_policy_matrix.jl` provides CCOpt's frozen-test counterpart:
the same 12 public cells as the established Ipopt/MadNLP policy matrix (IEEE
118/300, nominal/+5% load, and anchor/flat-low/flat-high starts), using the
same public overlay and complete tap/shunt/droop policy set. Each cell retains
the serialised design, solver diagnostics, direct exact-droop audit, source
audit, and a stable context hash.

CCOpt is evaluated under its declared native direct profile: exact
complementarity, 1000 inner iterations and 60 seconds per cell, with
`sigma_min=1e-14` and `tol=acceptable_tol=1e-11`. This gives identical test
coverage and acceptance evidence, but does not pretend that CCOpt supports the
Ipopt/MadNLP multiplier-reset policy: its MOI interface exposes neither a
portable dual-reset operation nor a separate outer-homotopy counter.

```sh
julia --project=. examples/s1_ccopt_policy_matrix.jl artifacts/s1_ccopt_frozen
```

The resulting `report.md` is the human-readable frozen record and
`summary.json` is the machine-readable counterpart. It records failed cells as
evidence; no profile is silently replaced by the experimental tighter polish.
