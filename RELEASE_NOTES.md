# v0.10.0-rc1 — library capabilities

The library provides limit-aware active response, shared reactive droop design,
multi-period mixed AVR/droop security models, apparent-power constraints,
reserve and feasibility objectives, and PSS/E RAW import with saved-state checks.

Shared multi-controller droop design supports the default smooth NLP and the
exact complementarity formulation. Pass `encoding=:complementarity` to select
CCOpt; its current exact builder uses attached droop controls. Independently
validate the returned settings and scenario states before accepting a design.

## Compatibility

The default active response redistributes movement after generators saturate.
Serialized studies retain their declared response and control policies; saved
proportional-response contracts are not silently migrated. Physical operating
limits and acceptance tolerances are unchanged.

The models assess steady-state operation. They do not establish transient
stability, discrete equipment switching, or general islanding security. PSS/E
36 support remains schema-based pending native exporter qualification.

## Installation and documentation

Install from GitHub or a source archive. Installation does not launch studies.
See the README and teaching documentation for worked examples, supported scope,
solver configuration, and validation requirements.
