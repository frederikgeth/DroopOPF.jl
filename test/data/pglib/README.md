# PGLib-OPF regression data

The numerical tables are from PGLib-OPF **v23.07**, curated by the IEEE PES
Task Force on Benchmarks for Validation of Emerging Power System Algorithms.
Source URLs and changes are recorded in `provenance.json`. Comments have been
condensed and whitespace reformatted; numerical tables are preserved.

Data license: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/).
These files are not covered by the package's BSD software license.

- Case 3: Copyright (c) 2011 IEEE. B. C. Lesieutre, D. K. Molzahn,
  A. R. Borden and C. L. DeMarco, “Examining the Limits of the Application
  of Semidefinite Programming to Power Flow Problems,” Allerton, 2011,
  pp. 1492–1499.
- Case 5: Copyright (c) 2010 IEEE. F. Li and R. Bo, “Small Test Systems
  for Power System Economic Studies,” IEEE PES General Meeting, 2010.
  Created by Rui Bo in 2006, modified in 2010 and 2014.

The regression attaches a local droop control and uses DroopOPF's dispatch
deviation objective. Generator costs and branch angle-difference constraints
are not used by this adapter. These are modified problem formulations and
their objective values must not be compared to PGLib economic OPF baselines.

## S1 IEEE 118-bus source

The v23.07 IEEE 118 file is preserved without transformations, including its
original inline comments. Separate provenance is in
[provenance118.json](v23.07/provenance118.json). Copyright (c) 1999 Richard D.
Christie, University of Washington; CC BY 4.0, as retained in its header.
Its S1 baseline has no added droops or adjustable-bank overlay and uses the
project dispatch-deviation objective. Source angle bounds are audited after
solving, although the adapter does not impose them as optimization constraints.


## S1 IEEE 300-bus source

The v23.07 IEEE 300 file is preserved without transformations, with separate
[provenance300.json](v23.07/provenance300.json). Copyright (c) 1999 Richard D.
Christie, University of Washington; CC BY 4.0. Both public control studies use
separately recorded synthetic overlays, not inferred bank/tap specifications.
Original aggregate shunts and generator capabilities remain unchanged.
