# Scenario 01 S1 Pmin-zero variant

This derived case copies the IEEE 14-bus Challenge 1 Scenario 01 inputs. The original source case remains unchanged in `../scenario_01/`. In `case.raw`, the PSS/E generator PB field (minimum active power) is set to 0 MW for all six generator records, including the offline record; all other input files are copied byte-for-byte. The S1 Pmin-zero OPF and SCOPF runs are retained under `../results/scenario_01_pmin0/`.
