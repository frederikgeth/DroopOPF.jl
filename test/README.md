# Test suites

The default `julia --project=. -e 'using Pkg; Pkg.test()'` runs all retained core and extended tests. CI keeps this full gate.

For core development checks, use `DROOPOPF_TEST_SUITE=core julia --project=. test/runtests.jl`.

Core coverage retains physics, derivatives, default behavior, formulation equivalence, operating limits, persistence, validation, and synthetic OPF/SCOPF integration. The extended section retains solver restart, seed transfer, staged release, diagnostic reporting and research policy checks using small deterministic fixtures. Tests were moved by purpose; none of this retained coverage was removed because of assertion count.

The 14/500-bus numerical campaigns are example-level evidence, outside the package unit suite. Their closeout profile and saved-state replay are documented in `docs/src/s1_closeout.md`.
