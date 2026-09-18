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
