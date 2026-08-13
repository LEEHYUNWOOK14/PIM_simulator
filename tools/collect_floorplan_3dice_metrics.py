#!/usr/bin/env python3
"""Collect full-stack candidate metrics from pinned 3D-ICE outputs."""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def absolute(path: str | Path) -> Path:
    value = Path(path); return value if value.is_absolute() else ROOT / value


def collect(input_dir: str, output_csv: str) -> list[dict]:
    rows = []
    for directory in sorted(path for path in absolute(input_dir).iterdir() if path.is_dir()):
        metadata_path = directory / "3dice_export.json"; temperatures_path = directory / "floorplan_temperature.txt"; map_path = directory / "temperature_map.txt"; log_path = directory / "run.log"
        if not all(path.exists() for path in (metadata_path, temperatures_path, map_path, log_path)): continue
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        names, values = [], []
        for line in temperatures_path.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("% Time(s)"):
                names = [field.strip().removesuffix("(K)") for field in line.lstrip("% ").split("\t")[1:] if field.strip()]
            elif line and not line.startswith("%"):
                fields = line.split(); values = [float(value) for value in fields[1:]]
        peak_index = max(range(len(values)), key=values.__getitem__) if values else -1
        log = log_path.read_text(encoding="utf-8", errors="replace")
        status = "PASS" if values and len(values) == len(names) and "Emulation took" in log else "FAIL"
        rows.append({
            "strategy": directory.name, "status": status, "input_power_W": metadata["input_power_W"],
            "peak_temperature_K": values[peak_index] if peak_index >= 0 else "",
            "peak_temperature_C": values[peak_index] - 273.15 if peak_index >= 0 else "",
            "peak_block": names[peak_index] if peak_index >= 0 else "", "block_count": len(values),
            "temperature_map_bytes": map_path.stat().st_size,
            "evidence_class": "modeled_3dice_full_stack_estimated_power", "solver": metadata["solver"],
            "signoff": "NO", "temperature_map_path": str(map_path.relative_to(ROOT)).replace("\\", "/"),
        })
    if not rows or any(row["status"] != "PASS" for row in rows): raise RuntimeError("3D-ICE candidate result incomplete")
    output = absolute(output_csv); output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0]); writer.writeheader(); writer.writerows(rows)
    print(f"FLOORPLAN_3DICE_METRICS PASS runs={len(rows)} output={output}"); return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument("--input", default="output/floorplan_optimization/3dice"); parser.add_argument("--output", default="output/floorplan_optimization/3dice_results.csv")
    args = parser.parse_args(); collect(args.input, args.output); return 0


if __name__ == "__main__": raise SystemExit(main())
