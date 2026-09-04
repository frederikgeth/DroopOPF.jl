# Data model

```@meta
CurrentModule = DroopOPF
```

## Network and operating devices

`Bus`, `Branch`, `Load`, and `ACNetwork` describe the balanced AC network in
per-unit quantities. A `Generator` is attached to a network bus and carries
active/reactive limits, availability, and initial values.

```julia
network = ACNetwork(
    [Bus(1; reference = true), Bus(2)],
    [Branch(1, 1, 2; resistance = 0.01, reactance = 0.1,
            thermal_limit = 5.0)],
)
generator = Generator(
    1, 1;
    p_min = 0.0, p_max = 2.0,
    q_min = -1.0, q_max = 1.0,
    initial_p = 0.5,
)
```

## Volt-var droops

`VoltageSchedule` stores the reference voltage and deadband. `VoltVarDroop`
adds a positive voltage-per-reactive-power slope, a reactive reference inside
the deadband, and a `ReactiveCapability`.

```julia
control = VoltVarDroop(
    VoltageSchedule(1.0; v_db_low = 0.99, v_db_high = 1.01),
    0.05,
    0.0,
    ReactiveCapability(p_min = 0.0, p_max = 2.0,
                       q_min = -1.0, q_max = 1.0),
)
```

The exact curve is available through `droop_curve(control)` and evaluated with
`droop_response(control, voltage; p = active_power)`. The active-power range
on the control is enforced for its attached generator.

## Attachments

`GeneratorControlAttachment` connects one generator to one control and gives
the regulated location. M1 permits one static attachment per generator.

```julia
attachment = GeneratorControlAttachment(
    1, 1, RegulatedLocation(:bus, 1),
)
```

This explicit attachment layer leaves room for plant-level, remote-bus, and
system-level control semantics in later milestones.
