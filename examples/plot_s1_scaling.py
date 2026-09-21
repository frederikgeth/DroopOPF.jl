"""Matched scaling evidence, including every failure and physical-unit location."""
from pathlib import Path
import json, shutil
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
root=Path("artifacts/s1_scaling_probe")
rows=json.loads((root/"summary.json").read_text())
fig,axes=plt.subplots(2,1,figsize=(12,8),layout="constrained")
x=range(len(rows));colors=["#238b65" if r["valid"] else "#bd4545" for r in rows]
axes[0].bar(x,[r.get("iterations",0) for r in rows],color=colors)
axes[0].set_ylabel("Iterations");axes[0].set_title("Matched Ipopt scaling: green = validated; red = rejected")
for i,r in enumerate(rows):
    axes[0].text(i,r.get("iterations",0)+12,str(r.get("status","ERROR")).replace("_","\n"),ha="center",va="bottom",fontsize=7)
axes[0].set_ylim(0,1280)
for key,tol,label,marker in [("power_balance_max",1e-6,"AC balance", "o"),("droop_residual_max",1e-5,"Exact droop","s")]:
    axes[1].plot(x,[max((r.get("physical") or {}).get(key, float("nan"))/tol,1e-8) for r in rows],marker=marker,label=label)
axes[1].axhline(1,color="black",ls="--",label="Acceptance threshold")
axes[1].set_yscale("log");axes[1].set_ylabel("Residual / physical tolerance");axes[1].legend()
labels=[f"{r['buses']} / {r['tags']['load_factor']}\n{r['tags']['scaling']}" for r in rows]
for ax in axes:ax.set_xticks(list(x),labels,fontsize=8)
for ext in ("png","pdf"):fig.savefig(root/f"scaling.{ext}",dpi=160)
plt.close(fig)
lines=["# S1 matched numerical scaling", "",f"**{sum(r['valid'] for r in rows)}/{len(rows)} attempts validate. S1 remains open.**", "",
"The three arms use identical baseline primal states, control settings, smoothing (1e-6), small bound pushes (1e-8), objective, physical tolerances and iteration/time budgets. Only Ipopt numerical scaling changes: default gradient scaling, no scaling, or gradient scaling with maximum gradient 1. This tests solver scaling, not a new normalized-variable formulation. No equipment equation or physical bound changes.", "",
"These are dependent benchmark cases, not independent statistical trials or a general convergence guarantee. Timing includes diagnostic overhead and concurrent regression work; it is not isolated performance evidence. Only validated objectives may be compared. Source angle constraints are separately audited for physically valid results.", "",
"![Scaling results](scaling.png)", "", "| Attempt | Status | Valid | Iterations | Valid objective | Physical failures |", "|---|---|---|---|---|---|"]
for r in rows:
    physical=r.get("physical")
    failures=", ".join(physical["violations"]) if physical else "not evaluated"
    obj=f"{r['objective']:.9g}" if r['valid'] else "—"
    lines.append(f"| [{r['name']}]({r['name']}-diagnostics.json) | {r.get('status','ERROR')} | {r['valid']} | {r.get('iterations','—')} | {obj} | {failures or 'none'} |")
lines += ["", "## Physical failure locations", "", "Every failure is retained in JSON. The table below shows the largest exceedance per attempt and category, in original per-unit quantities. Exceedance is violation minus tolerance; branch limits use apparent power at the named terminal. Missing physical checks are explicitly marked, never treated as a pass.", "", "| Attempt | Category | Equipment ID | Component | Violation (pu) | Tolerance (pu) | Exceedance (pu) |", "|---|---|---|---|---|---|---|"]
for r in rows:
    seen=set()
    for d in r.get("physical_failures") or []:
        if d['category'] in seen:continue
        seen.add(d['category'])
        lines.append(f"| {r['name']} | {d['category']} | {d['equipment']} {d['id']} | {d['component']} | {d['violation_pu']:.4g} | {d['tolerance_pu']:.4g} | {d['exceedance_pu']:.4g} |")
lines += ["", "## Retained-run audit", "", "All 30 original public attempts were rechecked without rerunning the solver or modifying historical evidence. Equipment-level failure categories agree with the independent validator. See [the complete location audit](retained-public-failures.json).", "", "## Scope and next gate", "", "No scaling setting is promoted automatically. A candidate needs matched start variation and both physical and solution-quality checks. Primal/dual warm starts, explicit variable normalization and a declared restart/selection policy remain open. M9 is not unlocked.", ""]
text="\n".join(lines)
(root/"report.md").write_text(text)
assets=Path("docs/src/assets/s1_scaling");assets.mkdir(parents=True,exist_ok=True)
for p in root.glob("*"):
    if p.suffix in (".png",".pdf") or p.name in ("summary.json","retained-public-failures.json") or p.name.endswith("-diagnostics.json"):shutil.copy2(p,assets/p.name)
text=text.replace("](retained-public-failures.json)","](assets/s1_scaling/retained-public-failures.json)")
text=text.replace("](scaling.png)","](assets/s1_scaling/scaling.png)")
for r in rows:text=text.replace(f"]({r['name']}-diagnostics.json)",f"](assets/s1_scaling/{r['name']}-diagnostics.json)")
Path("docs/src/s1_scaling.md").write_text(text)
