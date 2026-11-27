# Static reactive laws and coupled witnesses

`StaticReactiveLaw` explicitly represents fixed Q, fixed power factor, piecewise
Q(V), droop, Q-limit-releasing AVR, SVC B(V), and STATCOM Q(V). Values use the case
system base; current uses that system base at terminal voltage. An optional
current limit intersects the supplied Q box and apparent circle. It restricts
feasible states and does not silently project or clip the active response.
Source boxes need not contain zero. No technology or dynamic mode is inferred.

`StaticWitness(case, laws; ...)` describes an ordinary preventive state when
`anchor=0`. Positive anchors reference an earlier preventive state's actual PG
for limit-aware active response. Cases in different preventive contexts may have
different declared capability profiles. Recourse cases may remove devices, but
cannot change loads, equipment, capabilities, laws or participation. Each
conditional probe declares a fixed `test_bus` and `test_q`; virtual Q is never
ordinary operating supply. Native witness endpoints do not prove path connection.

`optimize_static_witnesses` uses the existing native AC builder in one coupled
NLP. `design_bounds` shares explicit gain/reference parameters by generator ID;
all other supplied law settings stay fixed. Explicit `tap_controls` and
`shunt_controls` select shared preventive tap ratios and continuous bank
susceptances. Independent contexts may have their own preventive dispatch.
The declared device bounds and ordinary AC limits apply throughout.

The API supports `:loss`, `:cost`, `:feasibility`, `:dispatch`, `:q_reserve`,
`:security_margin` and `:voltage_deviation`. The cost objective requires
explicit piecewise-linear `generation_costs`. The dispatch objective minimizes
normalized squared movement from explicit reference PG vectors. For a loss
design with a prescribed headroom floor, pass `objective=:loss` and
`objective_limits=Dict(:security_margin => h)`. That limit applies to every
supplied witness. Validate with the same objective limits and selected equipment
controls. The [initialization guide](design_workflow.md#Review-performance-and-choose-a-candidate)
explains target selection and catalogue replay.

Shared AVR design uses reference-only bounds, for example
`Dict(1 => (; v_ref=(1.02, 1.04)), 2 => (; gain=(50., 200.), v_ref=(.98, 1.02)))`.
The AVR entry applies to `:avr` or `:smooth_avr`; its result contains only
`v_ref`. AVR projection gain, Q limits and smoothing width remain fixed, and
supplying a gain bound for an AVR is rejected. Droop entries still require both
gain and reference bounds. Every selected parameter is a single variable shared
across all supplied witnesses, including outage and conditional-Q states.

Explicit `:smooth_droop` and `:smooth_avr` modes retain native softplus saturation.
They require positive declared reactive widths; smooth droop additionally requires
its voltage width, and smooth AVR requires its projection gain. Legacy clipped
modes retain their existing semantics. These are static laws, not dynamic AVR
or inverter models.

`validate_static_witnesses` checks native convergence, physical constraints,
reactive laws, parameter bounds, angle bounds and exact active response, including
all declared conditional injections. `validate_static_reactive` separately
replays the explicit laws and current/apparent limits. These APIs do not change
legacy Study/Generator schemas or the inverter priority APIs.

Nonsmooth transitions are explicit; numerical failure is not physical
infeasibility. A 1e-20 square-root derivative guard is used internally, with
unmodified physical circles imposed separately and exact replay required.
Use bounded witness sets and measure memory before scaling. Complete catalogue
and conditional-path qualification remain the caller's responsibility.
