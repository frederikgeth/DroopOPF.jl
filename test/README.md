# Test suites

The default `julia --project=. -e 'using Pkg; Pkg.test()'` runs all retained core and extended tests. CI keeps this full gate.

For core development checks, use `DROOPOPF_TEST_SUITE=core julia --project=. test/runtests.jl`.

Core coverage retains physics, derivatives, default behavior, formulation equivalence, operating limits, persistence, validation, and synthetic OPF/SCOPF integration. The extended section retains solver restart, seed transfer, staged release, diagnostic reporting and research policy checks using small deterministic fixtures. Tests were moved by purpose; none of this retained coverage was removed because of assertion count.

The 14/500-bus numerical campaigns are example-level evidence, outside the package unit suite. Their closeout profile and saved-state replay are documented in `docs/src/s1_closeout.md`.

The ordinary package suite includes common case IO contract tests without
installing PowerIO. PowerIO integration uses a separate environment:

```sh
julia --project=test/powerio -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=test/powerio test/powerio/runtests.jl
```

That suite uses real PowerIO parsing/writing, independent transformer
expectations, native/PowerIO round trips, state/provenance checks, destination
failure checks and fresh-process extension load orders. CI runs both suites
on Julia 1.10 and 1.12; native library failures fail integration tests.

CI pins PowerIO 0.11.7 and explicitly requires two profiles on both Julia
versions. The default `released` profile requires the known guards. The
`corrected` profile builds the exact upstream source and test-only patch
documented in [powerio/support/README.md](powerio/support/README.md), then
requires both corrected capabilities. This is validation infrastructure and
does not patch the user's dependency or select a production library.

To test a corrected local PowerIO library, set `POWERIO_CAPI` to its shared
library path and `DROOPOPF_POWERIO_TEST_PROFILE=corrected` before running the
integration command. The suite checks both
RAW transformer basis qualification and dictionary frequency preservation;
the released 0.11.7 binary must retain its rejection paths, while a corrected
build exercises the full transformer matrix and 50 Hz RAW exports.
The small OPF smoke test validates independently replayed residuals. With a
corrected library it also exports a solved 50 Hz static snapshot and checks
that file through the native saved-state validator.
