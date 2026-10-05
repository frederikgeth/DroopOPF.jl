# Existing-shunt continuous-envelope family matrix

This checkpointed matrix replaces every available nonzero-B source fixed shunt by a continuous `alpha` envelope, `G=alpha*G0`, `B=alpha*B0`, `0<=alpha<=1`. It adds no compensation capacity and makes no claim that the source hardware is switchable. Discrete-step and AVR post-checks remain deferred. All converted devices start at `alpha=1`; nominal admittance and anchor feasibility are verified before solving.

The frozen one-reset policy, epsilon `1e-6`, three starts, and strict exact-droop gate `1e-5` are unchanged. A retry is warm-started only from the finite compatible iterate of its own first attempt with solver-specific dual reset. Cells and declared starts are otherwise independent: no accepted solution is propagated to another family, load, start, network, or backend. The `1e-2` result is diagnostic only; every row retains its raw mismatch. Load scope: **nominal plus raw-qualified 1.03 stress**. Status: **complete** (192/192 cells).

| Free families | Ipopt strict / diag | MadNLP strict / diag | Combined strict / diag |
|---|---:|---:|---:|
| fixed | 7/7 / 12 | 5/6 / 12 | 12/13 / 24 |
| droop | 8/8 / 12 | 8/8 / 12 | 16/16 / 24 |
| tap | 8/9 / 12 | 7/10 / 12 | 15/19 / 24 |
| shunt | 7/7 / 12 | 7/8 / 12 | 14/15 / 24 |
| tap_shunt | 3/5 / 12 | 4/12 / 12 | 7/17 / 24 |
| tap_droop | 7/7 / 12 | 5/6 / 12 | 12/13 / 24 |
| shunt_droop | 8/8 / 12 | 9/9 / 12 | 17/17 / 24 |
| joint | 5/6 / 12 | 1/7 / 12 | 6/13 / 24 |

Cell notation is `strict/diagnostic / attempts`; diagnostic acceptance keeps every non-droop gate unchanged.

| Solver/network/load/family | Strict | Diagnostic | Attempts | Starts strict (A/L/H) | Raw mismatch range (pu) |
|---|---:|---:|---:|---|---|
| ipopt/118/1.0/droop | 3 | 3 | 3 | ✓/✓/✓ | 5.134781488891349e-16–5.134781488891349e-16 |
| ipopt/118/1.0/fixed | 3 | 3 | 3 | ✓/✓/✓ | 5.134781488891349e-16–5.134781488891349e-16 |
| ipopt/118/1.0/joint | 2 | 2 | 3 | ✓/–/✓ | 2.3804153093109903e-12–0.07480396722797611 |
| ipopt/118/1.0/shunt | 3 | 3 | 3 | ✓/✓/✓ | 5.134781488891349e-16–5.134781488891349e-16 |
| ipopt/118/1.0/shunt_droop | 3 | 3 | 3 | ✓/✓/✓ | 5.134781488891349e-16–5.134781488891349e-16 |
| ipopt/118/1.0/tap | 2 | 3 | 3 | –/✓/✓ | 6.418971735533407e-7–1.2710465079279754e-5 |
| ipopt/118/1.0/tap_droop | 2 | 2 | 3 | ✓/–/✓ | 2.8590059381883304e-6–0.04416544408981338 |
| ipopt/118/1.0/tap_shunt | 1 | 2 | 3 | –/✓/– | 2.5729418595688003e-14–0.1485346731489482 |
| ipopt/118/1.03/droop | 3 | 3 | 3 | ✓/✓/✓ | 7.301104165691186e-13–2.474439070310197e-9 |
| ipopt/118/1.03/fixed | 3 | 3 | 3 | ✓/✓/✓ | 1.6431300764452317e-14–2.7422508708241367e-14 |
| ipopt/118/1.03/joint | 1 | 2 | 3 | ✓/–/– | 9.623442334516508e-6–0.062243468782815725 |
| ipopt/118/1.03/shunt | 3 | 3 | 3 | ✓/✓/✓ | 2.5231899902777855e-13–2.603334214867914e-13 |
| ipopt/118/1.03/shunt_droop | 3 | 3 | 3 | ✓/✓/✓ | 2.2130258478386677e-6–2.2130264584405146e-6 |
| ipopt/118/1.03/tap | 2 | 2 | 3 | ✓/✓/– | 7.826529755394773e-7–0.1659948014064867 |
| ipopt/118/1.03/tap_droop | 2 | 2 | 3 | ✓/–/✓ | 7.983714934295394e-7–0.08414645805584223 |
| ipopt/118/1.03/tap_shunt | 2 | 3 | 3 | ✓/–/✓ | 7.717095141246411e-7–3.289396503686204e-5 |
| ipopt/300/1.0/droop | 2 | 2 | 3 | ✓/✓/– | 1.7763568394002505e-15–5.799662579270004e-6 |
| ipopt/300/1.0/fixed | 1 | 1 | 3 | ✓/–/– | 1.7763568394002505e-15–6.072585841065958e-6 |
| ipopt/300/1.0/joint | 0 | 0 | 3 | –/–/– | 0.005530866594548656–0.23688623302119627 |
| ipopt/300/1.0/shunt | 1 | 1 | 3 | ✓/–/– | 1.7763568394002505e-15–5.759023983697986e-6 |
| ipopt/300/1.0/shunt_droop | 2 | 2 | 3 | ✓/–/✓ | 1.7763568394002505e-15–3.4606528753755583e-10 |
| ipopt/300/1.0/tap | 2 | 2 | 3 | ✓/✓/– | 4.78354743228826e-6–0.5293179718451047 |
| ipopt/300/1.0/tap_droop | 2 | 2 | 3 | ✓/✓/– | 1.767382529216377e-8–1.3131013777346041 |
| ipopt/300/1.0/tap_shunt | 0 | 0 | 3 | –/–/– | 0.04925195764892931–0.37214311907949815 |
| ipopt/300/1.03/droop | 0 | 0 | 3 | –/–/– | 3.5369682105379496e-6–0.05367777869586321 |
| ipopt/300/1.03/fixed | 0 | 0 | 3 | –/–/– | 2.0431434322176756e-12–2.835090137098817e-5 |
| ipopt/300/1.03/joint | 2 | 2 | 3 | –/✓/✓ | 3.9689176603019405e-6–1.1798076868789833 |
| ipopt/300/1.03/shunt | 0 | 0 | 3 | –/–/– | 1.1019294963832138e-5–0.015613336536933087 |
| ipopt/300/1.03/shunt_droop | 0 | 0 | 3 | –/–/– | 3.973008588786797e-10–0.09495195702857595 |
| ipopt/300/1.03/tap | 2 | 2 | 3 | ✓/–/✓ | 1.296101633907476e-6–0.10437173346590933 |
| ipopt/300/1.03/tap_droop | 1 | 1 | 3 | –/–/✓ | 2.4540858964972045e-6–1.3601544276913708 |
| ipopt/300/1.03/tap_shunt | 0 | 0 | 3 | –/–/– | 2.8486809144911973e-6–1.0991688494280734 |
| madnlp/118/1.0/droop | 3 | 3 | 3 | ✓/✓/✓ | 5.134781488891349e-16–3.40769079620884e-14 |
| madnlp/118/1.0/fixed | 2 | 3 | 3 | –/✓/✓ | 2.5851716600744368e-14–1.9349668940210618e-5 |
| madnlp/118/1.0/joint | 0 | 3 | 3 | –/–/– | 3.1957099469570593e-5–5.0414452974378854e-5 |
| madnlp/118/1.0/shunt | 2 | 3 | 3 | –/✓/✓ | 2.456368441983159e-14–2.0600083866395558e-5 |
| madnlp/118/1.0/shunt_droop | 3 | 3 | 3 | ✓/✓/✓ | 5.134781488891349e-16–2.533390164316529e-14 |
| madnlp/118/1.0/tap | 1 | 3 | 3 | ✓/–/– | 2.5979218776228663e-14–3.269063861477406e-5 |
| madnlp/118/1.0/tap_droop | 2 | 3 | 3 | ✓/✓/– | 7.988000316438287e-6–1.2571863961863272e-5 |
| madnlp/118/1.0/tap_shunt | 0 | 3 | 3 | –/–/– | 3.819080840421207e-5–3.9460354313569646e-5 |
| madnlp/118/1.03/droop | 2 | 2 | 3 | –/✓/✓ | 4.6601611458640946e-14–4.741346204539809e-14 |
| madnlp/118/1.03/fixed | 2 | 2 | 3 | –/✓/✓ | 1.5432100042289676e-14–3.33361810378463e-14 |
| madnlp/118/1.03/joint | 1 | 2 | 3 | –/✓/– | 3.8191672047105385e-14–6.160640365293624e-5 |
| madnlp/118/1.03/shunt | 3 | 3 | 3 | ✓/✓/✓ | 2.6145752229922437e-14–8.838624276918949e-13 |
| madnlp/118/1.03/shunt_droop | 3 | 3 | 3 | ✓/✓/✓ | 1.7430501486614958e-14–7.98666688339722e-14 |
| madnlp/118/1.03/tap | 2 | 3 | 3 | ✓/✓/– | 4.3146042294495146e-14–3.78969117591256e-5 |
| madnlp/118/1.03/tap_droop | 2 | 2 | 3 | –/✓/✓ | 1.1712852909795402e-14–8.71161557047806e-6 |
| madnlp/118/1.03/tap_shunt | 1 | 3 | 3 | –/✓/– | 2.153088280221205e-6–2.1368472704397234e-5 |
| madnlp/300/1.0/droop | 3 | 3 | 3 | ✓/✓/✓ | 1.7763568394002505e-15–3.019806626980426e-14 |
| madnlp/300/1.0/fixed | 1 | 1 | 3 | ✓/–/– | 1.7763568394002505e-15–2.8821389719269064e-12 |
| madnlp/300/1.0/joint | 0 | 2 | 3 | –/–/– | 4.621372369517651e-5–5.8711895113194856e-5 |
| madnlp/300/1.0/shunt | 2 | 2 | 3 | ✓/–/✓ | 1.7763568394002505e-15–7.797096301942474e-12 |
| madnlp/300/1.0/shunt_droop | 3 | 3 | 3 | ✓/✓/✓ | 1.7763568394002505e-15–3.9680259078522795e-11 |
| madnlp/300/1.0/tap | 2 | 2 | 3 | ✓/–/✓ | 5.062616992290714e-14–7.622646593252735e-5 |
| madnlp/300/1.0/tap_droop | 1 | 1 | 3 | ✓/–/– | 2.4868995751603507e-14–0.0028049930445546156 |
| madnlp/300/1.0/tap_shunt | 1 | 3 | 3 | –/–/✓ | 9.370131409461302e-6–4.336928003345619e-5 |
| madnlp/300/1.03/droop | 0 | 0 | 3 | –/–/– | 3.305199656344904e-5–0.03937089972781238 |
| madnlp/300/1.03/fixed | 0 | 0 | 3 | –/–/– | 0.002769099753243076–0.15748274913522387 |
| madnlp/300/1.03/joint | 0 | 0 | 3 | –/–/– | 1.114519899081401e-5–0.0002774450128661954 |
| madnlp/300/1.03/shunt | 0 | 0 | 3 | –/–/– | 0.0005966864491557811–0.09003319794422882 |
| madnlp/300/1.03/shunt_droop | 0 | 0 | 3 | –/–/– | 0.0015891725634902265–0.11853133855384779 |
| madnlp/300/1.03/tap | 2 | 2 | 3 | ✓/–/✓ | 3.2862601528904634e-14–1.7118271843918897e-5 |
| madnlp/300/1.03/tap_droop | 0 | 0 | 3 | –/–/– | 4.3520742565306136e-14–1.0750904933853889e-5 |
| madnlp/300/1.03/tap_shunt | 2 | 3 | 3 | ✓/–/✓ | 4.969739338694934e-6–6.641577388655229e-5 |

Failures remain algorithmic evidence, not infeasibility certificates. The 1.05 load study, when present, is a separately labelled near-limit challenge because the untouched IEEE-300 source case failed at 1.05 after succeeding through 1.04.
