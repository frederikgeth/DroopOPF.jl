# S1 smooth control-family isolation matrix

This checkpointed matrix uses the frozen Ipopt/MadNLP one-reset policy, epsilon `1e-6`, exact-droop tolerance `1e-5`, public 118/300 overlays, nominal/+5% loads, and anchor/flat-low/flat-high starts. Each family includes **all** controls of that type. `fixed` means *no free design variables*: the overlay's droop equalities remain active at their nominal anchor-derived settings, selected banks remain disconnected, and transformer ratios retain their source values. It is not the untouched PGLib OPF. No result replaces the original joint frozen decision.

Status: **complete** (192/192 cells).

## Aggregate acceptance

| Free families | Ipopt | MadNLP | Combined |
|---|---:|---:|---:|
| fixed | 7/12 | 6/12 | 13/24 |
| droop | 5/12 | 9/12 | 14/24 |
| tap | 7/12 | 6/12 | 13/24 |
| shunt | 9/12 | 7/12 | 16/24 |
| tap_shunt | 4/12 | 6/12 | 10/24 |
| tap_droop | 8/12 | 7/12 | 15/24 |
| shunt_droop | 7/12 | 8/12 | 15/24 |
| joint | 8/12 | 4/12 | 12/24 |

## Paired family effects

Each row adds exactly one free family. Positive values mean more accepted cells; they diagnose numerical interaction, not physical value.

| Added family / context | Ipopt delta | MadNLP delta | Combined delta |
|---|---:|---:|---:|
| droop to fixed | -2 | +3 | +1 |
| droop with tap | +1 | +1 | +2 |
| droop with shunt | -2 | +1 | -1 |
| droop with tap+shunt | +4 | -2 | +2 |
| tap to fixed | 0 | 0 | 0 |
| tap with droop | +3 | -2 | +1 |
| tap with shunt | -5 | -1 | -6 |
| tap with shunt+droop | +1 | -4 | -3 |
| shunt to fixed | +2 | +1 | +3 |
| shunt with droop | +2 | -1 | +1 |
| shunt with tap | -3 | 0 | -3 |
| shunt with tap+droop | 0 | -3 | -3 |

## Detailed slices

| Solver/network/load/family | Valid | Attempts | Start outcomes (A/L/H) |
|---|---:|---:|---|
| ipopt-118-load1.0-droop | 3 | 3 | ✓/✓/✓ |
| ipopt-118-load1.0-fixed | 3 | 3 | ✓/✓/✓ |
| ipopt-118-load1.0-joint | 3 | 3 | ✓/✓/✓ |
| ipopt-118-load1.0-shunt | 3 | 3 | ✓/✓/✓ |
| ipopt-118-load1.0-shunt_droop | 3 | 3 | ✓/✓/✓ |
| ipopt-118-load1.0-tap | 2 | 3 | –/✓/✓ |
| ipopt-118-load1.0-tap_droop | 2 | 3 | ✓/–/✓ |
| ipopt-118-load1.0-tap_shunt | 1 | 3 | –/–/✓ |
| ipopt-118-load1.05-droop | 0 | 3 | –/–/– |
| ipopt-118-load1.05-fixed | 3 | 3 | ✓/✓/✓ |
| ipopt-118-load1.05-joint | 1 | 3 | ✓/–/– |
| ipopt-118-load1.05-shunt | 3 | 3 | ✓/✓/✓ |
| ipopt-118-load1.05-shunt_droop | 3 | 3 | ✓/✓/✓ |
| ipopt-118-load1.05-tap | 1 | 3 | –/–/✓ |
| ipopt-118-load1.05-tap_droop | 1 | 3 | –/✓/– |
| ipopt-118-load1.05-tap_shunt | 1 | 3 | –/–/✓ |
| ipopt-300-load1.0-droop | 2 | 3 | ✓/✓/– |
| ipopt-300-load1.0-fixed | 1 | 3 | ✓/–/– |
| ipopt-300-load1.0-joint | 1 | 3 | ✓/–/– |
| ipopt-300-load1.0-shunt | 3 | 3 | ✓/✓/✓ |
| ipopt-300-load1.0-shunt_droop | 1 | 3 | ✓/–/– |
| ipopt-300-load1.0-tap | 2 | 3 | ✓/✓/– |
| ipopt-300-load1.0-tap_droop | 2 | 3 | ✓/✓/– |
| ipopt-300-load1.0-tap_shunt | 1 | 3 | ✓/–/– |
| ipopt-300-load1.05-droop | 0 | 3 | –/–/– |
| ipopt-300-load1.05-fixed | 0 | 3 | –/–/– |
| ipopt-300-load1.05-joint | 3 | 3 | ✓/✓/✓ |
| ipopt-300-load1.05-shunt | 0 | 3 | –/–/– |
| ipopt-300-load1.05-shunt_droop | 0 | 3 | –/–/– |
| ipopt-300-load1.05-tap | 2 | 3 | –/✓/✓ |
| ipopt-300-load1.05-tap_droop | 3 | 3 | ✓/✓/✓ |
| ipopt-300-load1.05-tap_shunt | 1 | 3 | ✓/–/– |
| madnlp-118-load1.0-droop | 3 | 3 | ✓/✓/✓ |
| madnlp-118-load1.0-fixed | 2 | 3 | –/✓/✓ |
| madnlp-118-load1.0-joint | 0 | 3 | –/–/– |
| madnlp-118-load1.0-shunt | 2 | 3 | –/✓/✓ |
| madnlp-118-load1.0-shunt_droop | 3 | 3 | ✓/✓/✓ |
| madnlp-118-load1.0-tap | 1 | 3 | ✓/–/– |
| madnlp-118-load1.0-tap_droop | 2 | 3 | ✓/✓/– |
| madnlp-118-load1.0-tap_shunt | 1 | 3 | –/–/✓ |
| madnlp-118-load1.05-droop | 3 | 3 | ✓/✓/✓ |
| madnlp-118-load1.05-fixed | 3 | 3 | ✓/✓/✓ |
| madnlp-118-load1.05-joint | 1 | 3 | –/✓/– |
| madnlp-118-load1.05-shunt | 3 | 3 | ✓/✓/✓ |
| madnlp-118-load1.05-shunt_droop | 3 | 3 | ✓/✓/✓ |
| madnlp-118-load1.05-tap | 1 | 3 | –/✓/– |
| madnlp-118-load1.05-tap_droop | 3 | 3 | ✓/✓/✓ |
| madnlp-118-load1.05-tap_shunt | 1 | 3 | –/✓/– |
| madnlp-300-load1.0-droop | 3 | 3 | ✓/✓/✓ |
| madnlp-300-load1.0-fixed | 1 | 3 | ✓/–/– |
| madnlp-300-load1.0-joint | 1 | 3 | ✓/–/– |
| madnlp-300-load1.0-shunt | 2 | 3 | ✓/✓/– |
| madnlp-300-load1.0-shunt_droop | 2 | 3 | ✓/–/✓ |
| madnlp-300-load1.0-tap | 2 | 3 | ✓/–/✓ |
| madnlp-300-load1.0-tap_droop | 1 | 3 | ✓/–/– |
| madnlp-300-load1.0-tap_shunt | 2 | 3 | ✓/✓/– |
| madnlp-300-load1.05-droop | 0 | 3 | –/–/– |
| madnlp-300-load1.05-fixed | 0 | 3 | –/–/– |
| madnlp-300-load1.05-joint | 2 | 3 | ✓/✓/– |
| madnlp-300-load1.05-shunt | 0 | 3 | –/–/– |
| madnlp-300-load1.05-shunt_droop | 0 | 3 | –/–/– |
| madnlp-300-load1.05-tap | 2 | 3 | ✓/–/✓ |
| madnlp-300-load1.05-tap_droop | 1 | 3 | ✓/–/– |
| madnlp-300-load1.05-tap_shunt | 2 | 3 | ✓/–/✓ |

Interpretation rule: a family that succeeds alone but degrades in a pair identifies an interaction; failure of the fixed family means the control family cannot be assigned primary blame for that cell. Failures remain algorithmic evidence, not infeasibility certificates.
