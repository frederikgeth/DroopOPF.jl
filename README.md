# DroopOPF.jl

Julia tools for equilibrium-aware AC optimal power flow, reactive droop design,
mixed AVR/droop controls, and independently validated steady-state SCOPF.

## v0.10.0-rc1

This prerelease packages the implemented S1/S2/P1/P2/P3 capabilities without
bundling research campaigns. Milestone labels describe research work; they are
not separate installation dependencies or a claim that every milestone is closed.

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

## Capabilities and scope

- Smooth Ipopt/MadNLP and separate exact-complementarity CCOpt formulations.
- Explicit FreeQ, FixedQ, AVR and volt-var droop modes; apparent-power capability.
- Limit-aware automatic active response, including saturation redistribution.
- Continuous transformer/shunt design with declared preventive/corrective policies.
- Shared droop design, contingency assessment and independent physical validation.
- Deterministic multi-period operation, ramps, mixed controls and AVR scheduling.
- PSS/E RAW 33/34/36 parsing and supported-subset saved-solution checking.

See the [release scope](docs/src/release_scope.md) for qualification and limitations.
The latest mixed 500-bus study passed all 389 connected contingencies at five
sampled periods under its stated P2 policy. This is not full islanding, dynamic,
discrete-equipment or global-optimality certification.

## Run and test

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
julia --project=. examples/release_smoke.jl
```

The default test suite includes extended small-network numerical tests and needs
no campaign archive. The smoke example uses a synthetic two-bus case and writes
no files. Research scripts in `examples/` are retained for reproducibility;
large campaign scripts require the optional evidence inputs described below.

## Documentation and evidence

- [Getting started](docs/src/getting_started.md)
- [SCOPF policies](docs/src/scopf.md)
- [Multi-period operation](docs/src/multi_period.md)
- [Mixed AVR/droop controls](docs/src/mixed_avr_droop.md)
- [PSS/E data and saved-solution checks](docs/src/psse.md)
- [Research evidence and restoration](docs/src/research.md)
- [Release notes](RELEASE_NOTES.md)

Research evidence is preserved separately in local archives with SHA-256
checksums; those archives remain local and are not distributed with this release.
The archives are not necessary to install or test the library.
Original sealed campaign contents remain unchanged. Git history is retained;
ordinary Git clones can still include historical large objects.

## License

Library code is BSD-3-Clause; see [LICENSE](LICENSE). Third-party test data retain
their own provenance and notices; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
