# S1 Pmin-zero variant: AC OPF reference

All 90 generator records in the derived case have `Pmin = 0 MW`; the original Scenario 02 file set and its original Pmin values remain preserved alongside it. The AC OPF was re-solved using the upstream PMSC/PowerModels formulation and Ipopt settings (`tol=1e-6`, `print_level=0`). It returned `LOCALLY_SOLVED` with objective **26,400.05575 GOC cost units**.

The bus voltage bounds remain 0.90–1.10 p.u. In this OPF, bus 321 is closest to Vmin at 0.98310 p.u. (0.08310 p.u. margin); bus 144 is at Vmax within solver tolerance. Branch 309 reaches its rate-A limit at approximately 220 MVA. Generator P/Q margins, all branch and transformer ratings/flows/angle bounds, and shunt source data are in the CSV files. Transformer taps and shunts are held fixed, matching the source AC OPF setup.

`summary.json` records the outcome and tightest limits. `network_model.json` contains the parsed case and thresholds; `opf_ac.json` contains the complete solved OPF state. SCOPF results will be added after the control configuration for this modified-Pmin SCOPF is confirmed.
