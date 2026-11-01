# Installation and learning paths

## Install Julia and the package

Use Julia 1.10 or newer. A Julia session shows a `julia>` prompt; the following is
**Julia code**, entered there or saved in a `.jl` script:

```julia
import Pkg
Pkg.activate("droopopf-tutorial"; shared=true)
Pkg.add(url="https://github.com/frederikgeth/DroopOPF.jl.git", rev="v0.10.0-rc1")
using DroopOPF
```

The named environment keeps the tutorial's dependencies together. The revision
pins the documented prerelease; use a specific revision for reproducible studies.
Package installation requires network access. Ipopt and the other declared Julia
dependencies are installed with the package; teaching examples require no additional input files.

If you already have a checkout, run this **shell command** from its root:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Then start `julia --project=.` for an interactive session in that environment.
`Pkg.instantiate()` installs the dependencies described by the project/manifest;
it does not run an optimization campaign.

## Choose a path

| Background or task | Suggested sequence |
|---|---|
| New to power-system optimization | [Concepts](concepts.md) → [first OPF](first_opf.md) → [Volt/VAR](volt_var.md) → [AC model](ac_model.md) |
| Familiar with AC OPF; new to autonomous controls | [Volt/VAR](volt_var.md) → [reactive modes](concepts.md#Four-reactive-modes) → [study workflows](study_workflows.md) |
| Ready for controller design | [First OPF](first_opf.md) → [droop optimization](droop_optimization.md) → [droop security](droop_security.md) |
| Importing a saved operating point | [Units and signs](notation.md) → [PSS/E](psse.md) → [validation](validation.md) |
| Investigating an unsuccessful solve | [Validation](validation.md) → [solvers](solvers.md) → [feasibility](feasibility_gate.md) → [robustness](robustness.md) |

The [first OPF](first_opf.md) constructs every object explicitly; it contains no
pre-existing `case` variable or hidden input file. Copy its blocks in order into
one Julia session.

## Check your installation

For a checkout, this shell command loads a bundled synthetic two-bus MATPOWER
fixture, solves it and independently checks its equilibrium:

```sh
julia --project=. examples/release_smoke.jl
```

That smoke case uses the control assignments provided by its importer. The teaching
case instead explicitly attaches a Volt/VAR curve so you can see its role.

## Symbols, units and scope

Before transferring equipment data, read [notation and units](notation.md).
Power fields use the case system base, branch phase angles use radians, and
Volt/VAR slopes use **voltage change per reactive-power change**. A droop slope
is not a reactive-power-per-voltage gain.

Next: [understand what the optimizer chooses](concepts.md), or go directly to
[the complete worked example](first_opf.md).
