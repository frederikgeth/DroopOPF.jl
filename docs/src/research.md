# Optional research evidence

The software release does not include the historical `artifacts/` tree. Its
contents, including failed attempts, have been preserved in verified local
archives by the maintainer. **Those archives are not public release assets.**
They are not required to install, test or use the library. Archive publication
is not part of this release, at the maintainer’s request.

The following inventory documents the local preservation format; it is not a
list of downloads supplied with this release.

| Asset | Contents |
|---|---|
| `campaigns.tar.gz` | Full historical campaign outputs and sealed manifests |
| `research-docs.tar.gz` | Original study reports, figure galleries, roadmap and historical notes |
| `research-drivers.tar.gz` | Exact source, tests, full study inputs, example drivers and environment snapshot |
| `evidence-index.json` | SHA-256 archive checksums, file counts and verification status |
| `*-files.json` | Original relative paths and per-file SHA-256 hashes |

Archives preserve repository-relative paths. Restore them into a **separate
research directory**, not over an installed release: historical source and docs
can differ from the release. Verify archive checksums before extraction, then
verify individual files against the corresponding file index. Sealed campaign
manifests provide additional original verification. Some old scripts contain
machine-specific paths; restoration does not promise turnkey reruns of every
historical workflow. No campaign runs during package installation or tests.

The latest evidence is `artifacts/p2_targeted_relaxations_20261023/REPORT.md`:
389/389 connected contingencies, five periods, 390 selected result files replayed,
unchanged P2 physical limits. Earlier reports retain their contemporary failures
and policies; use the [release scope](release_scope.md) for current status.

S1/S2/P1/P2/P3 are study and development labels, not required downloads.
The original S2 campaign remains paused. Archived source snapshots are retained
for reproducibility, not as alternative supported implementations.

## Restore a local archived campaign

The maintainer can restore a campaign into a new directory without overwriting
an existing study:

```sh
python3 tools/release/restore_campaign.py /path/to/research-v0.10.0-rc1 \
  psse_saved_solution_check_20261022 /path/to/restored-campaign
```

The command verifies the archive SHA-256 and every selected file before making
the restored directory available. It refuses an existing destination.

A small, curated [validation reference gallery](validation_evidence.md) is bundled
with the documentation. It contains selected summaries and figures, not full
research archives, network inputs or solver logs. The historical roadmap is
archived; the public [milestone index](milestones.md) provides current navigation.
