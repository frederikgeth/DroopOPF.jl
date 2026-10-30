# Case import and export

`import_case` provides a common interface to the existing readers and the
optional PowerIO integration. It returns a `CaseImport` containing the case,
supplied operating state, source identities, original rating evidence and
metadata for export. Importing does not solve or certify the supplied state.

```julia
using DroopOPF

native = import_case("network.raw"; backend=NativeBackend())
native.case
native.initial_state
native.source_ids
native.metadata
native.diagnostics

# PowerIO is optional during the native parser migration.
using PowerIO
external = import_case("network.raw"; backend=PowerIOBackend())
```

The native backend remains the default during migration. Format detection
recognizes `.raw` and `.m`; otherwise supply `format=:psse` or `:matpower`.
There is no automatic fallback after a reader rejects a case.

## Import policies and evidence

Both new import pathways require an explicit finite substitute for zero or
omitted thermal ratings before returning a case:

```julia
imported = import_case("network.raw"; backend=PowerIOBackend(),
    options=ImportOptions(unrated_limit_pu=10.0))
```

The substitute is a deliberate modeling assumption. Original unknown ratings
remain `nothing` in `metadata.branch_rating_mva`, and are never converted into
known source ratings. Legacy `load_matpower_case` and PSS/E APIs retain their
existing policies.

Supplied generator P/Q remain unchanged in `initial_state`, including values
outside limits. Only optimizer start hints are clamped. Saved-field presence
is tracked separately: a defaulted voltage is not evidence of a saved value.
PowerIO's current typed integration marks this presence `:unknown` and cannot
certify source saved-state completeness. The existing native
`validate_psse_saved_solution` remains available for that check.

`validate_imported_state(imported)` evaluates either backend without solving.
Its report separates `power_flow_consistent` (numerical residuals),
`saved_state_complete` (supplied-field evidence), `known_limits_valid` and
`thermal_coverage_complete` (original ratings). `valid` requires all four.
Thus an internally consistent PowerIO state with unknown source presence
reports its numerical consistency while remaining uncertified. An explicit
unrated-limit substitute never fills original rating coverage. Existing RAW
validation report schemas remain unchanged. Validation checks the original
snapshot signature and rejects later mutations of the case, state or evidence;
exports can still deliberately reconstruct a modified case with bound state.

MATPOWER uses a default frequency of 50 Hz in this common API, matching the
native loader. Supply `ImportOptions(base_frequency=60.0)` for a 60 Hz study.
RAW uses its parsed frequency unless explicitly overridden.

## Current PowerIO import profile

The integration uses PowerIO 0.11.7 or a compatible 0.11 release. It converts
balanced MATPOWER and RAW networks containing buses, generators,
constant-power/impedance loads, fixed shunts and supplied switched-shunt
admittance. Fixed two-winding transformers are supported through MATPOWER.
RAW transformers require the loaded library to pass a small public-parser
qualification over CW/CZ and nominal-voltage bases. The released PowerIO 0.11.7
library fails because it omits the nominal-winding/bus voltage-base impedance
factor for CZ=2/3. A corrected local build can pass and enable this pathway.
The check is repeated when needed, so changing the loaded library cannot
reuse a cached qualification. The native transformer importer and independent
two-port tests remain the compatibility reference.
Droop/AVR assignments are not inferred;
tap and switched-shunt controls are locked at supplied settings with diagnostics.

Current and exponential load terms, arbitrary branch terminal admittance,
current-based ratings, three-winding devices, storage, switches, DC equipment,
static VAR compensators and detailed node/breaker topology are rejected.
MATPOWER angle-difference constraints, nonrectangular generator capability
curves and nonempty unknown extension tables are rejected by the common API.
Costs and descriptive fields produce diagnostics; source costs do not configure
the DroopOPF objective. Both backends exclude isolated buses and their equipment.

Upstream warning/error diagnostics reject conversion unless their exact model
coverage has been qualified. Currently qualified RAW losses are owner/zone
descriptions, known solver iteration/adjustment settings and rating-set labels.
Every original notice remains in the result. Electrically active and unknown
losses remain errors. Consequently, some RAW files accepted by the
native parser are deliberately rejected by this initial integration, including
files with unresolved source regulation references. Inspect
`CaseIOError.diagnostics` for upstream codes and messages.

Native RAW v36 remains available; PowerIO's current reader covers RAW v32–35.
This adapter only accepts the RAW/MATPOWER profile described here, rather than
all formats supported upstream.

## Prepare and write exports

Exports use PowerIO and reconstruct output from the current case. Retained
input bytes are never replayed as an exported modified case.

```julia
using DroopOPF, PowerIO

imported = import_case("case.m";
    options=ImportOptions(base_frequency=60.0))
c = imported.case

# Capture ordering and model identity before calculating a state.
state_context = export_state_context(c)
solution = solve_opf(c)
bound_state = bind_export_state(solution.state, state_context)

plan = prepare_export(c; format=:psse, context=imported, state=bound_state)
plan.accepted
plan.diagnostics
write_export("solved.raw", plan)
```

`bind_export_state` copies the state and records caller-declared provenance.
The caller must use the context of the actual calculation. Export checks the
model signature and vector ordering, rather than assuming equal dimensions
establish alignment. A changed case requires a newly calculated/bound state.

To export an explicitly labeled initial guess:

```julia
plan = export_case("case_copy.m", c; format=:matpower, context=imported,
    options=ExportOptions(state_policy=:initial_guess))
```

Preparation runs in memory. An accepted plan owns output bytes and is
independent of later case edits. Writing rejects existing destinations unless
`overwrite=true`, always rejects source aliases and symlink destinations, and
installs output only after successful staging. Writer losses leave a plan
unaccepted; `write_export` refuses it without changing destination bytes.

## Export scope and fidelity

The initial export profiles are canonical MATPOWER and PSS/E RAW v33 single
files. Export passes `base_frequency` metadata to the public dictionary
constructor and checks the actual constructed frequency before writing.
Released PowerIO 0.11.7 ignores this metadata and therefore remains restricted
to 60 Hz construction. A corrected local build preserves it, enabling 50 Hz
RAW exports. MATPOWER cannot encode frequency; its writer reports that loss
for non-60 Hz cases and the prepared plan remains unaccepted.

Export represents a static AC case and optional operating point. Target
equipment IDs are regenerated by the writer, with a diagnostic; original
identities remain in import context. Source metadata and control behavior are
not promised to survive a round trip. Existing DroopOPF study persistence
remains the place to store study configuration and control definitions.

Droop controls and shunt banks require `control_policy=:snapshot`, which
explicitly allows their static projection. Other writer losses remain
rejected. Generator apparent-power capability is currently rejected because
this export profile cannot preserve it. PSS/E projection of transformer
terminal charging into magnetizing admittance is also rejected.

For imported unknown ratings, explicitly choose
`ExportOptions(rating_policy=:source)` to write an unrated value, or
`:effective` to adopt the finite limit in the current case. The default rejects
that ambiguity. Out-of-limit dispatch is reported and exported unchanged.

Every exported bus requires a positive real voltage base in
`CaseIOMetadata.bus_base_kv`. Imports retain it where provided. Programmatic
cases must supply their own metadata:

```julia
metadata = CaseIOMetadata()
metadata.bus_base_kv[1] = 230.0
metadata.bus_base_kv[2] = 115.0
plan = prepare_export(c; format=:matpower, metadata,
    options=ExportOptions(state_policy=:initial_guess))
```

The metadata must cover the actual buses in `c`. Imported context is checked
against equipment IDs, attachments, ordering and MVA base before reuse.
Preparation checks constructed states, limits, attachments, outages and branch
terminal admittances component by component, using linear storage rather than
a dense network matrix.

## Test a corrected local PowerIO build

Build PowerIO's C library in an isolated checkout with
`cargo build --locked -p powerio-capi`, then set `POWERIO_CAPI` to the resulting
shared library before starting Julia. PowerIO also provides
`PowerIO.set_library!(library_path)` for a session-only override. No persisted
preference is needed.

Run the integration suite described in the repository's `test/README.md` with
`DROOPOPF_POWERIO_TEST_PROFILE=corrected` for that library. CI separately requires
the released binary's rejection paths and the corrected build's positive paths,
including original two-port admittances, the public IEEE14 RAW case, native
equivalence and exported RAW frequencies. The corrected CI library is built
from a pinned upstream source with a test-only patch; production uses the
installed library and its qualification guards. A local patch does not change the installed
package's reported release version, so qualification uses behavior rather
than an assumed future version number.
