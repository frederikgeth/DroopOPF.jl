# DroopOPF.jl

Julia tools for equilibrium-aware AC optimal power flow, reactive droop design,
mixed AVR/droop controls, and independently validated steady-state SCOPF.

## v0.10.0-rc1

This prerelease provides steady-state AC optimization, reactive/equipment design,
security assessment and deterministic multi-period operation.

```julia
using Pkg
Pkg.add(url="https://github.com/frederikgeth/DroopOPF.jl.git", rev="v0.10.0-rc1")
using DroopOPF
```

For a smaller download without historical Git objects, download the source asset
from the [release](https://github.com/frederikgeth/DroopOPF.jl/releases/tag/v0.10.0-rc1),
extract it, and use `Pkg.develop(path="/path/to/DroopOPF")`.
Julia 1.10 and 1.12 are the release test targets. Solver dependencies are installed
separately by Julia; the source archive size is not the installed depot footprint.

## Current development updates

The current `main` branch includes updates beyond the tagged prerelease:

- Correct RAW CZ=2/3 transformer impedance conversion and independent two-winding
  checks; PowerIO integration is tested with native 0.11.7 and official 0.11.9.
- RAW snapshot inspection, compatible time-series loading, explicit generator
  classifications and zone extraction with fixed saved boundary exchanges.
- Supplied generator on/off changes and period-specific AVR input targets,
  preserving capability, ramp and outage-policy checks.
- Explicit static inverter/current-limit and common-frequency models,
  initialization helpers, static witnesses and validated operating-point transfer.

For these APIs, install `rev="main"` instead of the tag above, or develop a
checkout of the current source. Record the exact commit for reproducible studies.
This does not create a new tagged release or change the stable documentation
snapshot. See [static controls](docs/src/static_controls.md),
[case import/export](docs/src/case_io.md), and [RAW series](docs/src/psse.md).
All new control models remain steady-state models; no dynamic stability or
native PSS/E matching claim follows from import or a converged solve.

## Learn the model

Start with the [teaching guide](docs/src/index.md), then run the complete
[two-bus OPF](docs/src/first_opf.md) and [three-bus security example](docs/src/first_security.md).
The [workflow flowcharts](docs/src/design_workflow.md) cover parsing, input checks,
initialization objectives, design handoff and candidate review.
The guide includes network/control schematics, a [Volt/VAR curve tutorial](docs/src/volt_var.md),
[AC branch physics](docs/src/ac_model.md), and [notation, signs and units](docs/src/notation.md).
The examples execute and check their results during the documentation build.

## Capabilities and scope

- Smooth Ipopt/MadNLP and separate exact-complementarity CCOpt formulations.
- Explicit FreeQ, FixedQ, AVR and volt-var droop modes; apparent-power capability.
- Limit-aware automatic active response, including saturation redistribution.
- Continuous transformer/shunt design with declared preventive/corrective policies.
- Shared droop design, contingency assessment and independent physical validation.
- Deterministic multi-period operation, ramps, mixed controls and AVR scheduling.
- PSS/E RAW 33/34/36 parsing and supported-subset saved-solution checking.

See the [release scope](docs/src/release_scope.md) for qualification and limitations.
## Run and test

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
julia --project=. examples/release_smoke.jl
```

The default tests use bundled small-network fixtures. The smoke example uses a
synthetic two-bus case and writes no files.

## Documentation

- [Learning guide](docs/src/index.md)
- [Getting started](docs/src/getting_started.md)
- [Notation and units](docs/src/notation.md)
- [SCOPF policies](docs/src/scopf.md)
- [Multi-period operation](docs/src/multi_period.md)
- [Mixed AVR/droop controls](docs/src/mixed_avr_droop.md)
- [PSS/E data, saved-solution checks and snapshot series](docs/src/psse.md)
- [Case import/export and optional PowerIO](docs/src/case_io.md)
- [Static controls, initialization and operating-point transfer](docs/src/static_controls.md)
- [Validation](docs/src/validation.md)
- [Supported scope](docs/src/release_scope.md)

## License

Library code is BSD-3-Clause; see [LICENSE](LICENSE). Third-party test data retain
their own provenance and notices; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Integration boundary

This repository owns the reusable AC OPF/SCOPF core, static controls, capability,
equipment policies, multi-period optimisation and case I/O. DroopDesign consumes
it for Q/H research and MHQ integration. See [package boundaries](docs/src/package_boundaries.md).

### Fixed-frequency Q–V study scope

New aggregate IBR studies use [`qv_inverter`](docs/src/static_inverters.md),
with a configurable reactive ceiling of 0.395 times effective apparent rating.
Supplied Q bounds, apparent/current limits and declared control priority remain
active. GFL, terminal-equivalent GFM and BESS charging are supported; storage
energy accounting is separate. P–f/common-frequency models remain available
as the **frequency-aware Q–V design** side study. Existing constructor behavior
and historical evidence are preserved. See `examples/fixed_frequency_qv.jl`.
