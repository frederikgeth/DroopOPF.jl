# Validation

```@meta
CurrentModule = DroopOPF
```

Solver termination is not, by itself, proof that a generator operating point
is physically valid. `validate_equilibrium` recomputes the AC power balance,
generator limits, branch margins, and exact droop residuals independently.

```julia
validation = validate_equilibrium(case, result.state)
validation.valid
validation.power_balance_max
validation.droop_residual_max
```

For a smooth result, passing the result object also records the smoothing gap:

```julia
report = equilibrium_report(case, result)
println(markdown_report(report))
```

The report checks:

- maximum active/reactive AC power-balance residual;
- exact generator droop residual;
- voltage, active-power, reactive-power, and thermal margins;
- control active-power-range violations;
- smooth-versus-exact droop gap, when applicable.

For cross-solver tests, start with `1e-5` per-unit AC residuals, `5e-4`
per-unit exact droop residuals, and `1e-5` complementarity products. Tighten
these after scaling and conditioning have been characterized on larger cases.
