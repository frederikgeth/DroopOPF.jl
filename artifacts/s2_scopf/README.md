# Retained security reference cases

The imported 14-bus and 500-bus OPF/SCOPF reference results remain in `ieee14/` and `ieee500/`. These references are separate from the completed base-case S1 study. A new SCOPF campaign requires the equipment-policy confirmation described in `AGENTS.md`.

The user-confirmed native 14-bus campaign is retained separately under
[`ieee14_native/`](ieee14_native/REPORT.md): 24 connected eligible outages,
9/9 accepted solver runs and 157 independently replayed states. Its islanding
exclusion and exact control/limit contract are explicit. S1 remains closed;
the imported references above remain unchanged.
