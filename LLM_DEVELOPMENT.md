# LLM-Assisted Development Guide

This project is intended to be developed with substantial LLM assistance. The goal is to make that assistance fast without weakening scientific correctness or architectural discipline.

## 1. Operating principles

### Small, reviewable changes

Prefer one coherent change per task:

- one domain type;
- one formulation feature;
- one validator;
- one adapter;
- one regression test.

Avoid asking an LLM to implement an entire subsystem without intermediate tests.

### Evidence before abstraction

The agent should inspect existing code, tests, and documentation before proposing a new abstraction. New interfaces should be justified by at least two real use cases or by a clear separation of concerns in the architecture.

### Equations before code

Every new physical feature must first state:

- variables;
- parameters;
- units;
- equations;
- inequalities;
- scenario behavior;
- expected limiting cases;
- validation method.

### Independent validation

The implementation and validator should not blindly reuse the same expression tree. A result is not trustworthy merely because the solver reports success.

## 2. Repository context for agents

Before changing code, read:

1. `ARCHITECTURE.md`;
2. `ROADMAP.md`;
3. the current `Project.toml`;
4. relevant source files;
5. relevant tests;
6. the git diff and status.

The working tree may contain user changes. Preserve unrelated work.

## 3. Standard task format

Use prompts or issues with this structure:

```text
Objective:

Context:

Architectural layer:

In scope:

Out of scope:

Required behavior:

Acceptance tests:

Validation and diagnostics:

Files expected to change:

Risks or unresolved assumptions:
```

## 4. Implementation protocol

For each task, the agent should:

1. inspect the relevant repository state;
2. restate the intended change briefly;
3. identify assumptions;
4. make the smallest coherent patch;
5. add or update focused tests;
6. run the narrowest relevant test command;
7. run broader tests when practical;
8. inspect the final diff;
9. report changed files, tests, and remaining risks.

Do not silently broaden the scope because a broader redesign appears attractive.

## 5. Coding constraints

- Do not put solver objects in domain types.
- Do not mutate user-owned case data during solving.
- Do not duplicate physical equations in several backends without a stated reason.
- Do not use string-keyed dictionaries in hot numerical loops.
- Do not add a new dependency without explaining why it belongs in core or an extension.
- Do not hide unit conversion in arbitrary solver callbacks.
- Do not silently change from exact to smoothed controls after an error.
- Do not report a successful solve as a valid equilibrium without validation.
- Do not add GPU or distributed code before a measured bottleneck exists.

## 6. Physical-model checklist

Before accepting a new control or device model, confirm:

- sign conventions are documented;
- all parameters have units;
- per-unit conversion is explicit;
- limiting cases are tested;
- availability and outage behavior are defined;
- saturation behavior is defined;
- interactions with bounds are defined;
- the independent validator can replay the model;
- the model has at least one hand-checkable test case.

For droop specifically, confirm:

- reference frequency or voltage;
- input signal location;
- absolute versus incremental output;
- deadband;
- slope sign;
- saturation;
- activation stage;
- response limits;
- smoothing epsilon and tolerance;
- behavior under generator outage;
- behavior under islanding.

## 7. Test expectations

Every new feature should add tests at the appropriate level.

### Unit level

Test pure functions and data validation with small values and edge cases.

### Model level

Test that the feature contributes the intended variables and constraints.

### Physical level

Test residuals, limits, and expected response using independently computed values.

### Regression level

Add a minimal fixture for every discovered bug. Prefer small deterministic cases over large opaque fixtures.

## 8. Validation report expectations

New failure modes should produce structured findings with:

- stable code;
- severity;
- scenario ID when applicable;
- component ID when applicable;
- measured value;
- limit or tolerance;
- units;
- concise message;
- enough context to reproduce the issue.

Finding codes should be stable even if message wording changes.

Suggested naming convention:

```text
E.<domain>.<condition>
W.<domain>.<condition>
I.<domain>.<condition>
```

Examples:

```text
E.CTRL.DROOP_RESIDUAL
E.PF.REACTIVE_POWER_RESIDUAL
W.CTRL.SMOOTHING_GAP
W.NUM.ILL_CONDITIONED
I.CTRL.SATURATED
```

## 9. Review checklist for LLM-generated code

Before merging, a human or reviewer agent should ask:

### Scope

- Does the change implement the requested issue only?
- Did it introduce speculative features?

### Correctness

- Are equations and signs correct?
- Are units consistent?
- Are outage cases handled?
- Does the result remain physically interpretable?

### Architecture

- Is the change in the correct layer?
- Are solver-specific types contained?
- Is mutable state separated from case data?
- Is the validator independent enough to catch implementation errors?

### Numerical behavior

- Are scaling and tolerances explicit?
- Are boundary and saturation cases tested?
- Is the initial point reasonable?
- Is the behavior near breakpoints understood?

### Tests and documentation

- Is there a focused regression test?
- Is the public behavior documented?
- Are limitations and assumptions recorded?

## 10. Recommended agent roles

For larger tasks, use separate passes rather than one agent doing everything:

1. **Modeling pass** — writes equations, assumptions, and edge cases.
2. **Implementation pass** — makes the smallest code change.
3. **Test pass** — adds unit, integration, and adversarial tests.
4. **Validation pass** — checks independent residuals and physical meaning.
5. **Review pass** — inspects architecture, diff, and documentation.

The same model may perform all roles sequentially, but the prompts should preserve these different perspectives.

## 11. Useful task prompts

### New physical feature

```text
Implement <feature> in the domain, formulation, and validation layers.

First state the equations, units, limiting cases, and contingency behavior.
Do not modify unrelated APIs. Keep the exact physical evaluator independent
from the JuMP implementation. Add focused tests, including one intentionally
invalid case. Report changed files and test commands.
```

### Bug diagnosis

```text
Diagnose the failure in <test or example>.

Inspect the current implementation and reproduce the issue before editing.
Separate data, formulation, solver, and validation hypotheses. Implement a
fix only after identifying the cause. Add a regression test that would fail
under the old behavior. Do not refactor unrelated code.
```

### Performance work

```text
Profile <workflow> before changing the architecture.

Identify the measured bottleneck, establish a baseline, make one optimization,
and verify numerical equivalence with the independent validator. Report build
time, solve time, allocations or memory where available, and any trade-offs.
```

## 12. Completion message format

Each completed development task should end with:

```text
Implemented:
- ...

Changed files:
- ...

Tests run:
- ...

Validation:
- ...

Known limitations:
- ...

Suggested next task:
- ...
```

## 13. Source references

The workflow draws on the following project patterns:

- [BMOPFTools.jl](https://github.com/frederikgeth/BMOPFTools.jl): structured findings, staged model construction, provenance, and solution profiling;
- [PowerModels.jl](https://github.com/lanl-ansi/PowerModels.jl): formulation-oriented architecture;
- [JuMP nonlinear modeling](https://jump.dev/JuMP.jl/stable/manual/nonlinear/): sparse nonlinear derivatives;
- [MadNLP.jl](https://madsuite.org/MadNLP.jl/stable/): sparse nonlinear optimization and solver backends.

