# M10 campaign policy

- One Julia process reuses compilation across all requested outages.
- Base Ipopt CPU/wall-time limit: 120.0 seconds.
- Per-outage Ipopt CPU/wall-time limit: 120.0 seconds.
- Per-outage Ipopt iteration limit: 1000.
- Every eligible outage in the requested range is evaluated; there is no severity pre-filter.

A time or iteration limit, invalid result, or exception is unresolved evidence and never a safety claim.
