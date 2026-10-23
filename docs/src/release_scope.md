# Release scope — v0.10.0-rc1

This is a software prerelease, not closure of all research milestones.

| Area | Released implementation | Qualification boundary |
|---|---|---|
| S1 | Base AC OPF and reactive/equipment design | Declared sampled 14/500-bus studies; original data assumptions apply |
| S2 | Shared security design and scenario assessment | Declared 14-bus scope closed; original 500-bus research remains paused |
| P1/P2 | Sparse models, validation, initialization and bounded scenario workflows | No general safe predictive skipping or full-catalogue resource/loss optimality claim |
| P3 multi-period | Shared curves, dispatch ramps, outage recourse and AVR schedules | Deterministic sampled steady states, no storage or dynamic trajectories |
| P3 parser | RAW 33/34/36 and saved-state replay | Strict AC subset; native v36 export qualification pending |
| Mixed controls | AVR and generic volt-var with apparent-power circles | Detailed synchronous-machine and GFL/GFM dynamics deferred |

The latest selected mixed 500-bus design uses 15 AVR and 36 droop units,
assumed S=Pmax/0.95, five hourly demand factors 90/100/105/100/90%, full load,
normal bounds, limit-aware active response and shared designed curves.
All 389 connected outages pass independent audits. Corrective controls remain
continuous: 131 taps, supplied +/-5% absolute envelope and <=0.025 supplied-ratio
movement; 11 banks within legal envelopes and <=two-section movement. The assumed
120-second settled stage is not a verified device delay. AVR targets are
preventive within each period and move <=0.01 pu/hour. No physical limits were
relaxed for the final recovery. The objective was feasibility, not a certified
minimum-loss or maximum-reserve solution.

Deferred: general island balancing, dynamic/small-signal validation, discrete
switching and verified device timing, current-limited GFL/GFM models, storage,
renewable availability, full coupled resource optimization and broad screening
qualification. The earlier full model used roughly 17 GiB RAM; separating saved
research files does not change that numerical memory requirement.

See [research evidence](research.md) for exact historical contracts and manifests.
