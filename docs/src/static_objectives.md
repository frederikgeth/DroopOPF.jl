# Shared static witness objectives

`optimize_static_witnesses` retains `:loss` as its default. Explicit alternatives are `:cost`, `:q_reserve`, `:security_margin`, and `:voltage_deviation`. These use the same shared static laws, demand-specific preventive dispatch and declared shared equipment. They do not establish global optimality or dynamic stability.

Supply convex piecewise-linear `generation_costs` as generator ID => ordered `(slope, intercept)` segments evaluated at per-unit active power. The maximum of segments is used, including endpoint extrapolation; the caller owns cost provenance and valid operating domains. `cost_scale` defaults to 1e4 and changes numerical scaling only. Costs are weighted over preventive witnesses.

Reactive reserve maximizes the minimum distance to both effective Q limits, divided by each generator's declared Q-box width, across all witnesses. Apparent/current capability is retained. This is generator headroom, not deliverable network reserve. Security margin maximizes the minimum of that reserve, voltage slack divided by the full allowed voltage band, and both-end thermal slack divided by rating. Voltage deviation minimizes the mean squared deviation from 1 pu normalized by 0.1 pu across buses and witnesses.

`objective_limits` optionally supplies lower bounds for Q/security reserve and upper bounds for loss, cost and voltage deviation, enabling a second loss-polishing solve. `static_witness_metrics` independently recomputes these metrics on materialized equipment. Pass the same costs and limits to `validate_static_witnesses` to check objective bounds as well as physical feasibility. These limits are explicit study choices; no automatic downstream Q constraint is introduced.

For new studies, follow the [operating-headroom initialization and objective policy](initialization.md#Operating-headroom-objective-policy-for-new-static-studies). Prescribed floors now use an exact constant-margin formulation; primary margin maximization retains variables. A fixed-floor economic solve is distinct from maximizing margin and then accepting its unpolished economic result.
