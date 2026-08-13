#!/usr/bin/env python3
"""Validate schema, geometry, connectivity, units and CSV round-trip of a floorplan manifest."""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]


class FloorplanValidationError(ValueError):
    pass


def absolute(path: str | Path) -> Path:
    value = Path(path)
    return value if value.is_absolute() else ROOT / value


def load(path: str | Path) -> dict[str, Any]:
    return json.loads(absolute(path).read_text(encoding="utf-8-sig"))


def rectangle(item: dict[str, Any], halo: float = 0.0) -> tuple[float, float, float, float]:
    return (
        float(item["x_um"]) - halo,
        float(item["y_um"]) - halo,
        float(item["x_um"]) + float(item["width_um"]) + halo,
        float(item["y_um"]) + float(item["height_um"]) + halo,
    )


def overlaps(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> bool:
    return a[0] < b[2] and a[2] > b[0] and a[1] < b[3] and a[3] > b[1]


def contained(inner: tuple[float, float, float, float], outer: tuple[float, float, float, float]) -> bool:
    return inner[0] >= outer[0] and inner[1] >= outer[1] and inner[2] <= outer[2] and inner[3] <= outer[3]


def bundle_points(bundle: dict[str, Any]) -> list[tuple[float, float]]:
    return [
        (float(bundle["x_um"]) + column * float(bundle["pitch_um"]),
         float(bundle["y_um"]) + row * float(bundle["pitch_um"]))
        for column in range(int(bundle["columns"]))
        for row in range(int(bundle["rows"]))
    ]


def circle_hits_rect(x: float, y: float, radius: float, rect: tuple[float, float, float, float]) -> bool:
    nearest_x = min(max(x, rect[0]), rect[2])
    nearest_y = min(max(y, rect[1]), rect[3])
    return (x - nearest_x) ** 2 + (y - nearest_y) ** 2 < radius ** 2


def unique(items: list[dict[str, Any]], key: str, label: str) -> None:
    values = [item[key] for item in items]
    duplicates = sorted({value for value in values if values.count(value) > 1})
    if duplicates:
        raise FloorplanValidationError(f"duplicate {label}: {', '.join(duplicates)}")


def validate_csv(manifest: dict[str, Any], csv_path: str | Path) -> None:
    with absolute(csv_path).open(newline="", encoding="utf-8-sig") as stream:
        rows = list(csv.DictReader(stream))
    by_id = {row["bundle_id"]: row for row in rows}
    expected = {item["bundle_id"]: item for item in manifest["tsv_bundles"]}
    if set(by_id) != set(expected):
        raise FloorplanValidationError("TSV CSV bundle IDs do not match manifest")
    numeric = ("x_um", "y_um", "pitch_um", "diameter_um", "keepout_um")
    integer = ("rows", "columns", "redundancy_count")
    for bundle_id, bundle in expected.items():
        row = by_id[bundle_id]
        for field in ("kind", "signal_class", "source", "direction", "classification", "confidence"):
            if row[field] != str(bundle[field]):
                raise FloorplanValidationError(f"{bundle_id}: CSV mismatch in {field}")
        if row["destinations"].split(";") != bundle["destinations"]:
            raise FloorplanValidationError(f"{bundle_id}: CSV destination mismatch")
        for field in numeric:
            if not math.isclose(float(row[field]), float(bundle[field]), rel_tol=0, abs_tol=1e-9):
                raise FloorplanValidationError(f"{bundle_id}: CSV mismatch in {field}")
        for field in integer:
            if int(row[field]) != int(bundle[field]):
                raise FloorplanValidationError(f"{bundle_id}: CSV mismatch in {field}")


def validate(manifest_path: str, schema_path: str, tsv_csv: str | None = None) -> dict[str, Any]:
    manifest = load(manifest_path)
    schema = load(schema_path)
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = sorted(validator.iter_errors(manifest), key=lambda error: list(error.absolute_path))
    if errors:
        error = errors[0]
        location = "/".join(str(part) for part in error.absolute_path) or "<root>"
        raise FloorplanValidationError(f"schema {location}: {error.message}")

    blocks = manifest["blocks"]
    tsv = manifest["tsv_bundles"]
    bumps = manifest["micro_bump_bundles"]
    regions = manifest["reserved_regions"]
    corridors = manifest["routing_corridors"]
    unique(blocks, "instance", "block instance")
    unique(tsv + bumps, "bundle_id", "vertical bundle ID")
    unique(regions + corridors, "region_id", "region ID")
    if any(item["kind"] != "tsv" for item in tsv):
        raise FloorplanValidationError("tsv_bundles contains non-TSV kind")
    if any(item["kind"] != "micro_bump" for item in bumps):
        raise FloorplanValidationError("micro_bump_bundles contains non-micro-bump kind")

    die = rectangle(manifest["die"])
    block_rects: dict[str, tuple[float, float, float, float]] = {}
    for block in blocks:
        rect = rectangle(block, float(block["halo_um"]))
        if not contained(rect, die):
            raise FloorplanValidationError(f"{block['instance']}: block/halo outside die")
        if block["allowed_region"] is not None and not contained(rectangle(block), rectangle(block["allowed_region"])):
            raise FloorplanValidationError(f"{block['instance']}: outside allowed_region")
        block_rects[block["instance"]] = rect
    names = list(block_rects)
    for left in range(len(names)):
        for right in range(left + 1, len(names)):
            if overlaps(block_rects[names[left]], block_rects[names[right]]):
                raise FloorplanValidationError(f"block overlap: {names[left]} and {names[right]}")

    for region in regions + corridors:
        if not contained(rectangle(region), die):
            raise FloorplanValidationError(f"{region['region_id']}: region outside die")
        if region["blocks_prohibited"]:
            for name, rect in block_rects.items():
                if overlaps(rect, rectangle(region)):
                    raise FloorplanValidationError(f"{name}: overlaps prohibited region {region['region_id']}")

    endpoints = (
        set(manifest["external_endpoints"])
        | {block["instance"] for block in blocks}
        | {bundle["bundle_id"] for bundle in tsv + bumps}
    )
    all_tsv_points: list[tuple[str, float, float, float]] = []
    for bundle in tsv + bumps:
        if bundle["source"] not in endpoints:
            raise FloorplanValidationError(f"{bundle['bundle_id']}: dangling source {bundle['source']}")
        dangling = [item for item in bundle["destinations"] if item not in endpoints]
        if dangling:
            raise FloorplanValidationError(f"{bundle['bundle_id']}: dangling destinations {dangling}")
        if "uncertainty" in bundle and bundle["uncertainty"]["min"] > bundle["uncertainty"]["max"]:
            raise FloorplanValidationError(f"{bundle['bundle_id']}: invalid uncertainty range")
        radius = float(bundle["diameter_um"]) / 2 + float(bundle["keepout_um"])
        if float(bundle["pitch_um"]) + 1e-12 < 2 * radius and (int(bundle["rows"]) > 1 or int(bundle["columns"]) > 1):
            raise FloorplanValidationError(f"{bundle['bundle_id']}: pitch violates diameter plus keep-out")
        for x, y in bundle_points(bundle):
            if x - radius < die[0] or y - radius < die[1] or x + radius > die[2] or y + radius > die[3]:
                raise FloorplanValidationError(f"{bundle['bundle_id']}: element/keep-out outside die")
            if bundle["kind"] == "tsv":
                for name, rect in block_rects.items():
                    if circle_hits_rect(x, y, radius, rect):
                        raise FloorplanValidationError(f"{name}: violates TSV keep-out {bundle['bundle_id']}")
                all_tsv_points.append((bundle["bundle_id"], x, y, radius))
    for left in range(len(all_tsv_points)):
        a_id, ax, ay, ar = all_tsv_points[left]
        for right in range(left + 1, len(all_tsv_points)):
            b_id, bx, by, br = all_tsv_points[right]
            if math.hypot(ax - bx, ay - by) + 1e-9 < ar + br:
                raise FloorplanValidationError(f"TSV keep-out overlap: {a_id} and {b_id}")

    if tsv_csv:
        validate_csv(manifest, tsv_csv)
    report = {
        "status": "PASS",
        "manifest": str(absolute(manifest_path)),
        "checks": {
            "json_schema": "PASS", "coordinate_units": "PASS", "unique_ids": "PASS",
            "die_boundary": "PASS", "block_overlap": "PASS", "allowed_regions": "PASS",
            "reserved_regions": "PASS", "tsv_pitch_keepout": "PASS",
            "connectivity_endpoints": "PASS", "tsv_csv_roundtrip": "PASS" if tsv_csv else "NOT_RUN"
        },
        "counts": {
            "blocks": len(blocks), "tsv_bundles": len(tsv),
            "tsv_shapes": sum(int(item["rows"]) * int(item["columns"]) for item in tsv),
            "micro_bump_bundles": len(bumps),
            "micro_bump_shapes": sum(int(item["rows"]) * int(item["columns"]) for item in bumps),
            "reserved_regions": len(regions), "routing_corridors": len(corridors)
        },
        "scope": "Architectural floorplan contract validation; not foundry DRC, LVS, PI, thermal or timing signoff."
    }
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default="design/floorplan/logic_die_floorplan.json")
    parser.add_argument("--schema", default="design/floorplan/logic_die_floorplan.schema.json")
    parser.add_argument("--tsv-csv", default="design/floorplan/tsv_connectivity.csv")
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        report = validate(args.manifest, args.schema, args.tsv_csv or None)
    except (FloorplanValidationError, OSError, json.JSONDecodeError) as error:
        print(f"FLOORPLAN_VALIDATION_ERROR: {error}")
        return 2
    text = json.dumps(report, indent=2)
    if args.output:
        output = absolute(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
