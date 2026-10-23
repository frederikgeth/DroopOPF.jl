# Third-party data and dependencies

The library's BSD-3-Clause license does not replace third-party terms.

- PGLib-OPF small cases: CC BY 4.0, attribution and modifications in
  `test/data/pglib/README.md` and `provenance.json`; full license in that directory.
- PSS/E 34 fixture: unchanged VeraGrid file, MPL-2.0; pinned upstream source and
  SHA-256 in `test/data/psse/PROVENANCE.json`, license in `VeraGrid-LICENSE.md`.
- ARPA-E Challenge 1 14-bus RAW: public test fixture distributed by LANL-ANSI
  PowerModelsSecurityConstrained.jl. Source attribution and the upstream
  BSD-3 license notice are retained in `test/data/arpae/`.
- Julia solver dependencies retain their respective licenses and are installed
  through Julia Pkg, not vendored into this source distribution.

Optional research archives retain historical source/provenance records. They are
separate research materials and are not all relicensed under the library license.
