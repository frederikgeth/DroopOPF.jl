"""Report the paired explicit/reduced droop-Q formulation experiment."""
from pathlib import Path
import hashlib
import json
import re
import shutil

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


root = Path("artifacts")
out = root / "s1_reduced_q"
out.mkdir(exist_ok=True)
solvers = ("ipopt", "madnlp")
baseline_paths = {s: root / f"s1_policy_{s}" / "summary.json" for s in solvers}
reduced_paths = {s: root / f"s1_reduced_q_{s}" / "summary.json" for s in solvers}
baseline = {s: json.loads(p.read_text()) for s, p in baseline_paths.items()}
reduced = {s: json.loads(p.read_text()) for s, p in reduced_paths.items()}
assert all(len(baseline[s]) == len(reduced[s]) == 12 for s in solvers)


def selected_attempt(row):
    if row["selected"] is None:
        return row["attempts"][-1]
    return next(a for a in row["attempts"] if a["name"] == row["selected"])


def accepted_objective(row):
    return next((a["objective"] for a in row["attempts"] if a["valid"]), None)


def fmt(value):
    return "—" if value is None else f"{value:.9g}"


manifest_paths = [
    *baseline_paths.values(),
    *reduced_paths.values(),
    Path("src/jump.jl"),
    Path("src/joint_design.jl"),
    Path("examples/s1_experiments.jl"),
    Path("examples/s1_restart_policy.jl"),
    Path("examples/s1_policy_matrix.jl"),
]
(out / "provenance.json").write_text(json.dumps({
    "hashes": {
        str(path): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in manifest_paths
    },
    "scope": "Paired frozen tuning matrix; not holdout reliability evidence",
    "acceptance": "native solver acceptance plus independent physical validation plus policy budget",
    "concurrency": "Ipopt and MadNLP matrices ran concurrently; elapsed time is descriptive only",
}, indent=2) + "\n")

lines = [
    "# S1 reduced-space droop-Q formulation",
    "",
    "**The reduced formulation is mathematically equivalent on the declared domain, but it is not a general reliability improvement. The explicit formulation remains the default and S1 remains open.**",
    "",
    "This checkpoint substitutes each controlled generator's smoothed volt-var response directly into reactive-power balance and the reactive objective term. It is available only through the opt-in `optimize_joint_design(...; droop_q_formulation=:reduced)` path.",
    "",
    "## Formulation and equivalence",
    "",
    "For an attached available generator, the explicit formulation contains",
    "",
    "```math",
    r"q_g - \widehat q_g(V_{r(g)},\theta_g)=0,\qquad \underline q_g\le q_g\le\overline q_g.",
    "```",
    "",
    "The reduced formulation removes `q_g` and its equality, and uses the smoothed response `\\widehat q_g` wherever `q_g` occurs. In particular, the generator contribution in the reactive balance at bus `i` becomes",
    "",
    "```math",
    r"\sum_{g\in\mathcal G_i^{\rm free}}q_g+\sum_{g\in\mathcal G_i^{\rm droop}}\widehat q_g(V_{r(g)},\theta_g),",
    "```",
    "",
    "and a term `c_q q_g^2` becomes `c_q \\widehat q_g^2`. The same smoothed curve, controller parameters, network equations and objective coefficients are used. The returned operating point reconstructs each eliminated `q_g` from that curve.",
    "",
    "The controller capability interval is validated to lie inside its generator capability interval. Because the smoothed clamp lies inside the controller interval in exact arithmetic, the eliminated generator-Q bounds are implied. Thus every explicit feasible point maps to one reduced feasible point and conversely on the validated domain. Regression tests verify the variable/equality count, endpoint behavior, and matching objective, voltage, Q, tap and shunt results on a small joint case with both solvers.",
    "",
    "This is an equivalent physical model but a different numerical problem. It removes the independent `q_g` starting value, changes a quadratic objective representation into a nonlinear expression, and changes the Jacobian/Hessian structure. Restart-context hashes include the formulation so seeds cannot cross modes silently. Independent validation remains unchanged; it checks reconstructed Q values, AC balance, equipment limits and the exact unsmoothed droop curve.",
    "",
    "## Structural reduction",
    "",
    "![Structural reduction](size.png)",
    "",
    "| Network | Controlled Q variables removed | Variables, explicit → reduced | Constraints, explicit → reduced |",
    "|---|---:|---:|---:|",
]

size_rows = []
for buses in (118, 300):
    old = next(r for r in baseline["ipopt"] if r["buses"] == buses)["attempts"][0]["model"]
    new = next(r for r in reduced["ipopt"] if r["buses"] == buses)["attempts"][0]["model"]
    removed = len(new["reduced_droop_q_generator_ids"])
    size_rows.append((buses, removed, old["variables"], new["variables"], old["constraints"], new["constraints"]))
    lines.append(f"| IEEE {buses} | {removed} | {old['variables']} → {new['variables']} | {old['constraints']} → {new['constraints']} |")

fig, axes = plt.subplots(1, 2, figsize=(9, 4.2), layout="constrained")
for ax, index, ylabel in zip(axes, (2, 4), ("Variables", "JuMP constraints")):
    x = range(len(size_rows))
    old_values = [r[index] for r in size_rows]
    new_values = [r[index + 1] for r in size_rows]
    ax.bar([v - 0.18 for v in x], old_values, width=0.36, label="Explicit", color="#607d8b")
    ax.bar([v + 0.18 for v in x], new_values, width=0.36, label="Reduced", color="#238b65")
    ax.set_xticks(list(x), [f"IEEE {r[0]}" for r in size_rows])
    ax.set_ylabel(ylabel)
    ax.grid(axis="y", alpha=0.2)
axes[0].legend()
for suffix in ("png", "pdf"):
    fig.savefig(out / f"size.{suffix}", dpi=160)
plt.close(fig)

lines += [
    "",
    "One eliminated controlled Q contributes one variable, its nonlinear droop equality and its two variable-bound constraints to the reported JuMP counts. Unattached and unavailable generator-Q variables remain explicit.",
    "",
    "## Frozen public comparison",
    "",
    "The comparison uses the same 12 IEEE 118/300 cases per backend, starts, physical coordinates, smoothing width, objective, one-reset policy, 2000-iteration total allowance and 120-second cooperative wall budget as the explicit baseline. Every attempt is retained. Since the two solver matrices ran concurrently, elapsed time is not used to rank formulations.",
    "",
    "![Acceptance comparison](acceptance.png)",
    "",
    "| Solver | Explicit initial → policy | Reduced initial → policy | Gained / lost | Reduced attempts | Reduced iterations | Iteration / wall overruns |",
    "|---|---|---|---|---:|---:|---|",
]

fig, axes = plt.subplots(1, 2, figsize=(10, 4.5), layout="constrained")
for ax, solver in zip(axes, solvers):
    old = {r["name"]: r for r in baseline[solver]}
    new = {r["name"]: r for r in reduced[solver]}
    old_initial = sum(r["attempts"][0]["valid"] for r in old.values())
    old_policy = sum(r["valid"] for r in old.values())
    new_initial = sum(r["attempts"][0]["valid"] for r in new.values())
    new_policy = sum(r["valid"] for r in new.values())
    gains = sum(new[name]["valid"] and not row["valid"] for name, row in old.items())
    losses = sum(row["valid"] and not new[name]["valid"] for name, row in old.items())
    attempts = sum(len(r["attempts"]) for r in new.values())
    iterations = sum(r["iterations"] for r in new.values())
    over = [sum(r["budget_exceeded"][key] for r in new.values()) for key in ("iterations", "wall")]
    lines.append(
        f"| {solver} | {old_initial} → {old_policy} | {new_initial} → {new_policy} | "
        f"{gains} / {losses} | {attempts} | {iterations} | {over[0]} / {over[1]} |"
    )
    values = [old_initial, old_policy, new_initial, new_policy]
    ax.bar(range(4), values, color=["#90a4ae", "#607d8b", "#91c9ad", "#238b65"])
    ax.set_xticks(range(4), ["Explicit\ninitial", "Explicit\npolicy", "Reduced\ninitial", "Reduced\npolicy"])
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
    "MadNLP improves from 4/12 to 8/12 accepted cases, gaining five and losing one. Its gains include all three nominal IEEE 118 starts and both additional nominal IEEE 300 starts. The lost case is the stressed IEEE 300 flat-low start. Ipopt falls from 8/12 to 4/12: it retains all nominal IEEE 118 starts and the nominal IEEE 300 anchor, but loses one stressed IEEE 118 case and all three stressed IEEE 300 cases. This backend dependence prevents promotion as a common default.",
    "",
    "Two reduced MadNLP attempts terminate locally solved but fail the unchanged physical droop check by small margins: their maximum exact-curve residuals are 1.04e-5 and 1.12e-5 against a 1e-5 tolerance. The reduced equality uses the smoothed response exactly; the validator deliberately compares against the exact curve. Iteration-limit failures primarily retain AC power-balance violations. Solver termination alone therefore remains insufficient for acceptance.",
    "",
    "## Paired ledger",
    "",
    "| Case | Explicit / reduced valid | Explicit / reduced iterations | Explicit / reduced accepted objective | Reduced final status and physical failure |",
    "|---|---|---|---|---|",
]
for solver in solvers:
    old = {r["name"]: r for r in baseline[solver]}
    for row in reduced[solver]:
        before = old[row["name"]]
        attempt = selected_attempt(row)
        violations = attempt["physical"].get("violations", [])
        failure = "none" if not violations else ", ".join(violations)
        lines.append(
            f"| [{row['name']}]({row['name']}-policy.json) | {before['valid']} / {row['valid']} | "
            f"{before['iterations']} / {row['iterations']} | {fmt(accepted_objective(before))} / "
            f"{fmt(accepted_objective(row))} | {attempt['status']}; {failure} |"
        )

lines += [
    "",
    "## Decision and next experiment",
    "",
    "Keep `droop_q_formulation=:explicit` as the default. Retain `:reduced` as an opt-in S1 diagnostic because it substantially helps MadNLP on this matrix and cleanly removes the locally dependent droop-Q row, but it regresses Ipopt and one prior MadNLP success. The experiment establishes local algebraic equivalence and backend-specific numerical value; it does not establish general convergence or global optimality.",
    "",
    "The full regression suite passes 1551/1551 tests. During verification, preserving the legacy explicit nonlinear-constraint insertion order was necessary to retain the existing M2 complementarity solve; this order is now covered by the full regression result. Reduced mode retains its required early substitution.",
    "",
    "S1 remains open and M9 remains gated. The next small step is to use the retained paired failures to test a smooth-clamp representation or targeted equality treatment that keeps explicit Q limits and has non-flat saturation derivatives, first on the two-variable reproducer and then on this frozen matrix. Only a candidate that preserves prior accepted cases should proceed to new controller placements, additional loading levels and larger holdout networks.",
    "",
]

for solver in solvers:
    folder = root / f"s1_reduced_q_{solver}"
    for path in folder.glob("*.json"):
        if path.name != "summary.json":
            shutil.copy2(path, out / path.name)
    (out / f"baseline-{solver}.json").write_text(json.dumps(baseline[solver], indent=2) + "\n")
(out / "summary.json").write_text(json.dumps(reduced, indent=2) + "\n")
text = "\n".join(lines)
(out / "report.md").write_text(text)
assets = Path("docs/src/assets/s1_reduced_q")
assets.mkdir(parents=True, exist_ok=True)
for path in out.glob("*"):
    if path.suffix in (".json", ".png", ".pdf"):
        shutil.copy2(path, assets / path.name)
text = re.sub(r"\]\(([^)]+)\)", lambda match: "](assets/s1_reduced_q/" + match.group(1) + ")", text)
Path("docs/src/s1_reduced_q.md").write_text(text)
