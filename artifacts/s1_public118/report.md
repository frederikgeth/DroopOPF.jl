# Public IEEE 118-bus fixed-equipment baseline

The unmodified [PGLib v23.07 IEEE 118 source](https://raw.githubusercontent.com/power-grid-lib/pglib-opf/v23.07/pglib_opf_case118_ieee.m) imports as **118 buses, 54 generators, 186 branches and 14 fixed shunts**. Its preserved header contains attribution and CC BY 4.0 licensing. [Provenance](../../test/data/pglib/v23.07/provenance118.json) records SHA-256 b1af0833849040c04babc3700631cff0d9afa66b79c5d3e13ae79bdf516cec78.

The solve terminates **LOCALLY_SOLVED** and passes independent AC and operating-limit validation. No droops, adjustable banks or optimized ratios have been added. This is a public fixed-equipment baseline, not a public joint-design scalability result.

| Check | Result |
|---|---|
| Maximum AC balance residual | 1.280e-09 pu |
| Minimum voltage lower/upper margin | 5.915e-02 / 9.312e-12 pu |
| Minimum both-terminal branch margin | 1.081e-01 pu |
| Post-solve source angle violation | 0.000e+00 degrees |
| Iterations | 21 |
| Objective | 7.621127051 |

The initial import retained only one generator: splitting on semicolons before removing line comments let an inline comment consume the next row. The parser now strips comments line by line before splitting records. Regression tests cover consecutive inline comments, comment-only lines, malformed row widths and the public component counts. The source file is unchanged.

The adapter omits costs and branch angle-difference constraints. This solve uses the project dispatch-deviation objective, not the published PGLib cost optimum. Source angle bounds are audited on the returned state and pass; they were not optimization constraints. Existing import logic clamps supplied dispatch to generator capability bounds and uses it as the objective reference. Source VM/VA are not fixed replay inputs: the numerical start is flat and the state is optimized.

![Voltage, terminal loading and source angle checks](validation.png)

[Diagnostics](pglib118-fixed-diagnostics.json), [result](pglib118-fixed-design.json), [study](study.json) and [plot data](summary.json) are retained. Reproduce using examples/s1_public_baseline.jl with output directory artifacts/s1_public118.
