# API reference

```@meta
CurrentModule = DroopOPF
```

```@autodocs
Modules = [DroopOPF]
Order = [:type, :function]
Filter = t -> !(t in (NetworkDesignContract, NETWORK_DESIGN_DEFAULTS, optimize_joint_design, optimize_staged_joint_design, validate_staged_joint_design))
```

## Staged single-snapshot design

optimize_staged_joint_design is the opt-in strict feasibility/reserve/feasibility/loss
workflow. See [initialization](initialization.md#Strict-staged-joint-design)
for the reserve metric, budgets, returned stage reports and qualification scope.

### Prepared PowerModels network workflow

See [Prepared network and snapshot design](network_design.md) for the optional
PowerModels extension. `NetworkDesignContract`, `solve_network_design`,
`replay_network_design`, `solve_network_series`, and `replay_network_series`
use the prepared source dictionaries directly. Contract/result read and write
helpers bind artifacts to source content and replay by default on result reads.
The native `Case` API remains separate and backward compatible.
