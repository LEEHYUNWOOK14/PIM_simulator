#!/usr/bin/env python3
"""Collect comparable metrics from manifest-driven OpenROAD proxy runs."""
from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WIRE_RE = re.compile(r"^\s*(met\d+)\s+([0-9.]+)um", re.MULTILINE)
UTIL_RE = re.compile(r"Effective utilization:\s+([0-9.]+)")
AREA_RE = re.compile(r"Total instances area:\s+([0-9.]+) um\^2")
INSTANCE_RE = re.compile(r"Number of instances:\s+([0-9]+)")
CONGESTION_RE = re.compile(r"comment:\s+capacity:(\d+)\s+usage:(\d+)\s+congestion:(\d+)")
DEF_COMPONENT_RE = re.compile(
    r"^\s*-\s+(\S+)\s+\S+\s+\+\s+FIXED\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\S+)\s*;",
    re.MULTILINE,
)


def absolute(path: str | Path) -> Path:
    value = Path(path)
    return value if value.is_absolute() else ROOT / value


def parse_congestion(path: Path) -> dict[str, int]:
    if not path.exists():
        return {"violations": 0, "overflow_sum": 0, "max_overflow": 0}
    values = [tuple(map(int, match)) for match in CONGESTION_RE.findall(path.read_text(encoding="utf-8", errors="replace"))]
    return {
        "violations": len(values),
        "overflow_sum": sum(max(0, usage - capacity) for capacity, usage, _ in values),
        "max_overflow": max((max(0, usage - capacity) for capacity, usage, _ in values), default=0),
    }


def verify_def_roundtrip(path: Path, metadata: dict) -> tuple[bool, float, int]:
    """Verify fixed placements against metadata; DEF coordinates use 1000 DBU/um."""
    if not path.exists() or not metadata.get("expected_placements"):
        return False, float("inf"), 0
    actual = {
        name: (int(x) / 1000.0, int(y) / 1000.0, orientation)
        for name, x, y, orientation in DEF_COMPONENT_RE.findall(path.read_text(encoding="utf-8", errors="replace"))
    }
    max_error = 0.0
    for expected in metadata["expected_placements"]:
        if expected["instance"] not in actual:
            return False, float("inf"), len(actual)
        x, y, orientation = actual[expected["instance"]]
        max_error = max(max_error, abs(x - expected["x_um"]), abs(y - expected["y_um"]))
        if orientation != expected["orientation"]:
            return False, max_error, len(actual)
    return max_error <= 0.001, max_error, len(actual)


def collect(input_dir: str, output_csv: str) -> list[dict]:
    root = absolute(input_dir)
    rows = []
    for directory in sorted(path for path in root.iterdir() if path.is_dir()):
        log_path = directory / "run.log"
        metadata_path = directory / "proxy_manifest.json"
        if not log_path.exists() or not metadata_path.exists():
            continue
        text = log_path.read_text(encoding="utf-8", errors="replace")
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        layers = {layer: float(value) for layer, value in WIRE_RE.findall(text)}
        util = UTIL_RE.search(text)
        area = AREA_RE.search(text)
        instances = INSTANCE_RE.search(text)
        guide = directory / "route.guide"
        def_path = directory / "floorplan_proxy.def"
        odb = directory / "floorplan_proxy.odb"
        congestion = parse_congestion(directory / "congestion.rpt")
        roundtrip_ok, max_coordinate_error_um, def_components = verify_def_roundtrip(def_path, metadata)
        status = "PASS" if "STOB_OPENROAD_PROXY PASS" in text and def_path.exists() and odb.exists() and roundtrip_ok else "FAIL"
        rows.append({
            "strategy": directory.name,
            "status": status,
            "evidence_class": "global_routed_modeled_macro_proxy",
            "openroad_version": "26Q3-1080-gab6fd26351",
            "blocks": len(metadata["blocks"]),
            "tsv_endpoints": metadata["tsv_endpoints"],
            "instance_count": int(instances.group(1)) if instances else "",
            "instance_area_um2": float(area.group(1)) if area else "",
            "effective_utilization": float(util.group(1)) if util else "",
            "global_route_wirelength_um": sum(layers.values()),
            "met2_wirelength_um": layers.get("met2", 0.0),
            "met3_wirelength_um": layers.get("met3", 0.0),
            "met4_wirelength_um": layers.get("met4", 0.0),
            "met5_wirelength_um": layers.get("met5", 0.0),
            "route_guide_bytes": guide.stat().st_size if guide.exists() else 0,
            "congestion_violation_bins": congestion["violations"],
            "global_route_overflow_sum": congestion["overflow_sum"],
            "global_route_max_overflow": congestion["max_overflow"],
            "routing_result": "global_routed_with_reported_overflow" if congestion["overflow_sum"] else "global_routed_no_reported_overflow",
            "def_coordinate_roundtrip": roundtrip_ok,
            "def_component_count": def_components,
            "max_coordinate_error_um": max_coordinate_error_um,
            "setup_wns_ns": "not_available_no_macro_liberty",
            "hold_wns_ns": "not_available_no_macro_liberty",
            "static_ir_drop_mV": "not_available_no_proxy_pdn",
            "def_path": str(def_path.relative_to(ROOT)).replace("\\", "/"),
            "odb_path": str(odb.relative_to(ROOT)).replace("\\", "/"),
            "limitations": ";".join(metadata["limitations"]),
        })
    output = absolute(output_csv)
    output.parent.mkdir(parents=True, exist_ok=True)
    if rows:
        with output.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
            writer.writeheader()
            writer.writerows(rows)
    if not rows or any(row["status"] != "PASS" for row in rows):
        raise RuntimeError("missing or failed OpenROAD proxy runs")
    print(f"OPENROAD_PROXY_METRICS PASS runs={len(rows)} output={output}")
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default="output/floorplan_optimization/openroad_proxy")
    parser.add_argument("--output", default="output/floorplan_optimization/openroad_proxy/openroad_proxy_metrics.csv")
    args = parser.parse_args()
    collect(args.input, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
