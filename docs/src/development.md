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

## Maintain the teaching documentation

Teaching pages introduce the electrical problem before the API and define each
symbol locally, with the common [notation reference](notation.md) as an index.
Use complete executed `@example` blocks for runnable tutorials; label partial
reference snippets as fragments. Give diagrams descriptive alternative text and
explain their assumptions in captions. Explain the assumptions of each illustrative calculation.

From the repository root, regenerate the nine deterministic SVG schematics and
check the rendered documentation:

```sh
python3 tools/docs/build_teaching_figures.py
julia --project=docs docs/make.jl
python3 tools/docs/check_teaching_docs.py docs/build
```

The docs environment must first be instantiated with the local package developed
into it. Its existing project/manifest describes the build dependencies. Review
the built pages visually, including curves, circuit signs and equation tables.
The link checker checks local targets/anchors and teaching-figure metadata; the
Documenter build executes tutorial assertions. Neither substitutes for reviewing
the physical meaning of a formula.
