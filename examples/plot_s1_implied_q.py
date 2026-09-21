"""Report the saturated-droop reproducer and paired implied-Q-bound experiment."""
from pathlib import Path
import hashlib
import json
import re
import shutil

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

root = Path("artifacts")
out = root / "s1_implied_q"
out.mkdir(exist_ok=True)
solvers = ("ipopt", "madnlp")
baseline_paths = {s: root / f"s1_policy_{s}" / "summary.json" for s in solvers}
baseline = {s: json.loads(p.read_text()) for s, p in baseline_paths.items()}
implied = {
    s: json.loads((root / f"s1_implied_q_{s}" / "summary.json").read_text())
    for s in solvers
}
reproducer = json.loads((root / "s1_saturation_reproducer" / "summary.json").read_text())
assert all(len(implied[s]) == 12 for s in solvers)
assert len(reproducer) == 12

manifest = {
    str(path): hashlib.sha256(path.read_bytes()).hexdigest()
    for path in [
        *baseline_paths.values(),
        Path("examples/s1_saturation_reproducer.jl"),
        Path("src/jump.jl"),
        Path("src/joint_design.jl"),
    ]
}
(out / "provenance.json").write_text(json.dumps({
    "hashes": manifest,
    "scope": "Paired frozen tuning matrix; not holdout reliability evidence",
    "floating_endpoint_excursion_maximum": "bounded by 16*eps(Float64) in tests",
}, indent=2) + "\n")

def accepted_objective(row):
    return next((a["objective"] for a in row["attempts"] if a["valid"]), None)

def fmt(value):
    return "—" if value is None else f"{value:.9g}"

lines = [
    "# S1 saturated droop reproducer and implied Q-bound formulation",
    "",
    "This checkpoint isolates the numerical dependence between a saturated droop equality and an active generator reactive-power bound, then evaluates an opt-in equivalent formulation on the frozen IEEE 118/300 tuning matrix. The existing `droop_q_bounds=:explicit` formulation remains the default.",
    "",
    "For a positive smoothing width, the softplus derivative lies strictly between zero and one. By the mean-value theorem,",
    "",
    "```math",
    r"0 < \operatorname{softplus}_\epsilon(r-q_{\min})-\operatorname{softplus}_\epsilon(r-q_{\max}) < q_{\max}-q_{\min}.",
    "```",
    "",
    "Therefore the smoothed droop response lies inside its control capability in exact arithmetic. Case validation already requires that capability interval to lie inside the attached generator limits. In `:implied` mode only those redundant generator-Q variable bounds are omitted. The `qg` variable, droop equality, AC balances, objective, controller limits, smoothing and extracted result are unchanged. Unattached and unavailable generators retain their bounds.",
    "",
    "The difference-of-softplus floating-point evaluation can exceed an endpoint by roundoff. A voltage sweep in the regression test observes a positive excursion and bounds it by `16eps(Float64)`; the maximum is around 1e-15 in the current cases. Independent physical validation remains unchanged at 1e-6 and checks every returned generator Q value. No result is accepted merely because its bound was omitted from the optimization model.",
    "",
    "## Minimal reproducer",
    "",
    "The two-variable model retains the package droop evaluator, a voltage variable, a reactive-power variable, the droop equality and the same small reactive objective weight. It targets lower saturation, deadband and upper saturation with both solvers. In explicit mode the saturation rows have droop gradient `[0, 1]`, parallel to the active Q bound `[0, 1]`; the stacked matrix has a zero singular value. Implied mode removes that duplicate active row. This reproducer demonstrates local numerical dependence, not full-network reliability.",
    "",
    "![Reproducer multipliers](reproducer.png)",
    "",
    "| Solver | Target V | Explicit / implied status | Explicit / implied objective | Explicit droop / active-bound dual | Implied droop dual |",
    "|---|---|---|---|---|---|",
]

fig, axes = plt.subplots(1, 2, figsize=(10, 4.5), layout="constrained")
for ax, solver in zip(axes, solvers):
    rows = [r for r in reproducer if r["solver"] == solver]
    for target in (0.8, 1.0, 1.2):
        explicit = next(r for r in rows if r["mode"] == "explicit" and r["target_voltage"] == target)
        implied_row = next(r for r in rows if r["mode"] == "implied" and r["target_voltage"] == target)
        active_bound = None
        if target == 0.8:
            active_bound = explicit["q_bound_dual"]["upper"]
        elif target == 1.2:
            active_bound = explicit["q_bound_dual"]["lower"]
        lines.append(
            f"| {solver} | {target} | {explicit['termination']} / {implied_row['termination']} | "
            f"{fmt(explicit['objective'])} / {fmt(implied_row['objective'])} | "
            f"{fmt(explicit['droop_dual'])} / {fmt(active_bound)} | {fmt(implied_row['droop_dual'])} |"
        )
        ax.scatter(target - 0.005, abs(explicit["droop_dual"]), color="#607d8b", marker="o")
        ax.scatter(target + 0.005, abs(implied_row["droop_dual"]), color="#238b65", marker="x")
    ax.set_yscale("symlog", linthresh=1e-6)
    ax.set_xlabel("Target voltage (pu)")
    ax.set_ylabel("Absolute droop multiplier")
    ax.set_title(solver)
    ax.grid(alpha=0.2)
axes[0].scatter([], [], color="#607d8b", marker="o", label="Explicit Q bound")
axes[0].scatter([], [], color="#238b65", marker="x", label="Implied Q bound")
axes[0].legend()
for suffix in ("png", "pdf"):
    fig.savefig(out / f"reproducer.{suffix}", dpi=160)
plt.close(fig)

lines += [
    "",
    "## Frozen public comparison",
    "",
    "Each backend uses the same 12 cases, declared physical starts, epsilon 1e-6, physical controller coordinates, objective, one-reset policy, 2000-iteration total allowance and 120-second cooperative wall budget as its frozen baseline. Every failed attempt is retained. Runs were concurrent, so elapsed time is not an isolated performance comparison.",
    "",
    "![Acceptance comparison](acceptance.png)",
    "",
    "| Solver | Explicit initial → policy | Implied initial → policy | Gained / lost cases | Attempts | Iteration / wall overruns |",
    "|---|---|---|---|---|---|",
]

fig, axes = plt.subplots(1, 2, figsize=(10, 4.5), layout="constrained")
for ax, solver in zip(axes, solvers):
    old = {r["name"]: r for r in baseline[solver]}
    new = {r["name"]: r for r in implied[solver]}
    old_initial = sum(r["attempts"][0]["valid"] for r in old.values())
    old_policy = sum(r["valid"] for r in old.values())
    new_initial = sum(r["attempts"][0]["valid"] for r in new.values())
    new_policy = sum(r["valid"] for r in new.values())
    gains = sum(new[name]["valid"] and not row["valid"] for name, row in old.items())
    losses = sum(row["valid"] and not new[name]["valid"] for name, row in old.items())
    attempts = sum(len(r["attempts"]) for r in new.values())
    over = [sum(r["budget_exceeded"][key] for r in new.values()) for key in ("iterations", "wall")]
    lines.append(
        f"| {solver} | {old_initial} → {old_policy} | {new_initial} → {new_policy} | "
        f"{gains} / {losses} | {attempts} | {over[0]} / {over[1]} |"
    )
    values = [old_initial, old_policy, new_initial, new_policy]
    ax.bar(range(4), values, color=["#90a4ae", "#607d8b", "#91c9ad", "#238b65"])
    ax.set_xticks(range(4), ["Explicit\ninitial", "Explicit\npolicy", "Implied\ninitial", "Implied\npolicy"])
    ax.set_ylim(0, 13)
    ax.set_ylabel("Validated cases out of 12")
    ax.set_title(solver)
    for index, value in enumerate(values):
        ax.text(index, value + 0.2, str(value), ha="center")
for suffix in ("png", "pdf"):
    fig.savefig(out / f"acceptance.{suffix}", dpi=160)
plt.close(fig)

lines += [
    "",
    "## Paired ledger",
    "",
    "| Case | Explicit / implied valid | Explicit / implied iterations | Explicit / implied accepted objective | Implied final decision |",
    "|---|---|---|---|---|",
]
for solver in solvers:
    old = {r["name"]: r for r in baseline[solver]}
    for row in implied[solver]:
        before = old[row["name"]]
        lines.append(
            f"| [{row['name']}]({row['name']}-policy.json) | {before['valid']} / {row['valid']} | "
            f"{before['iterations']} / {row['iterations']} | {fmt(accepted_objective(before))} / "
            f"{fmt(accepted_objective(row))} | {row['events'][-1]} |"
        )

lines += [
    "",
    "## Decision",
    "",
    "The implied-bound formulation validates 7/12 Ipopt cases versus 8/12 explicitly bounded, and 3/12 MadNLP cases versus 4/12. MadNLP gains all three nominal IEEE 118 starts but loses four previously accepted stressed or larger cases. Ipopt loses one stressed IEEE 118 anchor. The formulation changes numerical trajectories rather than providing a general reliability improvement.",
    "",
    "This result narrows the diagnosis: the saturated-droop/active-Q-bound dependence is real, but it is not the only source of failure. `:implied` remains opt-in and S1 remains open. The next experiment should preserve explicit physical bounds while preventing saturated equalities from becoming numerically flat, or use a reduced-space substitution whose derivative and endpoint behavior are verified before public benchmarking. No further equipment-model change is made in this checkpoint.",
    "",
]

for solver in solvers:
    folder = root / f"s1_implied_q_{solver}"
    for path in folder.glob("*.json"):
        if path.name != "summary.json":
            shutil.copy2(path, out / path.name)
    (out / f"baseline-{solver}.json").write_text(json.dumps(baseline[solver], indent=2) + "\n")
(out / "summary.json").write_text(json.dumps(implied, indent=2) + "\n")
(out / "reproducer-summary.json").write_text(json.dumps(reproducer, indent=2) + "\n")
text = "\n".join(lines)
(out / "report.md").write_text(text)
assets = Path("docs/src/assets/s1_implied_q")
assets.mkdir(parents=True, exist_ok=True)
for path in out.glob("*"):
    if path.suffix in (".json", ".png", ".pdf"):
        shutil.copy2(path, assets / path.name)
text = re.sub(r"\]\(([^)]+)\)", lambda match: "](assets/s1_implied_q/" + match.group(1) + ")", text)
Path("docs/src/s1_implied_q.md").write_text(text)
