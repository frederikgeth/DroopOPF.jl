# PSS/E RAW data parser

The [common case import and export API](case_io.md) also supports an optional
PowerIO pathway and canonical exports. This page documents the native parser
and its existing saved-state validation API.

Historical `artifacts/` paths on this page identify local campaign records, not
files bundled with the release. See [archive access](research.md) and the
[current qualification index](milestones.md).

`parse_psse_raw` reads full-case bus/branch RAW revisions **33, 34 and 36**.
`import_psse_case` converts the supported electrical subset into a DroopOPF
`Case`, with source identities, supplied operating points and diagnostics.
`load_psse_case` returns just the converted case.

```julia
raw = parse_psse_raw("network.raw")
raw.revision
raw.sections[:generator][1].fields

# Strict conversion: zero/omitted ratings require an explicit decision.
imported = import_psse_case(raw; unrated_limit=10.0) # pu, only if intended
case = imported.case
supplied_state = imported.initial_state
identities = imported.source_ids
messages = imported.diagnostics
```

There are no added package dependencies or PSS/E installation requirements.
This parser does not read binary `.sav`, `.dyr`, `.seq` or JSON `.rawx` files.
IC=1 change-case files are rejected because they need an existing network.
No optimization is launched by parsing or importing.

## Version handling

| Feature | v33 | v34 | v36 |
|---|---|---|---|
| Bus fields and supplied Vm/Va | Parsed | Parsed | Parsed |
| Load fields | Original layout | Distributed-generation fields | Text load type and name |
| Fixed shunts | Original layout | Same layout | Additional name |
| Generator fields | Original layout | NREG at tail | NREG before MBASE, BASLOD, droop-controller name and machine name |
| Branch ratings | Three ratings | Name and twelve ratings | Twelve ratings plus bypass flag |
| Switched shunts | N/B block pairs | NREG extension | ID, NREG, name and S/N/B block triples |
| Transformer records | Four or five rows | Expanded winding ratings | Expanded winding ratings |
| Additional sections | Retained | System-wide/switching/substation data retained | Voltage droop, switching-rating tables, load types and interfaces retained |

The parser handles comma or whitespace delimiters, single/double quoted fields,
doubled quote escapes, commas/slashes inside names, trailing comments, `@!`
headers, empty fields, CRLF, UTF-8 BOM and Fortran D exponents. Optional omitted
fields remain absent in `.fields`; conversion applies documented defaults.
Use `encoding=:latin1` for legacy extended-ASCII text.

Each `PSSERecord` retains typed known fields, original token rows and line
numbers. `PSSERawData.text` retains the source text; unknown fields and sections
are preserved. Transformer regulation tails are retained as `control_fields_1`,
`control_fields_2` and `control_fields_3` rather than guessing minor-version
node/control-field ordering. Extended bus-name references are retained by the
parser; current AC conversion requires numeric bus references.

Delimiter comments determine section transitions when present. Bare zero
terminators use the declared revision's section order. Substation internals are
opaque, preserving nested records and zero delimiters. Malformed numeric fields,
unterminated quotes, truncated transformers, unsupported revisions, premature EOF
and data after Q produce source/line errors.

## Electrical conversion

The strict AC subset includes energized buses; in-service constant-power loads;
fixed shunts; generators (including equal minimum/maximum Q); lines; fixed
2-winding transformer ratios/phases; and switched shunts locked at supplied
BINIT. Load impedance components are represented exactly as voltage-squared
fixed shunts. Constant-current loads and embedded distributed-generation load
models are rejected. Unavailable generators, branches and shunts retain their
availability flags. Type-4 buses and their attached equipment are excluded from
the energized case, with diagnostics; their original records remain available.

MW/MVAr values are divided by SBASE; angles are converted from degrees to
radians. Fixed shunt BL and switched-shunt BINIT retain the positive-capacitive
sign. Generator identity is `(bus, ID)`, and branch identity includes `(I,J,CKT)`;
integer domain IDs are mapped back through `.source_ids`.

Transformer CW=1/2/3 and CZ=1/2/3 conversions account for system MVA base,
nominal winding kV, winding-bus kV, secondary winding ratio and phase. Tests
compare all nine combinations against an independent two-port admittance
primitive. Magnetizing admittance and impedance-correction tables are rejected;
they are not silently moved to fixed bus shunts that would lose transformer
outage association. Nonzero branch-end shunts and bypassed branches are also
rejected by conversion.

Zero/omitted thermal ratings are **not** assigned a fabricated finite limit.
Conversion requires an explicit `unrated_limit` in pu and records its use.
The source XFRRAT/NXFRAT current-rating unit options are retained, but conversion
currently requires MVA ratings. It uses the first normal rating; remaining
ratings remain available in the parsed records.

There must be exactly one energized reference bus for AC conversion. Supplied
angles are shifted by its angle. `.initial_state` retains supplied generator
P/Q, including values outside reported limits; only generator optimizer start
hints are clamped, with diagnostics. Import success does not certify the source
operating point's feasibility.

Automatic PSS/E voltage regulation, remote control, tap/shunt switching and
voltage-droop controllers are not inferred as library droop/AVR controls. Cases
with nonempty voltage-droop, DC, FACTS, GNE, induction-machine, switching-device,
interface, substation or other unsupported electrical sections are rejected by
conversion. Three-winding transformers parse as five-row records but are not
yet converted to star equivalents. These records remain accessible in `raw`.

## Public data and qualification limits

- Existing public ARPA-E 14- and 500-bus v33 RAW files are exercised without modification.
- A genuine PSS/E 34.6 IEEE 14-bus file is included unchanged under
  `test/data/psse/public_v34_ieee14.raw`, with pinned URL, SHA-256 and the upstream
  MPL-2.0 license in the same directory. Source:
  [VeraGrid fixture](https://github.com/SanPen/VeraGrid/blob/1706c693584015c643305ef534823964eff89bde/src/tests/data/grids/RAW/ieee-14-bus_d_rename_lodf.raw).
- A public v33 synthetic South Carolina 500-bus RAW was tested: 500 buses,
  90 generators, 466 lines and 131 transformers. Source:
  [PowSyBl public fixture](https://github.com/powsybl/powsybl-core/blob/c0a2243e3d6dd79e50eaac072df63f72df33752a/psse/psse-model-test/src/main/resources/illinois/synthetic/SouthCarolina500.RAW).
- Synthetic v33/v34/v36 fixtures describe the same electrical circuit and test
  version-specific field positions. **No native public v36 exporter file was
  found in the searched sources.** Its present qualification is schema-based;
  this is not full PSS/E 36 exporter/interoperability certification.

The implementation references the
[versioned VeraGrid RAW schema definitions](https://github.com/SanPen/VeraGrid/tree/1706c693584015c643305ef534823964eff89bde/src/VeraGridEngine/IO/raw/versioned)
and independently checks transformer conversions against
[PowerModels' converter equations](https://github.com/lanl-ansi/PowerModels.jl/blob/master/src/io/psse.jl).
V36 additions were cross-checked with the Siemens-authored PSS/E 36.1 Data
Formats Reference Manual, sections 1.8–1.13 and RAW format change summary
(publicly indexed [manual copy](https://www.scribd.com/document/824207437/07-Data-Formats-Reference-Manual));
the proprietary manual is not redistributed. In particular, v36 BP and the new
sections must not be inferred solely from an inherited v35 branch schema.

Evidence is retained under `artifacts/p3_psse_parser_20261022/`. This work does
not alter sealed P2/S2 or multi-period campaign evidence and does not qualify
new controls or security studies.

## Check a new file against its saved power-flow state

The ordinary loader now checks the RAW saved solution automatically and logs a
compact result. It retains its `Case` return type. A failed saved-state check
warns by default; `require_valid=true` makes it an acceptance gate:

```julia
case = load_psse_case("network.raw";
    report_path="network.validation.json", require_valid=true)
```

The strict case loader still requires an explicit `unrated_limit` for missing
ratings. To inspect a file without constructing a case for optimization, use the
report-only check. This also works when thermal ratings are absent:

```julia
report = check_psse_file("network.raw";
    report_path="network.validation.json")
report["power_flow_consistent"]
report["known_limits_valid"]
report["thermal_coverage_complete"]
report["worst_buses"]
```

On the work machine, from the repository directory:

```sh
julia --project=. examples/check_psse_file.jl network.raw network.validation.json
```

Export the solved case from PSS/E to RAW, retaining bus VM/VA and generator
PG/QG. The check never re-solves, redispatches, adjusts equipment, clamps the
saved state or uploads data. It recomputes both-terminal branch flows, branch
losses, shunt consumption and P/Q balance at every bus using the saved values.
The JSON report includes source file SHA-256, revision, tolerances, bus
mismatches, branch flows, source identities and conversion diagnostics. It
refuses to overwrite the source RAW file, including an existing symlink alias.

Interpret the results separately:

| Status | Meaning |
|---|---|
| `passed` | Saved state satisfies AC balance and the assessed supported normal limits |
| `power_flow_mismatch` | At least one bus exceeds the declared P/Q balance tolerance |
| `limits_violated` | AC balance passes but a supported operating limit fails |
| `limits_unassessed` | Balance and known limits pass, but active branches lack ratings |
| `missing_saved_solution` | Required VM/VA or PG/QG fields are absent; defaults cannot certify a saved solution |
| `unsupported` | An electrical model cannot be faithfully converted for this check |
| `invalid_file` | File cannot be read or parsed |

The CLI exits 0 only for `passed`, and 2 for a reported failure or incomplete
assessment. Invalid command options or report-write errors remain errors.
A solved PSS/E case can balance correctly while violating generator or thermal
limits; `power_flow_consistent` identifies this distinction even when overall
`valid` is false.

Default balance thresholds are **0.01 MW and 0.01 MVAr per bus**, explicitly
reported to accommodate common RAW output rounding. They are configurable:

```julia
report = check_psse_file("network.raw";
    power_tolerance_mw=0.001, reactive_tolerance_mvar=0.001,
    limit_tolerance_pu=1e-6, top_buses=10)
```

These are saved-file comparison thresholds; the library's existing physical
solver-acceptance tolerances are unchanged. Loader options use
`validation_options=(power_tolerance_mw=0.001, reactive_tolerance_mvar=0.001)`.
Automatic checking can be disabled explicitly with `check_saved_solution=false`.

For report-only replay, an internal adapter marker lets admittances be evaluated
without thermal ratings. That marker is never exposed as a source rating or
used to accept thermal loading. Missing ratings appear as JSON null and remain
unassessed. No case with such a marker is returned by `check_psse_file`.

This checks the supported AC equations at the state saved in RAW. RAW does not
supply an independent branch-flow result listing, so recomputed flows are not
claimed to have been compared against a separate PSS/E branch-flow export.
Original PSS/E solver termination, remote/automatic control semantics, dynamics
and security qualification remain outside this small check.
