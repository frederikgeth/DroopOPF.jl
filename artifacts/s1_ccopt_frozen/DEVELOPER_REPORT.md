# CCOpt 0.1.0: frozen S1 reproduction report

## Scope

This is a reproducible numerical-robustness report, not a claim that CCOpt has
an incorrect formulation.  The model is an AC OPF with continuous transformer
tap ratios, continuous shunt-bank susceptances, and bounded voltage--reactive
power droop parameters. Droop is represented with CCOpt's exact piecewise
linear complementarity encoding.  Physical acceptance is independently checked
against the direct piecewise curve, with an unchanged `1e-5` pu criterion.

## Environment and reproduction

- Repository base revision: `89660d72fb07d4043c73b9757370c6223cd4ca65` on branch
  `transformers`, with the CCOpt runner and audit instrumentation present as
  uncommitted working-tree changes (include `git diff` when sharing externally).
- CCOpt: `0.1.0` (`Manifest.toml` tree `39279f2e144df6253cc78cdaa19886d6e29364de`).
- Command: `julia --project=. examples/s1_ccopt_policy_matrix.jl artifacts/s1_ccopt_frozen`
- Runner: [`examples/s1_ccopt_policy_matrix.jl`](../../examples/s1_ccopt_policy_matrix.jl).
- Native profile per cell: `max_iter=1000`, `max_wall_time=60`, proportional
  relaxation `sigma_min=1e-14`, and `tol=acceptable_tol=1e-11`.

The matrix contains the same 12 public cells as the frozen Ipopt/MadNLP matrix:
IEEE 118/300, nominal/+5% load, and anchor/flat-low/flat-high starts. The
runner checkpoints every completed cell and retains the design, complete
diagnostic record, CCOpt encoding audit, and direct physical droop audit.

## Result

Two of 12 cells were accepted by all solver, policy, AC-physical, and direct
exact-droop checks:

| Cell | Status | Exact droop residual |
|---|---|---:|
| IEEE 118, nominal, flat-high | `LOCALLY_SOLVED` | `5.442e-6` |
| IEEE 118, +5%, anchor | `LOCALLY_SOLVED` | `3.790e-6` |

The other 10 reached `ITERATION_LIMIT` (nine cells) or `TIME_LIMIT` (one IEEE
300 nominal anchor cell). Their direct exact-droop residuals range from
`1.053e-2` to `7.498e-1` pu, so they are correctly rejected rather than being
near-threshold candidates. The full per-cell record is [`report.md`](report.md)
and [`summary.json`](summary.json).

## Accuracy observation motivating discussion

In a separate, converged IEEE 118 terminal-tap diagnostic, CCOpt reported a
small complementarity product (`9.09e-13`) and relaxed-NLP primal/dual metrics
of similar size, yet the independently evaluated exact droop curve missed the
physical criterion by `1.663e-5` pu. The encoding audit attributes this to a
`1.109e-7` hinge discrepancy, amplified by the droop slope; it is not a
reactive-power projection/extraction discrepancy. Tightening to
`sigma_min=1e-16`, `tol=acceptable_tol=1e-13` lowered that direct residual to
about `1.67e-7`, but did not reliably improve the complete placement matrix.

Relevant retained evidence: [`../s1_ccopt_polish/summary.json`](../s1_ccopt_polish/summary.json),
[`../s1_ccopt_placement/report.md`](../s1_ccopt_placement/report.md), and
[`../s1_ccopt_placement_encoding/report.md`](../s1_ccopt_placement_encoding/report.md).

## Conditional-feasibility follow-up

The frozen harness includes a checkpointed droop-only feasibility ladder:

```sh
julia --project=. examples/s1_ccopt_droop_feasibility.jl \
  artifacts/s1_ccopt_frozen artifacts/s1_ccopt_droop_feasibility
```

For every frozen cell without a witness, it fixes taps and shunts to an
admissible anchor design (and, for IEEE 118, each accepted CCOpt witness) while
optimizing exact PWL droops. A validated result proves a local feasible witness
for the original joint problem; a failed reduced solve remains unknown and is
not presented as an infeasibility result.

The resulting case-level status is summarized in
[`FEASIBILITY_STATUS.md`](FEASIBILITY_STATUS.md): IEEE 118 at both loads and
IEEE 300 nominal have validated local witnesses. IEEE 300 at +5% remains
unknown; the retained failures are termination evidence, not an infeasibility
certificate.

A 1%-increment continuation from the validated IEEE 300 nominal droop-only
witness also stopped at the first step (load factor 1.01), at the 1000-iteration
cap with a direct exact-droop residual of `2.368e-1` pu. This is retained in
[`../s1_ccopt_300_continuation/report.md`](../s1_ccopt_300_continuation/report.md).
It is evidence of a continuation/termination robustness issue, not an
infeasibility certificate.

## Questions for the CCOpt maintainers

1. Is there a recommended CCOpt termination/relaxation configuration for
   accurate primal recovery of PWL complementarity variables when the physical
   residual is more stringent than the relaxed-NLP feasibility metric?
2. Can the MOI interface expose a reliable outer-homotopy iteration count and
   a portable warm-start/reset pathway, or is a direct `NLPModels` route the
   appropriate interface for this experiment?
3. Is the observed hinge-error amplification expected at the reported
   relaxation level, and is there a recommended post-solve feasibility-polish
   procedure that preserves the original MPCC semantics?
