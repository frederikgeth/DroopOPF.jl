# Package boundaries and integration

DroopOPF owns reusable static network physics, capability and control equilibria,
AC OPF/SCOPF, contingency response, equipment policies, multi-period optimisation,
case I/O and independent static validation. M11–M14 development belongs here.

DroopDesign is a separate private research consumer of this package. It owns QV
tracing/design research (Q), dynamics and stability methods (H), and MHQ integration
and assurance. DroopOPF does not depend on DroopDesign or its dynamic backends.
Q's independent static equations remain useful verification/tracing machinery;
they do not become a second production SCOPF implementation.

## Supported boundary

Use exported APIs and preserve case, controller, scenario and period identities.
`model_data` exposes the library serialization representation; the enclosing file
format retains its own schema version. `materialize_operating_point` reconstructs
and validates static physical settings from supplied states, OPF, joint design,
SCOPF and multi-period results. `scale_case_loads` explicitly scales demand.

```julia
point = materialize_operating_point(study, result; scenario_id=:base)
point.case
point.state
point.reactive_assignments
point.source_context
```

The materializer does not solve or repair a candidate. Scenario endpoints carry
no inferred dynamic fault sequence or verified equipment movement timing. An
external dynamic assessor must map a supported physical controller and event.
The caller owns output storage and confidentiality. Neither serialization nor
static validation sanitizes private network information.

PowerIO is an optional weak dependency. Its extension and import/export tests
belong to DroopOPF. Native import remains available without loading PowerIO;
unsupported electrical/source mappings fail explicitly. RAW series, supplied
availability and protected full-load security APIs are static workflows; fitted
IBR observations do not automatically become active or verified controllers.

## Development and evidence

Run `python3 tools/check_boundaries.py` and package tests before integrating.
Use synthetic/public fixtures only. Dynamic models, Q/H research campaigns and
private evidence belong in the consuming research environment. Confidential RAW
files and all derived results stay outside Git/cloud folders on the work machine.

The 3 November 2026 local migration transfers existing static implementations
and tests into this checkout. It is not a new release or new physical campaign.
Existing user edits are retained; no branch, commit, push or publication is
implied. Consumers must record a source revision plus a content fingerprint for
a dirty development tree. A version number alone does not identify local changes.
