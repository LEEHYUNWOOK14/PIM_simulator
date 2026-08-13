#!/usr/bin/env python3
"""Generate three deterministic five-axis adapter fixture sets."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from hardware_cost_adapter_contract import CATEGORIES, require_valid_adapter


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DEFINITIONS = ROOT / "hardware_cost" / "regression" / "synthetic_candidate_definitions.json"


def digest(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def category_metrics(total_area, total_power, area_fractions, power_fractions, leakage_fraction):
    area = {name: total_area * area_fractions[name] for name in CATEGORIES}
    power = {}
    for name in CATEGORIES:
        total = total_power * power_fractions[name]
        leakage = total * leakage_fraction
        power[name] = {"mapped_area_um2": area[name], "dynamic_power_W": total - leakage, "leakage_power_W": leakage, "total_power_W": total}
    area_rows = {name: {"mapped_area_um2": area[name], "dynamic_power_W": None, "leakage_power_W": None, "total_power_W": None} for name in CATEGORIES}
    return area_rows, power


def generate(definitions_path=DEFAULT_DEFINITIONS, output_path="output/hardware_cost_adapter_v2/adapters"):
    definitions_path = Path(definitions_path) if Path(definitions_path).is_absolute() else ROOT / definitions_path
    output = Path(output_path) if Path(output_path).is_absolute() else ROOT / output_path
    definitions = json.loads(definitions_path.read_text(encoding="utf-8"))
    common = definitions["common"]
    evidence = {"path": definitions_path.relative_to(ROOT).as_posix(), "sha256": digest(definitions_path), "bytes": definitions_path.stat().st_size}
    written = []
    for candidate in definitions["candidates"]:
        candidate_meta = {"id": candidate["id"], "label": candidate["label"], "parameters": {"lanes": None, "bank_port_mode": None, "scheduler_policy": None, "context_depth": None}}
        trace_id = f"fixture:{candidate['id']}"
        operating = {"pdk": None, "library": None, "process_corner": None, "voltage_V": None, "temperature_C": common["ambient_temperature_C"], "clock_constraint_ns": common["clock_constraint_ns"], "workload_trace_id": trace_id}
        area_categories, power_categories = category_metrics(candidate["mapped_floorplan_area_um2"], candidate["total_power_W"], common["area_fractions"], common["power_fractions"], common["leakage_fraction"])
        blocks = []
        for index, name in enumerate(CATEGORIES):
            values = power_categories[name]
            blocks.append({"instance": f"top.{name}", "module": f"synthetic_{name}", "category": name, "target": {"stack": 0, "layer": "logic", "die": -1, "channel": -1, "bank": -1}, **values})
        dynamic = candidate["total_power_W"] * (1.0 - common["leakage_fraction"])
        leakage = candidate["total_power_W"] * common["leakage_fraction"]
        base = {"schema_version": 1, "adapter_contract_version": 1, "status": "PASS", "candidate": candidate_meta, "claim_class": "assumed", "operating_point": operating, "source_evidence": [evidence], "notes": ["Deterministic synthetic fixture; not physical evidence."]}
        documents = {
            "area": {**base, "axis": "area", "calibration": "synthetic", "tool": {"name": "synthetic-area-fixture", "version": "1"}, "metrics": {"precision": common["precision"], "primary_category": "normalization_rounding", "generic_cells": candidate["generic_cells"], "generic_topological_path_length": candidate["generic_topological_path_length"], "technology_mapped_area_um2": None, "mapped_floorplan_area_um2": candidate["mapped_floorplan_area_um2"], "categories": area_categories}},
            "timing": {**base, "axis": "timing", "calibration": "synthetic", "tool": {"name": "synthetic-timing-fixture", "version": "1"}, "metrics": {"critical_path_ns": candidate["critical_path_ns"], "slack_ns": candidate["slack_ns"]}},
            "power": {**base, "axis": "power", "calibration": "synthetic", "tool": {"name": "synthetic-power-fixture", "version": "1"}, "metrics": {"dynamic_power_W": dynamic, "leakage_power_W": leakage, "total_power_W": candidate["total_power_W"], "categories": power_categories, "blocks": blocks}},
            "workload": {**base, "axis": "workload", "calibration": "workload_model", "claim_class": "modeled", "tool": {"name": "synthetic-workload-fixture", "version": "1"}, "metrics": {"name": "synthetic_normalization", "precision": common["precision"], "operation_count": candidate["operation_count"], "latency_cycles": candidate["latency_cycles"], "clock_period_ns": common["clock_constraint_ns"], "throughput_ops_s": candidate["throughput_ops_s"]}},
            "thermal": {**base, "axis": "thermal", "calibration": "synthetic_architectural", "claim_class": "modeled", "tool": {"name": "synthetic-thermal-fixture", "version": "1"}, "metrics": {"peak_temperature_K": candidate["peak_temperature_K"], "peak_delta_K": candidate["peak_temperature_K"] - (common["ambient_temperature_C"] + 273.15), "hotspot": candidate["hotspot"]}},
        }
        candidate_dir = output / candidate["id"]
        candidate_dir.mkdir(parents=True, exist_ok=True)
        for axis, document in documents.items():
            require_valid_adapter(document)
            path = candidate_dir / f"{axis}.json"
            path.write_text(json.dumps(document, indent=2), encoding="utf-8")
            written.append(path)
    print(f"SYNTHETIC_HARDWARE_COST_ADAPTERS PASS candidates={len(definitions['candidates'])} outputs={len(written)}")
    return written


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--definitions", default=str(DEFAULT_DEFINITIONS))
    parser.add_argument("--output", default="output/hardware_cost_adapter_v2/adapters")
    args = parser.parse_args()
    generate(args.definitions, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
