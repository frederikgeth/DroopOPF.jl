# Explicit static controls and reusable operating points

These APIs describe steady-state equilibria. They do not establish transient
stability, protection behavior, device timing or dynamic grid-forming performance.
Provide physical capabilities and control settings explicitly; RAW machine base
or technology labels are not inverter ratings.

## Inverter capability and reactive response

`StaticInverter` declares device bases, terminal/regulated buses, active/reactive
priority, apparent/current limits, availability, and fixed-Q or Volt/VAR control.
P/Q references use the device `base_mva`; current uses
`base_mva / (sqrt(3) * terminal_base_kv)`. Network voltages use terminal bus bases.
The capability intersection retains tighter source generator bounds.

`qv_inverter` builds a fixed-frequency Q/V model with an explicit configurable
reactive cap (default 0.395 of its effective apparent rating). This cap is an
assumed capability envelope, not guaranteed reserve. P/f response is separate.
Use `inverter_response` for the declared static response and
`validate_static_inverters` to assess a candidate state. `solve_inverter_opf` and
`validate_inverter_opf` integrate the controls with AC equations and replay.

`VoltageSourceGFM` and `ThresholdVirtualImpedance` provide a separate static
internal-voltage representation with current limiting. Use
`solve_voltage_source_opf` and `validate_voltage_source_opf` for that declared
model. No filter, virtual impedance or transient control parameter is inferred
from an imported case. Terminal Q/V and internal-source representations have
different model contracts and must not be silently substituted.

## Common-frequency equilibrium and initialization

`GeneratorFrequencyResponse` declares active references and P/f response in
pu-system-power per Hz. `solve_common_frequency` couples participating generator
and inverter responses to one frequency, with explicit bounds; saturated units
retain their capability limits. `validate_common_frequency` replays the control
and network equations. A common-frequency equilibrium is not a frequency nadir
or transient stability result.

`prepare_initialization` copies a supplied primal seed, aligns its angle gauge,
and can bracket a common-frequency start. This changes numerical hints only,
not source settings or operating limits. An unbracketed seed is reported as such.
`design_preventive_dispatch` is a separate declared optimization of active
references with fixed reactive laws and equipment. Its reserve objective and
bounded reserve-target fallback are explicit; validation is required before
using the resulting state. It is not a reactive gain-design campaign.

## Static witnesses and materialization

`StaticReactiveLaw` and `optimize_static_witnesses` support explicit reactive
assignments and AC witnesses; use `validate_static_witnesses` for physical acceptance.
Limits, relief, equipment controls and objectives must remain part of the declared
contract. A feasible witness does not prove network-wide feasibility or optimality.

Supplying `generation_costs` for reporting does not add cost variables to a
non-cost solve. Cost epigraphs are added only for `objective=:cost` or an explicit
`:cost` entry in `objective_limits`; reported costs are recomputed from dispatch.

`model_data` exposes the library's serializable representation without writing a
file. `materialize_operating_point` returns a supported case, state, reactive
assignments and source context, rejecting invalid optimized results through the
corresponding validator. It does not repair a point or infer a dynamic event.
`scale_case_loads` applies an explicit nonnegative common P/Q factor while
preserving equipment and controls. These representations can contain private
identities and operating data; none is a disclosure sanitizer.

## Period-specific availability and AVR inputs

Multi-period studies allow supplied generator status to vary while preserving
other compatibility checks. Response weights must agree whenever a unit is
online. Declared ramps still apply across status changes; commitment decisions
and startup exemptions are not inferred.

`supplied_avr_schedule=true` permits supplied period-specific AVR targets with
common modes and regulated locations. Each target stays fixed across outages.
This is input scheduling, not automatic optimization of AVR targets. Leave it
false to retain the common-target contract, or use the protected RAW-series
entry points described in [PSS/E import](psse.md).
