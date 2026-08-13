#!/usr/bin/env python3
"""Collect candidate HotSpot temperatures while excluding package nodes."""
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
        metadata_path = directory / "hotspot_export.json"; steady_path = directory / "steady.txt"
        if not metadata_path.exists() or not steady_path.exists(): continue
        metadata = json.loads(metadata_path.read_text(encoding="utf-8")); names = set(metadata["blocks"])
        temperatures = {}
        for line in steady_path.read_text(encoding="utf-8", errors="replace").splitlines():
            fields = line.split()
            if len(fields) == 2 and fields[0] in names:
                temperatures[fields[0]] = float(fields[1])
        status = "PASS" if len(temperatures) == len(names) else "FAIL"
        peak_name, peak = max(temperatures.items(), key=lambda item: item[1]) if temperatures else ("", float("nan"))
        rows.append({
            "strategy": directory.name, "status": status,
            "input_power_W": metadata["input_power_W"], "peak_temperature_K": peak,
            "peak_temperature_C": peak - 273.15, "peak_block": peak_name,
            "block_count": len(temperatures), "evidence_class": "modeled_hotspot_2d_estimated_power",
            "solver": metadata["solver"], "signoff": "NO",
            "steady_path": str(steady_path.relative_to(ROOT)).replace("\\", "/"),
        })
    if not rows or any(row["status"] != "PASS" for row in rows): raise RuntimeError("HotSpot candidate result incomplete")
    output = absolute(output_csv); output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0]); writer.writeheader(); writer.writerows(rows)
    print(f"FLOORPLAN_HOTSPOT_METRICS PASS runs={len(rows)} output={output}"); return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default="output/floorplan_optimization/hotspot")
    parser.add_argument("--output", default="output/floorplan_optimization/hotspot_results.csv")
    args = parser.parse_args(); collect(args.input, args.output); return 0


if __name__ == "__main__": raise SystemExit(main())
