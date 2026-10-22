# ARPA-E Grid Optimization Competition 1 — Network Model 01

Challenge 1 Network Model 01 Scenario 01 (IEEE 14-bus) and Scenario 02 (500-bus) inputs used by the LANL-ANSI PowerModelsSecurityConstrained.jl tests are preserved here in their original PSS/E / Challenge 1 formats. The current S1/S2 sequence starts with the 14-bus case in `scenario_01/`, then advances to the 500-bus case in `scenario_02/` after the small-case reproduction is established.

- `scenario_01/`: IEEE 14-bus source case and PSS/E / Challenge 1 files
- `scenario_02/case.raw`: 500-bus PSS/E RAW network model
- `scenario_02/case.con`: contingency definitions
- `scenario_02/case.inl`: generator participation/inertia data
- `scenario_02/case.rop`: generator operating parameters and costs
- `scenario_02/solution1.txt`: upstream Challenge 1 first-stage operating point / initialization
- `inputfiles.ini`: parser configuration for the source PMSC package
- `report.md`: S1 case and solution summary
- `results/`: AC OPF and AC SCOPF results, component tables, and margin reports

Sources: [scenario_01](https://github.com/lanl-ansi/PowerModelsSecurityConstrained.jl/tree/master/test/data/c1/scenario_01) and [scenario_02](https://github.com/lanl-ansi/PowerModelsSecurityConstrained.jl/tree/master/test/data/c1/scenario_02). The upstream `test/opf.jl` and `test/scopf.jl` include AC OPF and AC contingency-cut SCOPF tests for both cases.

The source files are unchanged. The project’s native MATPOWER loader does not parse PSS/E RAW directly; the reference results were reproduced using the upstream PMSC parser and formulation. See [`examples/s1_arpae500_reference.jl`](../../../../examples/s1_arpae500_reference.jl) for the runner.

For the current S1/S2 study setup, [`scenario_01_pmin0_qsym/`](scenario_01_pmin0_qsym/README.md) and [`scenario_02_pmin0_qsym/`](scenario_02_pmin0_qsym/README.md) preserve each source case while setting every generator's Pmin to 0 MW and making Q limits symmetric at the larger absolute original bound. Each derived case includes `generator_limits_original_and_study.csv`, so the original bounds remain available generator by generator. Their AC OPF and SCOPF solutions and margins are saved under [`results/scenario_01_pmin0_qsym/`](results/scenario_01_pmin0_qsym/README.md) and [`results/scenario_02_pmin0_qsym/`](results/scenario_02_pmin0_qsym/README.md). The previous Pmin-zero-only 14- and 500-bus runs remain under `results/scenario_01_pmin0/` and `results/scenario_02_pmin0/`; those solutions do not apply to the new symmetric-Q setup.
