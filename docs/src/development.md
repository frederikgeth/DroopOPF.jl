# Development

## Local checks

Run the package tests from the repository root:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

Build the documentation locally:

```sh
julia --project=docs -e 'using Pkg; Pkg.develop(path = "."); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

The generated site is in `docs/build/`.

## Continuous integration and deployment

`.github/workflows/CI.yml` runs the package tests on Julia `1.10` and `1.12`.
`.github/workflows/Documentation.yml` builds the docs for pull requests and
deploys the `main` and tagged-version documentation to GitHub Pages through
Documenter.jl.

The deployment workflow requires GitHub Pages to be enabled for the repository.
Documenter uses the repository `GITHUB_TOKEN`, so no deploy key is needed for
this same-repository deployment.

## Roadmap

The staged development plan is maintained in
[`ROADMAP.md`](https://github.com/frederikgeth/DroopOPF.jl/blob/main/ROADMAP.md):

- M1: AC OPF with generator volt-var droops — complete in `0.1.0`;
- M2: security-constrained AC OPF;
- M3: optimization of generalized droop curves.
