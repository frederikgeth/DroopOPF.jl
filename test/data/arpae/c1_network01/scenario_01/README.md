# ARPA-E GOC Challenge 1, Network Model 01, Scenario 01

This is the original IEEE 14-bus Challenge 1 `scenario_01` input set from the LANL-ANSI PowerModelsSecurityConstrained.jl test data. The original PSS/E / Challenge 1 files are preserved unchanged: `case.raw`, `case.con`, `case.inl`, `case.rop`, and `solution1.txt`.

Source: [PowerModelsSecurityConstrained.jl, test/data/c1/scenario_01](https://github.com/lanl-ansi/PowerModelsSecurityConstrained.jl/tree/master/test/data/c1/scenario_01). The upstream AC OPF test expects objective 14676.95 and the AC contingency-cut SCOPF test expects the same objective, both with `LOCALLY_SOLVED` termination. See the project-level result indexes under `results/scenario_01/`.

The untouched source case remains the benchmark reference. The current S1/S2 study variant is kept separately in `../scenario_01_pmin0_qsym/`: it sets every generator Pmin to zero and symmetrizes the Q range while retaining original limits in a CSV. The earlier Pmin-zero-only copy remains in `../scenario_01_pmin0/` with its historical results.
