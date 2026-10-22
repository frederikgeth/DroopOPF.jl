# S1 reference: ARPA-E GOC Challenge 1, Network Model 01, Scenario 02

This adds the 500-bus PSS/E case and its upstream AC OPF and AC SCOPF reference solutions to S1. The source files remain in their original formats under `scenario_02/`; see the [case provenance and file guide](README.md) and [full results index](results/README.md).

The parsed case has 500 buses, 90 generator records (51 online), 599 branch circuits (593 online: 468 lines and 131 transformers), and 17 switched shunts. The base is 100 MVA. The case provides voltage bounds, P/Q capability bounds, transformer ratios, branch thermal ratings A/B/C, and branch angle-difference limits. Across this RAW import, bus voltage limits are 0.90–1.10 p.u. and branch angle limits are approximately −60° to +60°. The CSVs contain the thresholds and operating points for every imported device, including offline generators and circuits.

Both AC models solved locally with the upstream PMSC formulation and Ipopt settings (`tol=1e-6`, `print_level=0`). The AC OPF objective is **27,564.9207** GOC cost units. The fixed-point AC SCOPF objective is **33,193.9178** after four iterations, about 20.4% above the OPF objective. The SCOPF holds transformer taps and shunt admittances at their case values and uses the source `.inl` generator response rules. Its converged master includes a generator outage, one transformer outage, and two line outages; all five solved states (base plus four contingencies) are retained.

| Margin check | AC OPF base point | SCOPF base point | SCOPF contingencies |
|---|---:|---:|---:|
| Lowest voltage and distance above Vmin | 1.04012 p.u. at bus 492; +0.14012 p.u. | 0.93302 p.u. at bus 182; +0.03302 p.u. | 0.92774 p.u. at bus 182; +0.02774 p.u. |
| Highest voltage and distance below Vmax | 1.10000 p.u. at bus 144; essentially 0 | 1.10000 p.u. at bus 144; essentially 0 | 1.10000 p.u. at bus 144; essentially 0 |
| Maximum apparent branch flow | 220.00 / 220.00 MVA on branch 309 (rate A) | 315.41 / 597.00 MVA on branch 532 (rate C) | 145.00 / 145.00 MVA on branch 73 (rate C), transformer outage case |
| Closest generator P bound | generator 14 at Pmin 231.54 MW; within solver tolerance | generator 78 at Pmax 94.379 MW; within solver tolerance | generator 79 exceeds Pmax by 58.56 MW in the generator-outage state |
| Closest generator Q bound | generator 71 at Qmax, within 0.00005 MVAr | generator 78 at Qmin, within solver tolerance | generator 71 exceeds Qmax by 23.66 MVAr in the transformer-outage state |

Branch thermal limits are enforced on apparent power at both ends. OPF uses rate A, while the SCOPF contingency networks use rate C. The tightest SCOPF branch loading is effectively 100% of rate C (the maximum numerical overshoot is about 2.5×10⁻⁷ MVA). All branch angle limits and margins are in the branch CSVs.

One material qualification: the upstream SCOPF model makes contingency generator power variables unbounded (`bounded=false`). The base point respects generator P/Q bounds within numerical tolerance, but some contingency dispatches exceed those equipment limits, as the negative margins above show. Therefore its `LOCALLY_SOLVED` status and no-new-contingencies fixed point should not be read as proof that every generator capability limit is satisfied in every contingency. The solver log also reports some active contingencies as still insecure during intermediate checks. This is the source formulation reproduced as requested.

For all 90 generator records and their OPF/SCOPF dispatches, see [`generator_solution.csv`](results/generator_solution.csv). Bus voltages and limits are in [`bus_voltage.csv`](results/bus_voltage.csv). Every line and transformer rating, fixed tap, flow, and angle margin is in [`branch_solution.csv`](results/branch_solution.csv); transformer-only rows are in [`transformer_solution.csv`](results/transformer_solution.csv). The 17 shunt records and their fixed susceptance data are in [`shunt_data.csv`](results/shunt_data.csv). Per-contingency bus, generator, and branch details are in the `scopf_*_scenarios.csv` files. Full numerical solver outputs are in the JSON files under `results/`.
