#!/usr/bin/env python3
"""Adapt existing STOB package/architecture snapshots to the canonical floorplan IR."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]

ROLE = {
    "logic_die_64ch_reduction_top": "cross-channel reduction",
    "bank_local_reduction_buffer": "bank reduction buffering",
    "bank_local_fp16_reduction": "bank reduction arithmetic",
    "hierarchical_reduction_path": "hierarchical reduction",
    "logic_die_link_arbiter": "TSV link arbitration",
    "logic_die_dual_link_arbiter": "dual-link arbitration",
    "shared_fp16_pipeline_fabric": "shared arithmetic fabric",
    "shared_fp16_reduction_cluster": "shared reduction cluster",
}

DEFAULT_TOTAL_POWER_W = {
    "logic_die_64ch_reduction_top": 0.55,
    "bank_local_reduction_buffer": 0.25,
    "bank_local_fp16_reduction": 0.45,
    "hierarchical_reduction_path": 0.55,
    "logic_die_link_arbiter": 0.20,
    "logic_die_dual_link_arbiter": 0.20,
    "shared_fp16_pipeline_fabric": 1.00,
    "shared_fp16_reduction_cluster": 0.80,
}

TIMING_CRITICALITY = {
    "logic_die_64ch_reduction_top": 0.90,
    "bank_local_reduction_buffer": 0.45,
    "bank_local_fp16_reduction": 0.75,
    "hierarchical_reduction_path": 0.95,
    "logic_die_link_arbiter": 0.70,
    "logic_die_dual_link_arbiter": 0.70,
    "shared_fp16_pipeline_fabric": 1.00,
    "shared_fp16_reduction_cluster": 0.90,
}


def absolute(path: str | Path) -> Path:
    value = Path(path)
    return value if value.is_absolute() else ROOT / value


def read_json(path: str | Path) -> dict[str, Any]:
    return json.loads(absolute(path).read_text(encoding="utf-8-sig"))


def sha256(path: str | Path) -> str:
    digest = hashlib.sha256()
    with absolute(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def git_snapshot() -> tuple[str, bool]:
    try:
        commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip())
        return commit, dirty
    except (OSError, subprocess.CalledProcessError):
        return "0" * 40, True


def load_csv(path: str | None) -> dict[str, dict[str, str]]:
    if not path:
        return {}
    with absolute(path).open(newline="", encoding="utf-8-sig") as stream:
        rows = list(csv.DictReader(stream))
    return {row["instance"]: row for row in rows}


def provenance(source_id: str, source_path: str, description: str) -> dict[str, Any]:
    path = absolute(source_path)
    return {
        "source_id": source_id,
        "source_path": source_path.replace("\\", "/"),
        "source_hash_sha256": sha256(path) if path.exists() else None,
        "description": description,
    }


def generate(
    architecture_path: str,
    package_path: str,
    output_path: str,
    tsv_output_path: str,
    placement_csv: str | None = None,
    normalized_input: str | None = None,
) -> dict[str, Any]:
    architecture = read_json(architecture_path)
    package = read_json(package_path)
    placements = load_csv(placement_csv)
    normalized = read_json(normalized_input) if normalized_input else {"blocks": []}
    physical = {item["instance"]: item for item in normalized.get("blocks", [])}
    by_module = {item["module"]: item for item in normalized.get("blocks", [])}

    die_w = float(package["logic_die_width_um"])
    die_h = float(package["logic_die_height_um"])
    source_hashes = {
        architecture_path.replace("\\", "/"): sha256(architecture_path),
        package_path.replace("\\", "/"): sha256(package_path),
    }
    for optional in (placement_csv, normalized_input):
        if optional:
            source_hashes[optional.replace("\\", "/")] = sha256(optional)
    commit, dirty = git_snapshot()

    slots_x = [675.0, 1675.0, 2675.0, 4675.0]
    slots_y = [1100.0, 6500.0]
    blocks: list[dict[str, Any]] = []
    modules = architecture["rtl_modules"]
    for index, module in enumerate(modules):
        instance = f"top.{module}"
        x = slots_x[index % len(slots_x)]
        y = slots_y[(index // len(slots_x)) % len(slots_y)]
        width, height = 650.0, 4000.0
        placement_source = "deterministic_architecture_adapter_grid"
        classification = "illustrative"
        confidence = "low"
        status = "illustrative"
        if instance in placements:
            row = placements[instance]
            x, y = float(row["x_um"]), float(row["y_um"])
            width, height = float(row["width_um"]), float(row["height_um"])
            placement_source = placement_csv or "placement_csv"
            classification, confidence, status = "placed", "medium", "placed"
        p = physical.get(instance) or by_module.get(module) or {}
        if p:
            dynamic = float(p.get("dynamic_power_W", 0.0))
            leakage = float(p.get("leakage_power_W", 0.0))
            power_source = normalized_input or "normalized_physical_input"
        else:
            total = DEFAULT_TOTAL_POWER_W.get(module, 0.1)
            dynamic, leakage = total * 0.9, total * 0.1
            power_source = "estimated_4W_logic_die_allocation_for_relative_candidate_comparison"
        area_source = normalized_input if p else "illustrative_adapter_tile"
        block_provenance_path = placement_csv or architecture_path
        if module in {"bank_local_reduction_buffer", "bank_local_fp16_reduction"}:
            endpoint_channels = range(4) if index % 2 == 0 else range(4, int(package["channel_count"]))
        else:
            endpoint_channels = range(int(package["channel_count"]))
        blocks.append({
            "instance": instance,
            "module": module,
            "role": ROLE.get(module, module.replace("_", " ")),
            "x_um": x, "y_um": y, "width_um": width, "height_um": height,
            "orientation": "N",
            "area_source": area_source,
            "placement_source": placement_source,
            "status": status,
            "dynamic_W": dynamic,
            "leakage_W": leakage,
            "power_source": power_source,
            "clock_domain": "clk_i",
            "voltage_domain": "logic_vdd_unspecified",
            "traffic_endpoints": [f"dram.channel[{channel}]" for channel in endpoint_channels],
            "timing_criticality": TIMING_CRITICALITY.get(module, 0.5),
            "movable": status != "routed",
            "halo_um": 25.0,
            "allowed_region": {"x_um": 250.0, "y_um": 800.0, "width_um": die_w - 500.0, "height_um": die_h - 1050.0},
            "classification": classification,
            "confidence": confidence,
            "provenance": provenance("floorplan_adapter", block_provenance_path, "Adapted without changing RTL."),
        })

    tsv_bundles: list[dict[str, Any]] = []
    micro_bumps: list[dict[str, Any]] = []
    channels = int(package["channel_count"])
    # These arrays refine the old representative column into class-visible
    # channel bundles. Counts are research geometry, not a manufacturer pin map.
    bundle_specs = [
        ("DATA", "data", 8, 2, 1000.0, 128, "bidirectional", 0),
        ("CA", "command_address", 2, 2, 2300.0, 32, "down", 0),
        ("CLK", "clock", 1, 2, 2700.0, 2, "down", 0),
        ("POWER", "power", 4, 2, 3000.0, None, "not_applicable", 0),
        ("GROUND", "ground", 4, 2, 3800.0, None, "not_applicable", 0),
        ("SPARE", "spare", 1, 2, 4600.0, 0, "not_applicable", 2),
    ]
    for channel in range(channels):
        center_x = (channel + 0.5) * die_w / channels
        for label, signal_class, rows, columns, y, bandwidth, direction, redundancy in bundle_specs:
            tsv_id = f"TSV_CH{channel}_{label}"
            bump_id = f"MBUMP_CH{channel}_{label}"
            common = {
                "signal_class": signal_class,
                "x_um": center_x - 75.0 if columns > 1 else center_x,
                "y_um": y,
                "rows": rows,
                "columns": columns,
                "pitch_um": 150.0,
                "redundancy_count": redundancy,
                "bandwidth_bits": bandwidth,
                "direction": direction,
                "connectivity_source": "channel/class-level illustrative mapping; no public bit-level pin map",
                "classification": "illustrative",
                "confidence": "low",
            }
            tsv_bundles.append({
                "bundle_id": tsv_id,
                "kind": "tsv",
                "source": f"dram.channel[{channel}]",
                "destinations": [bump_id],
                **common,
                "diameter_um": float(package["tsv_size_um"]),
                "keepout_um": 50.0,
                "geometry_source": architecture_path,
                "uncertainty": {"distribution": "uniform", "min": 35.0, "max": 80.0},
                "provenance": provenance("detailed_hbm2_tsv_bundle_assumption", architecture_path, "Signal-class-visible TSV bundle derived from the old channel representative."),
            })
            micro_bumps.append({
                "bundle_id": bump_id,
                "kind": "micro_bump",
                "source": tsv_id,
                "destinations": ["top.logic_die_link_arbiter"],
                **common,
                "diameter_um": float(package["microbump_size_um"]),
                "keepout_um": 15.0,
                "geometry_source": package_path,
                "uncertainty": {"distribution": "uniform", "min": 15.0, "max": 35.0},
                "provenance": provenance("detailed_hbm2_microbump_bundle_assumption", package_path, "Micro-bump bundle paired one-to-one with its TSV bundle."),
            })

    region_provenance = provenance("floorplan_reserved_region_assumptions", package_path, "Research-only reserved-region assumptions.")
    reserved = [
        {"region_id": "PHY_SOUTH", "role": "phy", "x_um": 250.0, "y_um": 0.0, "width_um": die_w - 500.0, "height_um": 800.0, "blocks_prohibited": True, "classification": "estimated", "confidence": "low", "provenance": region_provenance},
        {"region_id": "PDN_WEST", "role": "pdn", "x_um": 0.0, "y_um": 0.0, "width_um": 250.0, "height_um": die_h, "blocks_prohibited": True, "classification": "illustrative", "confidence": "low", "provenance": region_provenance},
        {"region_id": "PDN_EAST", "role": "pdn", "x_um": die_w - 250.0, "y_um": 0.0, "width_um": 250.0, "height_um": die_h, "blocks_prohibited": True, "classification": "illustrative", "confidence": "low", "provenance": region_provenance},
        {"region_id": "CLOCK_SPINE", "role": "clock", "x_um": 3900.0, "y_um": 800.0, "width_um": 200.0, "height_um": die_h - 800.0, "blocks_prohibited": True, "classification": "illustrative", "confidence": "low", "provenance": region_provenance},
    ]
    corridors = []
    for channel in range(channels):
        corridors.append({
            "region_id": f"TSV_CORRIDOR_CH{channel}", "role": "routing",
            "x_um": (channel + 0.5) * die_w / channels - 75.0, "y_um": 800.0,
            "width_um": 150.0, "height_um": die_h - 800.0,
            "blocks_prohibited": False, "classification": "illustrative", "confidence": "low",
            "provenance": region_provenance,
        })

    manifest = {
        "schema_version": "1.0",
        "manifest_id": "stob_logic_die_floorplan_baseline_v1",
        "coordinate_system": {"origin": "logic_die_lower_left", "positive_x": "right", "positive_y": "up", "length_unit": "um", "bundle_anchor": "lower_left_element_center"},
        "die": {"x_um": 0.0, "y_um": 0.0, "width_um": die_w, "height_um": die_h},
        "evidence_snapshot": {"git_commit": commit, "working_tree_dirty": dirty, "captured_at": datetime.now(timezone.utc).isoformat(), "source_manifest_hashes": source_hashes},
        "external_endpoints": ["package.interposer", "host", "vdd", "vss"] + [f"dram.channel[{i}]" for i in range(channels)],
        "blocks": blocks,
        "tsv_bundles": tsv_bundles,
        "micro_bump_bundles": micro_bumps,
        "reserved_regions": reserved,
        "routing_corridors": corridors,
        "legacy_compatibility": {"logic_block_x_um": float(package["logic_block_x_um"]), "logic_block_y_um": float(package["logic_block_y_um"]), "source": package_path},
    }

    output = absolute(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    tsv_output = absolute(tsv_output_path)
    tsv_output.parent.mkdir(parents=True, exist_ok=True)
    fields = ["bundle_id", "kind", "signal_class", "source", "destinations", "x_um", "y_um", "rows", "columns", "pitch_um", "diameter_um", "keepout_um", "redundancy_count", "bandwidth_bits", "direction", "geometry_source", "connectivity_source", "classification", "confidence"]
    with tsv_output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for bundle in tsv_bundles:
            row = {field: bundle.get(field) for field in fields}
            row["destinations"] = ";".join(bundle["destinations"])
            writer.writerow(row)
    print(f"FLOORPLAN_MANIFEST_GENERATED blocks={len(blocks)} tsv_bundles={len(tsv_bundles)} output={output}")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--architecture", default="design/hbm2_architecture.json")
    parser.add_argument("--package", default="design/hbm2_package.json")
    parser.add_argument("--placement-csv")
    parser.add_argument("--normalized-input")
    parser.add_argument("--output", default="design/floorplan/logic_die_floorplan.json")
    parser.add_argument("--tsv-output", default="design/floorplan/tsv_connectivity.csv")
    args = parser.parse_args()
    generate(args.architecture, args.package, args.output, args.tsv_output, args.placement_csv, args.normalized_input)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
