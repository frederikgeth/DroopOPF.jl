# Independent-snapshot design (experimental)

The optional PowerModels extension consumes an explicitly prepared per-unit
network through one numerical contract. It retains the supplied dictionary at
the handoff. Native Case-based APIs keep their own declared control semantics.

The sequence is cold feasibility, strict reserve initialization, strict
zero-objective design feasibility, then loss optimization. Every accepted stage
requires native convergence and physical replay. Complete primal starts include
AVR sharing, response signals and equipment settings. Limits and replay tolerances
are unchanged. The reserve floor is fixed from accepted initialization.

## Two-snapshot policy

IBRs selected and online in every snapshot share slope and Vref. Mixed AVR/IBR
groups share the corresponding target. Pure AVR targets and source-declared
adjustable taps/shunts are snapshot-specific. Other online units retain supplied
controls; offline records are retained. Signed active output is preserved.
Weights are positive and sum to one (equal by default), defining weighted loss.
This is an operating-point study: no storage energy, ramp, commitment or outage
coupling is implied. Source bounds are never inferred for adjustable equipment.

## Library interface and input responsibility

With PowerModels and DroopOPF loaded, construct `NetworkDesignContract` from the
prepared per-unit dictionary and explicit control, regulation and equipment
plans. The caller supplies source reconciliation, capability assumptions,
classification and provenance. The extension consumes the prepared dictionary.

Use `solve_network_design` for one snapshot or `solve_network_series` for a
vector of contracts. The shared design and snapshot-specific decisions follow
the supplied plan. `write_network_contract` / `read_network_contract` and
`write_network_design` / `read_network_design` provide content-bound persistence.
Result reads replay by default. Review the accepted flag, all four stage
receipts, achieved reserve floor, settings and independent replay before using
any exported controller.

The [workflow flowcharts](design_workflow.md) describe stage objectives and
performance review. Native Case-based APIs retain their own control semantics.
Inputs and detailed outputs from confidential networks belong outside Git and
cloud-synced folders. Consumer file reconciliation, local plotting and diagnostic
release policies belong to the consuming application.

## Numerical defaults and saturation arithmetic

All prepared-network entry points default to limited-memory Hessian, 3000 iterations and
1200 seconds per stage. Budgets apply separately to each stage. Explicit options
can choose exact Hessians or different budgets; physical bounds and replay
acceptance tolerances do not change. Native Case APIs retain their own defaults.

The smooth positive part is (x + sqrt(x² + epsilon²))/2 with epsilon=1e-8.
Clipping uses lower + positive(x-lower) - positive(x-upper). JuMP expressions
retain each offset square as an explicit nonlinear power node. Expanding the
square into a quadratic polynomial can cause cancellation near saturation,
erasing epsilon² and producing NaN derivatives despite finite primal values.
The factored expression fixes evaluation without changing the clipping law or
smoothing width. Active response, IBR saturation and AVR equations share it.
High-precision derivative tests cover both limits. Native Case controls use
stable log1pexp smoothing separately; that established implementation is retained.

## Qualification scope

This optional extension is experimental. Its numerical stages and
replay are explicit. Consumer CLI execution and native PSS/E equivalence require
separate qualification with the corresponding source and policy. Run the native
staged and package regression suites for the native Case path.

```@meta
CurrentModule = DroopOPF
```

```@docs
NetworkDesignContract
NETWORK_DESIGN_DEFAULTS
```

The limited-memory default retains qualification of the synthetic remote-AVR
regression. With exact Hessians that fixture reaches Error_In_Step_Computation
at design feasibility despite passing physical replay; limited-memory converges
through all four stages. Public 14/500 exact-Hessian comparisons remain supported.

The Hessian choice applies to reserve initialization and both design stages.
Cold feasibility retains its established exact-Hessian preparation and adaptive
barrier settings; its separate numerical contract is reported in the stage file.
