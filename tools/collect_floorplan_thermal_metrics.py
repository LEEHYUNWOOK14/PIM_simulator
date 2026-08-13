#!/usr/bin/env python3
"""Collect validated, comparable thermal metrics from candidate solver outputs."""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def absolute(path: str | Path) -> Path:
    value = Path(path)
    return value if value.is_absolute() else ROOT / value


def collect(input_dir: str, output_csv: str) -> list[dict]:
    root = absolute(input_dir)
    rows = []
    for directory in sorted(path for path in root.iterdir() if path.is_dir()):
        summary_path = directory / "summary.json"
        mapped_path = directory / "mapped_power.json"
        field_path = directory / "temperature_field.npz"
        if not all(path.exists() for path in (summary_path, mapped_path, field_path)):
            continue
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
        mapped = json.loads(mapped_path.read_text(encoding="utf-8"))
        with np.load(field_path) as fields:
            temperature = fields["temperature_K"]
            raster_power = fields["power_W_cell"]
        logic_index = 2
        logic = temperature[logic_index]
        dx_mm = float(mapped["architecture"]["die_width_um"]) / logic.shape[1] / 1000.0
        dy_mm = float(mapped["architecture"]["die_height_um"]) / logic.shape[0] / 1000.0
        gy, gx = np.gradient(logic, dy_mm, dx_mm)
        residual_report = absolute("output/hbm2_thermal/validation/validation_report.json")
        validation = json.loads(residual_report.read_text(encoding="utf-8")) if residual_report.exists() else {"status": "MISSING"}
        expected = float(mapped["checks"]["mapped_power_W"])
        actual = float(raster_power.sum())
        rows.append({
            "strategy": directory.name, "status": summary["status"],
            "evidence_class": "modeled_reference_finite_volume_estimated_power",
            "solver": "reference_finite_volume_cpu_scipy_spsolve",
            "input_power_W": expected, "rasterized_power_W": actual,
            "power_conservation_error_W": abs(expected - actual),
            "peak_temperature_K": float(summary["peak_temperature_K"]),
            "peak_temperature_C": float(summary["peak_temperature_K"]) - 273.15,
            "peak_delta_K": float(summary["peak_delta_K"]),
            "max_logic_gradient_K_per_mm": float(np.hypot(gx, gy).max()),
            "hotspot_layer": summary["hotspot"]["layer"],
            "hotspot_x_index": summary["hotspot"]["x_index"],
            "hotspot_y_index": summary["hotspot"]["y_index"],
            "solver_validation": validation["status"],
            "steady_equation_residual_W": validation.get("checks", {}).get("steady_equation_residual_W", {}).get("value", ""),
            "classification": "modeled", "power_classification": "estimated",
            "signoff": "NO",
            "summary_path": str(summary_path.relative_to(ROOT)).replace("\\", "/"),
            "field_path": str(field_path.relative_to(ROOT)).replace("\\", "/"),
        })
    if not rows:
        raise RuntimeError("no complete candidate thermal outputs")
    if any(row["status"] != "PASS" or row["solver_validation"] != "PASS" or row["power_conservation_error_W"] > 1e-12 for row in rows):
        raise RuntimeError("candidate thermal validation failed")
    output = absolute(output_csv)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader(); writer.writerows(rows)
    print(f"FLOORPLAN_THERMAL_METRICS PASS runs={len(rows)} output={output}")
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default="output/floorplan_optimization/thermal")
    parser.add_argument("--output", default="output/floorplan_optimization/thermal_results.csv")
    args = parser.parse_args(); collect(args.input, args.output); return 0


if __name__ == "__main__":
    raise SystemExit(main())
