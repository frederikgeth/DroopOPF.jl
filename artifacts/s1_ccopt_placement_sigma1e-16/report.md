# IEEE 118 CCOpt placement diagnostic

All runs use the same imported IEEE 118 overlay, +5% load, three declared starts, exact complementarity droop, and one declared CCOpt accuracy profile/budget. Only the one free control location differs. This is a diagnostic comparison, not a topology or equipment-model change.

| Placement | Valid | Attempts | Worst exact-droop residual / 1e-5 criterion |
|---|---:|---:|---:|
| bank_colocated | 2 | 3 | 5.917370241199926e-8 / 0.005917370241199925× |
| bank_remote | 1 | 3 | 0.010091182001706736 / 1009.1182001706735× |
| tap_remote | 1 | 3 | 2.9225172979568947e-8 / 0.0029225172979568943× |
| tap_terminal | 1 | 3 | 0.000109557635867185 / 10.955763586718499× |
