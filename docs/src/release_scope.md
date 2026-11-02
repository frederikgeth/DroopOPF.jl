# Supported scope and limitations

DroopOPF solves balanced, positive-sequence **steady-state AC** models with
explicit reactive controls and declared operating/control constraints.

| Capability | Supported model | Interpretation limit |
|---|---|---|
| Base OPF | AC balance, voltage bounds, generator capability and both-terminal branch limits | Local nonlinear solutions require independent validation. |
| Reactive control | FreeQ, FixedQ, AVR and saturated/deadband Volt/VAR curves | These are equilibrium relations, not dynamic controller models. |
| Equipment design | Selected continuous transformer ratios and supported simple-bank admittances | Legal discrete positions and device movement trajectories need separate checks. |
| Security | Coupled base/outage states, limit-aware response and declared equipment recourse | Acceptance applies to the stated catalogue; exclusions and unresolved solves remain explicit. |
| Shared curve design | Bounded slopes, references and supported deadband widths | Multiple local or weakly identified designs can exist. |
| Multi-period operation | Shared controls, period-specific dispatch, durations and declared ramps | No inferred storage, commitment or dynamic transition model. |
| PSS/E import | RAW 33/34/36 parsing, strict supported AC conversion and saved-state replay | Native version-specific export evidence and missing ratings must be reported explicitly. |
| Feasibility qualification | Physical witnesses and supported independently checked outer certificates | A timeout or failed local solve is not an infeasibility proof. |

The base OPF objective is weighted schedule deviation. The base multi-period
objective is active loss energy. Optional reserve-aware policies are documented
separately; no generator fuel costs or manufacturer limits are invented.

Always declare system bases, ratings, generator availability, reactive modes,
control bounds, equipment timing and movement budgets before comparing results.
Use [validation](validation.md) to check the returned physical state and policy.
The [API reference](api.md) documents individual entry points.
