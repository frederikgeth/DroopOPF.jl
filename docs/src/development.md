# Development

## Local checks

Run the package tests from the repository root:

```sh
JULIA_NUM_THREADS=2 OPENBLAS_NUM_THREADS=1 julia --project=. -e 'using Pkg; Pkg.test()'
```

Build the documentation locally:

```sh
julia --project=docs -e 'using Pkg; Pkg.develop(path = "."); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

The generated site is in `docs/build/`. Two Julia threads exercise the bounded
contingency worker tests; serial-only runs skip that concurrency branch.

## Continuous integration and deployment

`.github/workflows/CI.yml` runs the package tests on Julia `1.10` and `1.12`.
`.github/workflows/Documentation.yml` builds the docs for pull requests and
deploys the `main` documentation to GitHub Pages through
Documenter.jl.

The deployment workflow requires GitHub Pages to be enabled for the repository.
Documenter uses the repository `GITHUB_TOKEN`, so no deploy key is needed for
this same-repository deployment.

## Milestone and qualification records

Use the [milestone index](milestones.md) for navigation and the
[release scope](release_scope.md) for current qualification boundaries.
M1–M4 are historical implementation milestones; their original small-case
scale-up decision is not the current status. Sparse models, scenario addition,
parallel assessment and 14/500-bus studies now have bounded qualification.
General safe predictive skipping and full coupled resource/loss optimization
remain open. Original S2 remains paused; later P2 evidence is a separate campaign.

See the [validation references](validation_evidence.md) for selected numerical
results and figures, and [research evidence](research.md) for archived reports.
Package tests check software regressions; they do not rerun the large campaigns.
