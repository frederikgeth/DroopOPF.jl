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

## Learn the model

Start with the [teaching guide](docs/src/index.md), then run the complete
[two-bus OPF](docs/src/first_opf.md) and [three-bus security example](docs/src/first_security.md).
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
- [PSS/E data and saved-solution checks](docs/src/psse.md)
- [Validation](docs/src/validation.md)
- [Supported scope](docs/src/release_scope.md)

## License

Library code is BSD-3-Clause; see [LICENSE](LICENSE). Third-party test data retain
their own provenance and notices; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
