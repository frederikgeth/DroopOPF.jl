# Validation evidence register

The [milestone index](milestones.md) is the clean entry point. Read [reports](validation_reports.md), [tables](validation_tables.md) or [figures](validation_figures.md) independently.

## What can be shared

Curated summaries only; full private archives, network inputs and solver logs are not bundled. No upload or publication is performed by generation.

The portable HTML bundle has `index.html`, `reports.html`, `tables.html`, `figures.html`, `provenance.html`, the curated JSON catalogue, three selected figures and a SHA-256 manifest. It works offline. Share the complete ZIP so relative links and images stay together. The full research archives, network inputs, solver logs and unfinished campaign payloads are excluded.

Build or refresh the documentation and local bundle:

```sh
python3 tools/docs/build_validation_hub.py --bundle release/validation-share-20261026
python3 tools/docs/build_validation_hub.py --check
```

The command creates a local reviewable bundle; it does not upload, email or publish it. Full originals remain available through the [private archive restoration workflow](research.md). Hashes identify originals but do not make those private files publicly reproducible.

## Source identities

The catalogue is dated 2026-10-26. [Download the catalogue](assets/validation/catalog.json) for full SHA-256 values and machine-readable definitions, findings and figure captions. [The P2 compact summary](assets/validation/summary.json) also records the selected result, replay and sealed-manifest identities.

| Label | Source locator | Availability | SHA-256 prefix |
| --- | --- | --- | --- |
| M1 | `docs/src/validation.md` | repository | `6bf9c9a258bd7cca…` |
| M2 | `docs/src/scopf.md` | repository | `2dfc307ebe466925…` |
| M3 | `docs/src/droop_optimization.md` | repository | `1db6fbafb6078838…` |
| M4 | `docs/src/robustness.md` | repository | `ddda2c0a6e76fc99…` |
| M5 | `ROADMAP.md` | private archive | `7f653a70aa1570de…` |
| M6 | `ROADMAP.md` | private archive | `7f653a70aa1570de…` |
| M7 | `docs/src/equipment_optimization.md` | repository | `35218d735075e338…` |
| M7 | `docs/src/assets/validation/summary.json` | repository | `b25b878463d18720…` |
| M7 | `release/ccopt_case_study_20261026/REPORT.md` | private package | `22fd08d5fb43312f…` |
| M8 | `ROADMAP.md` | private archive | `7f653a70aa1570de…` |
| M9 | `ROADMAP.md` | private archive | `7f653a70aa1570de…` |
| M10 | `docs/src/m10_audit.md` | private archive | `96c2ef988e9b5125…` |
| S1 | `docs/src/s1_closeout.md` | private archive | `675718bda1515747…` |
| S2 | `docs/src/s2_14bus.md` | private archive | `7dff605b7d9e3de6…` |
| S2 | `docs/src/release_scope.md` | repository | `c334271977904b99…` |
| P0 | `ROADMAP.md` | private archive | `7f653a70aa1570de…` |
| P1 | `ROADMAP.md` | private archive | `7f653a70aa1570de…` |
| P2 | `docs/src/assets/validation/summary.json` | repository | `b25b878463d18720…` |
| P2 | `docs/src/release_scope.md` | repository | `c334271977904b99…` |
| P2 | `artifacts/p2_targeted_relaxations_20261023/joint-five/result.json` | private campaign | `8d0bc3d70e485d23…` |
| P3 | `docs/src/multi_period.md` | repository | `7705e8223d152a01…` |
| P3 | `docs/src/psse.md` | repository | `e00238b90f368cc6…` |

## Maintenance

Update `docs/src/assets/validation/catalog.json` when evidence changes, retain the source identity and campaign policy, then regenerate these pages. New physical/control policies require a new campaign record. Preserve failed attempts and distinguish an implementation milestone from study closure. Current deadband results remain separate from historical S1/S2 closure until the new campaign is finalized.
