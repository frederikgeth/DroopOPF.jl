# v0.10.0-rc1 — compact software and reproducible research

This release candidate separates installable software from historical research
outputs. The source tree retains the library, all small-network tests, example
drivers and operational documentation. Large results, study figures and full
benchmark inputs are preserved in separate checksum-verified local archives. Those archives are
not included among the public release assets.

The release includes limit-aware active response, shared reactive design,
multi-period mixed AVR/droop security models, apparent-power constraints,
reserve/feasibility objective policies, and the PSS/E RAW adapter and saved-state
checker. Existing solver dependencies and numerical semantics are retained.

The latest five-period mixed 500-bus study qualifies all 389 connected outages
under its stated normal-limit, full-load P2 policy. It required control redesign
and numerical recovery, without physical-limit relaxation. This does not close
full resource/loss optimization or certify dynamics, islanding or discrete
controls. Native PSS/E 36 exporter qualification remains pending.

## Compatibility

The current active-response default is limit-aware saturation redistribution.
Historical proportional-response contracts remain explicit for replay. New
serialized study fields and reactive capability settings should be interpreted
with the saved policy, not silently migrated. See the operational documentation
and optional research records for precise contracts.

## Packaging

Generated artifacts, local manifests, caches and build outputs are excluded.
Git history is not rewritten; use the source archive for a small download.
The package remains installed from GitHub or a source archive, not newly
registered in Julia General by this release. No numerical campaign is launched
by installation. See `release-validation.json` for actual release checks.
