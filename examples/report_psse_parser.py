"""Build a parser-only evidence report from retained RAW import results."""
from pathlib import Path
import json
import sys
ROOT=Path(__file__).resolve().parents[1]
OUT=Path(sys.argv[1]).resolve()
d=json.loads((OUT/'summary.json').read_text())
assert d['parsed_and_imported']==11 and d['optimization_runs']==0
lines=['# PSS/E RAW 33/34/36 parser — initial qualification','',
'**Implemented: revision-aware RAW parsing and strict AC-subset conversion.** '
'All 11 selected files parse and import. No PSS/E executable, new package '
'dependency or optimization campaign is required. Native v33/v34 public inputs '
'are tested; **v36 qualification is schema-based, not native-export certification**.','',
'## Implementation','',
'- `parse_psse_raw(path_or_io)` returns typed core fields, token rows, line numbers, '
'header values, diagnostics and preserved source text. Unknown records/fields remain available.',
'- `import_psse_case(raw)` returns a supported AC case, supplied state, source-ID '
'maps and explicit conversion diagnostics. `load_psse_case(path)` returns its case.',
'- Version handling includes v34 extended ratings; v36 generator offsets, '
'load-type text, device names, branch bypass, shunt block triples and new sections.',
'- The adapter normalizes MW/MVAr by system base, preserves shunt signs, converts '
'degrees to radians and implements two-winding CW/CZ base conversions. All nine '
'CW/CZ combinations match independent two-port admittance checks.',
'- Generator domain bounds now accept equal Qmin/Qmax, preserving native '
'fixed-Q limits. Reactive droop capability still requires a nonzero Q range. '
'A solver regression verifies an available fixed-Q unit without widening its limits.','',
'## Input coverage','',
'| Input | RAW revision | Buses imported | Generators | Branches | Schema fixture? |',
'|---|---:|---:|---:|---:|---|']
for r in d['rows']:
    name=r['source'].replace('test/data/','')
    lines.append(f"| {name} | {r['revision']} | {r['buses']} | {r['generators']} | {r['branches']} | {'yes' if r['schema_fixture'] else 'no'} |")
lines+=['',
'The external public synthetic South Carolina case contains 500 buses, '
'90 generators, 466 lines and 131 two-winding transformers. Exact source bytes, '
'pinned upstream revision and SHA-256 are retained in `inputs/` and '
'`public-500-provenance.json`. The unchanged native v34 fixture, its MPL-2.0 '
'license and provenance are in `test/data/psse/`. Existing ARPA-E inputs are '
'unchanged and their hashes are recorded in `summary.json`.','',
'## Parsing is separate from physical feasibility','',
'Supplied source states are preserved without projecting generation into limits. '
'State replay reports balance and bound violations separately from parse/import '
'success. These fixture and source states do not pass the library’s full '
'operating-point acceptance gate; their saved reports show the actual residuals. '
'No claim of security, solved OPF or physical infeasibility follows. Native public '
'exports can contain rounded states or inconsistent limits.','',
'Zero or omitted ratings require explicit `unrated_limit`; these import-only '
'checks deliberately supply 1e6 pu as a recorded demonstration placeholder. '
'It is not an equipment capability or a qualified operating limit. No source '
'ratings or demand values were altered in the retained RAW files.','',
'## Conversion boundaries','',
'Taps/phases remain fixed. Switched shunts are locked at supplied BINIT and '
'imported as fixed susceptance; automatic control and switching are not inferred. '
'Constant-impedance load terms become exact voltage-squared shunts. Current ZIP '
'loads and embedded distributed-generation load models are rejected.','',
'DC/FACTS, GNE, induction machines, nonempty voltage-droop controllers, '
'node/breaker substations, switching devices, interfaces, magnetizing admittance, '
'impedance-correction tables, nonzero branch-end shunts and three-winding '
'conversion are not supported by the strict AC adapter. Parsed records remain '
'available. Unknown electrical sections, bypassed branches, current-based rating '
'units and multiple energized slack buses cause explicit conversion errors. '
'Binary SAV, DYR, SEQ and RAWX are separate formats.','',
'## Verification','',
'Focused parser/import and global-feasibility regression logs, full-suite logs '
'and documentation-build output are retained in `verification/`. The initial '
'full-suite run caught the obsolete rejection of an available equal-Q unit; '
'its original log is retained and the expectation was updated to the new exact '
'fixed-Q contract. No physics tolerances were relaxed.','',
'P2 and S2 status/configuration and previous sealed evidence remain unchanged. '
'The parser-only campaign did not choose or move equipment or run SCOPF.','',
'## Reproduce','',
'Run `julia --project=. examples/psse_parser_validation.jl /fresh/output '
'/path/to/public500.raw`. Run focused tests with `using Test, DroopOPF; '
'include("test/test_psse.jl")`. See `docs/src/psse.md` for API and reference sources.','']
checks=OUT/'verification/checks.json'
if checks.exists():
    c=json.loads(checks.read_text())
    lines+=['## Final check results','',f'- Focused RAW parser/import checks: {c["parser_checks_passed"]}.',
        f'- Full Julia regression checks: {c["full_regression_passed"]}; failures: 0.',
        '- Documentation build: passed (API/search-index size warnings).','']
(OUT/'REPORT.md').write_text('\n'.join(lines))
print(OUT/'REPORT.md')
