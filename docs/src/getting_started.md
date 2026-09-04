# Getting started

```@meta
CurrentModule = DroopOPF
```

## Installation

DroopOPF.jl currently installs from GitHub:

```julia
import Pkg
Pkg.add(url = "https://github.com/frederikgeth/DroopOPF.jl.git")
```

For a checkout, instantiate the project from the repository root:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Julia `1.10` or newer is supported by the package project.

## Solve a case

Create a `Case` from an `ACNetwork`, `Load`s, `Generator`s, `VoltVarDroop`
controls, and `GeneratorControlAttachment`s. A complete runnable two-bus
example is available at
[`examples/m1_regime_case_study.jl`](https://github.com/frederikgeth/DroopOPF.jl/blob/main/examples/m1_regime_case_study.jl).

```julia
using DroopOPF

# `case` is a fully assembled DroopOPF.Case.
result = solve_opf(case; smooth_epsilon = 1.0e-3)
report = equilibrium_report(case, result)
println(markdown_report(report))
```

The result contains the solved `ACState`, objective, solver statuses, and the
smoothing parameters used by the model.

## Inspect operating points

```julia
points = droop_operating_points(case, result.state)
for point in points
    println(point.generator_id, ": ", point.regime,
            " V=", point.voltage, " Q=", point.reactive_power)
end

write_droop_plot("droop_operating_points.svg", case, result.state)
```
