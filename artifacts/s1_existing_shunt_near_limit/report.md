# Existing-shunt continuous-envelope family matrix

This checkpointed matrix replaces every available nonzero-B source fixed shunt by a continuous `alpha` envelope, `G=alpha*G0`, `B=alpha*B0`, `0<=alpha<=1`. It adds no compensation capacity and makes no claim that the source hardware is switchable. Discrete-step and AVR post-checks remain deferred. All converted devices start at `alpha=1`; nominal admittance and anchor feasibility are verified before solving.

The frozen one-reset policy, epsilon `1e-6`, three starts, and strict exact-droop gate `1e-5` are unchanged. A retry is warm-started only from the finite compatible iterate of its own first attempt with solver-specific dual reset. Cells and declared starts are otherwise independent: no accepted solution is propagated to another family, load, start, network, or backend. The `1e-2` result is diagnostic only; every row retains its raw mismatch. Load scope: **unqualified 1.05 near-limit challenge**. Status: **complete** (96/96 cells).

| Free families | Ipopt strict / diag | MadNLP strict / diag | Combined strict / diag |
|---|---:|---:|---:|
| fixed | 3/3 / 6 | 3/3 / 6 | 6/6 / 12 |
| droop | 0/3 / 6 | 3/3 / 6 | 3/6 / 12 |
| tap | 3/3 / 6 | 3/5 / 6 | 6/8 / 12 |
| shunt | 3/3 / 6 | 2/2 / 6 | 5/5 / 12 |
| tap_shunt | 6/6 / 6 | 1/3 / 6 | 7/9 / 12 |
| tap_droop | 4/4 / 6 | 4/5 / 6 | 8/9 / 12 |
| shunt_droop | 3/3 / 6 | 3/3 / 6 | 6/6 / 12 |
| joint | 2/3 / 6 | 2/4 / 6 | 4/7 / 12 |

Cell notation is `strict/diagnostic / attempts`; diagnostic acceptance keeps every non-droop gate unchanged.

| Solver/network/load/family | Strict | Diagnostic | Attempts | Starts strict (A/L/H) | Raw mismatch range (pu) |
|---|---:|---:|---:|---|---|
| ipopt/118/1.05/droop | 0 | 3 | 3 | –/–/– | 6.729626694885853e-5–6.729626714543739e-5 |
| ipopt/118/1.05/fixed | 3 | 3 | 3 | ✓/✓/✓ | 1.3156142841808105e-14–1.709743457922741e-14 |
| ipopt/118/1.05/joint | 1 | 2 | 3 | ✓/–/– | 8.105925129453517e-7–0.001758442722555209 |
| ipopt/118/1.05/shunt | 3 | 3 | 3 | ✓/✓/✓ | 1.709743457922741e-14–2.781108676686017e-14 |
| ipopt/118/1.05/shunt_droop | 3 | 3 | 3 | ✓/✓/✓ | 7.588374373312945e-13–2.3180981023607217e-9 |
| ipopt/118/1.05/tap | 1 | 1 | 3 | –/–/✓ | 2.5815133572471005e-9–0.11213267920968485 |
| ipopt/118/1.05/tap_droop | 1 | 1 | 3 | –/✓/– | 8.083524414836951e-7–10.055746169166428 |
| ipopt/118/1.05/tap_shunt | 3 | 3 | 3 | ✓/✓/✓ | 7.57121358566093e-7–7.719311009152241e-7 |
| ipopt/300/1.05/droop | 0 | 0 | 3 | –/–/– | 0.004640673441018928–0.02959540273256578 |
| ipopt/300/1.05/fixed | 0 | 0 | 3 | –/–/– | 2.265854170957482e-12–0.041364099843094304 |
| ipopt/300/1.05/joint | 1 | 1 | 3 | ✓/–/– | 3.2057043117816875e-6–3.2393284006614547 |
| ipopt/300/1.05/shunt | 0 | 0 | 3 | –/–/– | 1.3352041694503214e-11–0.01827995681758987 |
| ipopt/300/1.05/shunt_droop | 0 | 0 | 3 | –/–/– | 9.965195335581711e-12–0.012244665218988371 |
| ipopt/300/1.05/tap | 2 | 2 | 3 | –/✓/✓ | 1.7089629178457244e-7–0.3700017686289674 |
| ipopt/300/1.05/tap_droop | 3 | 3 | 3 | ✓/✓/✓ | 1.9316333985663903e-6–1.931838311541867e-6 |
| ipopt/300/1.05/tap_shunt | 3 | 3 | 3 | ✓/✓/✓ | 3.12054505369197e-6–3.12054505369197e-6 |
| madnlp/118/1.05/droop | 3 | 3 | 3 | ✓/✓/✓ | 3.250177904590146e-14–3.952393967665557e-14 |
| madnlp/118/1.05/fixed | 3 | 3 | 3 | ✓/✓/✓ | 3.48922279957975e-14–1.3969381207346032e-13 |
| madnlp/118/1.05/joint | 2 | 3 | 3 | ✓/–/✓ | 7.399636459126668e-14–5.988806424805926e-5 |
| madnlp/118/1.05/shunt | 2 | 2 | 3 | –/✓/✓ | 2.693678613496786e-14–5.695444116327053e-14 |
| madnlp/118/1.05/shunt_droop | 3 | 3 | 3 | ✓/✓/✓ | 2.4577562207639403e-14–6.777911565336581e-14 |
| madnlp/118/1.05/tap | 1 | 3 | 3 | –/✓/– | 7.815970093361102e-14–2.4138028643094778e-5 |
| madnlp/118/1.05/tap_droop | 3 | 3 | 3 | ✓/✓/✓ | 9.747758156208874e-14–6.306582659321158e-6 |
| madnlp/118/1.05/tap_shunt | 1 | 2 | 3 | –/✓/– | 2.3037127760971998e-14–1.89088156001202e-5 |
| madnlp/300/1.05/droop | 0 | 0 | 3 | –/–/– | 2.064293180836785e-12–2.4523272301735233e-11 |
| madnlp/300/1.05/fixed | 0 | 0 | 3 | –/–/– | 2.059852288738284e-12–0.0029233646973920446 |
| madnlp/300/1.05/joint | 0 | 1 | 3 | –/–/– | 5.588757555641255e-5–0.0009287040719744843 |
| madnlp/300/1.05/shunt | 0 | 0 | 3 | –/–/– | 1.9837465004002297e-12–0.019273046661884896 |
| madnlp/300/1.05/shunt_droop | 0 | 0 | 3 | –/–/– | 7.279732372467151e-13–0.010164638826886369 |
| madnlp/300/1.05/tap | 2 | 2 | 3 | ✓/–/✓ | 2.042810365310288e-14–7.460698725481052e-14 |
| madnlp/300/1.05/tap_droop | 1 | 2 | 3 | ✓/–/– | 3.197442310920451e-14–1.332515589091976e-5 |
| madnlp/300/1.05/tap_shunt | 0 | 1 | 3 | –/–/– | 1.7665735001504146e-6–8.639983375902105e-5 |

Failures remain algorithmic evidence, not infeasibility certificates. The 1.05 load study, when present, is a separately labelled near-limit challenge because the untouched IEEE-300 source case failed at 1.05 after succeeding through 1.04.
