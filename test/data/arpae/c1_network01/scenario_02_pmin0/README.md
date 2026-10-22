# Scenario 02 S1 Pmin-zero variant

This is a derived copy of the original Scenario 02 500-bus Network Model 01 case. The original source case remains unchanged in `../scenario_02/`. In this variant, the PSS/E generator PB field (minimum active power) is set to 0.0 MW for all 90 generator records, including offline units. No other case fields are intentionally changed. The `.con`, `.inl`, `.rop`, and `solution1.txt` files are byte-identical copies from the original scenario.

The Pmin-zero OPF results are in `../results/scenario_02_pmin0/`.
