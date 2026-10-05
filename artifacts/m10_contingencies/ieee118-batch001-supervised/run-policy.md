# M10 run policy

- Base Ipopt CPU/wall-time limit: 180.0 seconds
- Contingency-batch Ipopt CPU/wall-time limit: 180.0 seconds
- Ipopt iteration limit: 1000

These limits begin when Ipopt starts; model construction needs a separate process supervisor. A time or iteration limit is an unresolved outcome, never a safety claim.
