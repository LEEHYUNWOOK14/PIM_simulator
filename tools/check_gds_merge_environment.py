#!/usr/bin/env python3
"""Create, transform, merge, and independently inspect tiny GDS fixtures."""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import math
import platform
from datetime import datetime, timezone
from pathlib import Path

import gdstk
import klayout.db as kdb
import numpy as np
from shapely.geometry import Point, Polygon


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def recursive_shape_count(cell: kdb.Cell, layer_index: int) -> int:
    iterator = cell.begin_shapes_rec(layer_index)
    count = 0
    while not iterator.at_end():
        count += 1
        iterator.next()
    return count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    output = Path(args.output).resolve()
    report_path = Path(args.report).resolve()
    output.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)

    rtl_path = output / "rtl_fixture.gds"
    overlay_path = output / "tsv_overlay_fixture.gds"
    merged_path = output / "merged_transform_smoke.gds"

    rtl_lib = gdstk.Library(unit=1e-6, precision=1e-9)
    rtl_cell = rtl_lib.new_cell("RTL_ROUTED_FIXTURE")
    rtl_cell.add(gdstk.rectangle((0, 0), (100, 50), layer=10, datatype=0))
    rtl_lib.write_gds(rtl_path)

    overlay_lib = gdstk.Library(unit=1e-6, precision=1e-9)
    overlay_cell = overlay_lib.new_cell("TSV_OVERLAY_FIXTURE")
    overlay_cell.add(gdstk.ellipse((0, 0), 5, layer=120, datatype=0))
    overlay_lib.write_gds(overlay_path)

    rtl_read = gdstk.read_gds(rtl_path)
    overlay_read = gdstk.read_gds(overlay_path)
    merged = gdstk.Library(unit=1e-6, precision=1e-9)
    merged.add(*rtl_read.cells, *overlay_read.cells)
    top = merged.new_cell("GDS_MERGE_TRANSFORM_SMOKE_TOP")
    top.add(gdstk.Reference(rtl_read.top_level()[0], origin=(1000, 2000), rotation=math.pi / 2))
    top.add(gdstk.Reference(overlay_read.top_level()[0], origin=(1025, 2050)))
    merged.write_gds(merged_path)

    layout = kdb.Layout()
    layout.read(str(merged_path))
    checked_top = layout.cell("GDS_MERGE_TRANSFORM_SMOKE_TOP")
    if checked_top is None:
        raise RuntimeError("merged top cell missing")
    metal_layer = layout.find_layer(10, 0)
    tsv_layer = layout.find_layer(120, 0)
    metal_shapes = recursive_shape_count(checked_top, metal_layer)
    tsv_shapes = recursive_shape_count(checked_top, tsv_layer)
    if (metal_shapes, tsv_shapes) != (1, 1):
        raise RuntimeError(f"recursive shape mismatch: metal={metal_shapes} tsv={tsv_shapes}")
    bbox = checked_top.bbox()
    expected_bbox_dbu = [950000, 2000000, 1030000, 2100000]
    actual_bbox_dbu = [bbox.left, bbox.bottom, bbox.right, bbox.top]
    if actual_bbox_dbu != expected_bbox_dbu:
        raise RuntimeError(f"transformed bbox mismatch: {actual_bbox_dbu} != {expected_bbox_dbu}")

    transformed_rtl = Polygon([(1000, 2000), (1000, 2100), (950, 2100), (950, 2000)])
    tsv = Point(1025, 2050).buffer(5)
    clearance_um = transformed_rtl.distance(tsv)
    if not np.isclose(clearance_um, 20.0, atol=1e-6):
        raise RuntimeError(f"geometry clearance mismatch: {clearance_um}")

    artifacts = []
    for path in (rtl_path, overlay_path, merged_path):
        artifacts.append({"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)})
    report = {
        "status": "PASS", "generated_at": datetime.now(timezone.utc).isoformat(),
        "host": platform.platform(), "python": platform.python_version(),
        "versions": {name: importlib.metadata.version(name) for name in
                     ("klayout", "gdstk", "numpy", "shapely", "jsonschema", "PyYAML", "Pillow")},
        "smoke": {
            "operation": "separate GDS read -> 90-degree rotation + translation -> hierarchy-preserving merge",
            "unit_um": 1.0, "precision_um": 0.001,
            "merged_top": checked_top.name,
            "bbox_dbu": actual_bbox_dbu,
            "metal_shapes_recursive": metal_shapes,
            "tsv_shapes_recursive": tsv_shapes,
            "geometry_clearance_um": clearance_um,
        },
        "artifacts": artifacts,
    }
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"GDS_MERGE_TRANSFORM_SMOKE PASS merged={merged_path} report={report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
