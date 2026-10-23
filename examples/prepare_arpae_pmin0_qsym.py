#!/usr/bin/env python3
"""Create preserved-source ARPA-E study variants with Pmin=0 and symmetric Q limits."""

from __future__ import annotations

import csv
import re
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "test/data/arpae/c1_network01"
CASES = {
    "scenario_01": "scenario_01_pmin0_qsym",
    "scenario_02": "scenario_02_pmin0_qsym",
}
GEN_START = "BEGIN GENERATOR DATA"
GEN_END = "END OF GENERATOR DATA"


def replace_number(token: str, value: float) -> str:
    """Replace a comma-delimited value while retaining its surrounding spacing."""
    match = re.fullmatch(r"(\s*).*?(\s*)", token)
    assert match
    return f"{match.group(1)}{value:.12g}{match.group(2)}"


def derive(source: str, target: str) -> None:
    source_dir = ROOT / source
    target_dir = ROOT / target
    if target_dir.exists():
        shutil.rmtree(target_dir)
    shutil.copytree(source_dir, target_dir)

    raw_path = target_dir / "case.raw"
    raw_path.chmod(raw_path.stat().st_mode | 0o200)
    lines = raw_path.read_text().splitlines(keepends=True)
    in_gen = False
    rows = []
    out = []
    for line in lines:
        lower = line.lower()
        if GEN_START.lower() in lower or "begin generator section" in lower:
            in_gen = True
            out.append(line)
            continue
        if in_gen and (GEN_END.lower() in lower or "end generator section" in lower):
            in_gen = False
            out.append(line)
            continue
        if not in_gen or not line.strip() or line.lstrip().startswith("0 /"):
            out.append(line)
            if "end fixed shunt section" in lower:
                in_gen = True
            continue

        row = next(csv.reader([line], skipinitialspace=True))
        if len(row) < 18:
            raise ValueError(f"Unexpected generator row in {raw_path}: {line}")
        bus, ident = row[0].strip(), row[1].strip().strip("'").strip()
        pg, qg = float(row[2]), float(row[3])
        qmax, qmin = float(row[4]), float(row[5])
        pmax, pmin = float(row[16]), float(row[17])
        radius = max(abs(qmin), abs(qmax))
        rows.append({
            "bus": bus, "id": ident, "status": row[14].strip(),
            "pg_mw": pg, "qg_mvar": qg,
            "pmin_original_mw": pmin, "pmax_original_mw": pmax,
            "qmin_original_mvar": qmin, "qmax_original_mvar": qmax,
            "pmin_study_mw": 0.0, "pmax_study_mw": pmax,
            "qmin_study_mvar": -radius, "qmax_study_mvar": radius,
        })
        parts = line.rstrip("\r\n").split(",")
        parts[4] = replace_number(parts[4], radius)
        parts[5] = replace_number(parts[5], -radius)
        parts[17] = replace_number(parts[17], 0.0)
        ending = "\r\n" if line.endswith("\r\n") else "\n" if line.endswith("\n") else ""
        out.append(",".join(parts) + ending)

    if not rows:
        raise ValueError(f"No generator records found in {raw_path}")
    raw_path.write_text("".join(out))
    with (target_dir / "generator_limits_original_and_study.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    (target_dir / "README.md").write_text(
        f"# {source} Pmin-zero, symmetric-Q study variant\n\n"
        f"This derived case copies `{source}/` without modifying it. In the PSS/E RAW generator "
        "records, every Pmin (PB) is set to 0 MW, including offline records, and reactive limits "
        "are made symmetric using `Qmin = -max(|Qmin_original|, |Qmax_original|)` and "
        "`Qmax = +max(|Qmin_original|, |Qmax_original|)`. Pmax and all other input files are "
        "preserved. `generator_limits_original_and_study.csv` records each generator's original "
        "and modified limits, along with its source PG/QG and status. Results from the previous "
        "Pmin-zero-only setup do not apply to this modified-Q case; resolve it separately for S1/S2.\n"
    )
    print(f"{source}: {len(rows)} generators -> {target}")


for src, dst in CASES.items():
    derive(src, dst)
