# IEEE 118 CCOpt placement diagnostic

All runs use the same imported IEEE 118 overlay, +5% load, three declared starts, exact complementarity droop, and the same tight CCOpt budget. Only the one free control location differs. This is a diagnostic comparison, not a topology or equipment-model change.

| Placement | Valid | Attempts | Worst exact-droop residual / 1e-5 criterion |
|---|---:|---:|---:|
| bank_colocated | 3 | 3 | 5.916370837735427e-6 / 0.5916370837735426× |
| bank_remote | 1 | 3 | 0.008824821784676806 / 882.4821784676806× |
| tap_remote | 2 | 3 | 0.00791074839914055 / 791.0748399140549× |
| tap_terminal | 0 | 3 | 1.663444786477973e-5 / 1.663444786477973× |
