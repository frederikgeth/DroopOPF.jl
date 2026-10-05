# Existing shunts: continuous nominal qualification

Existing nonzero-B available shunts are replaced by continuous alpha-scaled G/B devices, initially alpha=1 and bounded by 0 and 1. Selection is an explicit benchmark assumption. No new compensation capacity is added. Discrete steps and AVR behavior are outside this study. Nominal admittance, intermediate G/B replay, and the original anchor are verified before solving.

Eight nominal anchor-start cells compare fixed settings with shunt-only freedom; this is qualification, not the full 192-cell matrix. Fixed droop curves remain active in both families.

| Cell | Valid | Final status |
|---|---:|---|
| public118-ipopt-fixed-existing | true | LOCALLY_SOLVED |
| public118-ipopt-shunt-existing | true | LOCALLY_SOLVED |
| public118-madnlp-fixed-existing | false | LOCALLY_SOLVED |
| public118-madnlp-shunt-existing | false | LOCALLY_SOLVED |
| public300-ipopt-fixed-existing | true | LOCALLY_SOLVED |
| public300-ipopt-shunt-existing | true | LOCALLY_SOLVED |
| public300-madnlp-fixed-existing | true | LOCALLY_SOLVED |
| public300-madnlp-shunt-existing | true | LOCALLY_SOLVED |
