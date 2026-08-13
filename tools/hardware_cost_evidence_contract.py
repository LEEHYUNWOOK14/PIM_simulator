#!/usr/bin/env python3
"""Shared Evidence Contract v2 calibration rules and snapshot validation."""
from __future__ import annotations

import json
import math
from pathlib import Path

from jsonschema import Draft202012Validator

from physical_feasibility_contract import validate_physical_feasibility


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "hardware_cost" / "regression" / "snapshot_schema.json"
CALIBRATION_ORDER = (
    "synthetic",
    "synthesis_generic",
    "technology_mapped",
    "placed",
    "activity_based",
    "post_route",
    "measured",
)
RANK = {name: index for index, name in enumerate(CALIBRATION_ORDER)}
ALIASES = {
    "synthetic_architectural": "synthetic",
    "workload_model": "synthetic",
}
UNAVAILABLE = {"not_available", "pending"}
AXIS_LEVELS = {
    "synthesis": {"synthesis_generic", "technology_mapped", "placed", "post_route", "measured"},
    "physical": {"synthetic", "technology_mapped", "placed", "post_route", "measured"},
    "power": {"synthetic", "activity_based", "post_route", "measured"},
    "thermal": {"synthetic_architectural", "activity_based", "post_route", "measured"},
    "timing": {"not_available", "synthetic", "technology_mapped", "placed", "post_route", "measured"},
    "workload": {"pending", "workload_model", "measured"},
}


class EvidenceContractError(ValueError):
    pass


def comparison_policy(left: str, right: str) -> dict:
    """Return whether a numerical delta is defensible for two evidence levels."""
    if left in UNAVAILABLE or right in UNAVAILABLE:
        return {"status": "unavailable", "delta_allowed": False, "distance": None}
    a, b = ALIASES.get(left, left), ALIASES.get(right, right)
    if a not in RANK or b not in RANK:
        raise EvidenceContractError(f"unknown calibration level: {left!r}, {right!r}")
    distance = abs(RANK[a] - RANK[b])
    if distance == 0:
        return {"status": "quantitative", "delta_allowed": True, "distance": 0}
    if distance == 1:
        return {"status": "reference_only", "delta_allowed": False, "distance": 1}
    return {"status": "prohibited", "delta_allowed": False, "distance": distance}


def _finite(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def validate_snapshot(snapshot: dict, schema_path: Path = SCHEMA) -> list[str]:
    """Validate schema plus cross-field calibration/metric invariants."""
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    errors = [
        f"{'.'.join(str(x) for x in error.absolute_path) or '<root>'}: {error.message}"
        for error in sorted(Draft202012Validator(schema).iter_errors(snapshot), key=lambda e: list(e.absolute_path))
    ]
    if errors:
        return errors

    errors.extend(
        f"physical_feasibility.{error}"
        for error in validate_physical_feasibility(snapshot["physical_feasibility"], verify_sources=True)
    )
    if errors:
        return errors

    calibration = snapshot["calibration"]
    contract = snapshot["evidence_contract"]
    tools = contract["toolchain"]
    operating = contract["operating_point"]
    for axis, allowed in AXIS_LEVELS.items():
        if calibration[axis] not in allowed:
            errors.append(f"calibration.{axis}: {calibration[axis]!r} is not valid for this axis")

    technology_axes = ("synthesis", "physical", "timing")
    if any(calibration[axis] in {"technology_mapped", "placed", "post_route", "measured"} for axis in technology_axes):
        for key in ("pdk", "library", "process_corner", "voltage_V", "temperature_C"):
            if operating[key] is None:
                errors.append(f"evidence_contract.operating_point.{key}: required for technology-calibrated evidence")
        for key in ("synthesis_tool", "synthesis_tool_version"):
            if not tools[key]:
                errors.append(f"evidence_contract.toolchain.{key}: required for technology-calibrated evidence")
    if calibration["physical"] in {"placed", "post_route", "measured"}:
        for key in ("physical_tool", "physical_tool_version"):
            if not tools[key]:
                errors.append(f"evidence_contract.toolchain.{key}: required for placed or stronger evidence")
    if calibration["timing"] != "not_available" and operating["clock_constraint_ns"] is None:
        errors.append("evidence_contract.operating_point.clock_constraint_ns: required when timing is available")
    if calibration["power"] in {"activity_based", "post_route", "measured"}:
        for key in ("power_tool", "power_tool_version"):
            if not tools[key]:
                errors.append(f"evidence_contract.toolchain.{key}: required for activity-based or stronger power evidence")
        for key in ("voltage_V", "temperature_C", "workload_trace_id"):
            if operating[key] is None:
                errors.append(f"evidence_contract.operating_point.{key}: required for activity-based or stronger power evidence")
    if calibration["thermal"] in {"activity_based", "post_route", "measured"}:
        if comparison_policy(calibration["thermal"], calibration["power"])["status"] in {"unavailable", "prohibited"}:
            errors.append("calibration.thermal: calibrated thermal evidence requires compatible power calibration")
        for key in ("thermal_tool", "thermal_tool_version"):
            if not tools[key]:
                errors.append(f"evidence_contract.toolchain.{key}: required for activity-based or stronger thermal evidence")
    if calibration["workload"] != "pending" and operating["workload_trace_id"] is None:
        errors.append("evidence_contract.operating_point.workload_trace_id: required when workload evidence is available")

    totals = snapshot["physical_totals"]
    if totals["technology_mapped_area_um2"] is not None and calibration["synthesis"] == "synthesis_generic":
        errors.append("calibration.synthesis: technology_mapped_area_um2 requires technology_mapped or stronger synthesis evidence")
    if calibration["timing"] == "not_available":
        for key in ("critical_path_ns", "slack_ns"):
            if totals[key] is not None:
                errors.append(f"physical_totals.{key}: must be null when timing is not_available")
    elif totals["critical_path_ns"] is None and totals["slack_ns"] is None:
        errors.append("physical_totals: timing calibration requires critical_path_ns or slack_ns")

    if calibration["workload"] == "pending":
        if snapshot["workload"]["status"] != "pending":
            errors.append("workload.status: must be pending while workload calibration is pending")
        for key in ("throughput_ops_s", "energy_per_op_J"):
            if snapshot["workload"][key] is not None:
                errors.append(f"workload.{key}: must be null while workload calibration is pending")
    elif snapshot["workload"]["status"] == "pending":
        errors.append("workload.status: non-pending workload calibration requires available workload evidence")

    if snapshot["workload"]["energy_per_op_J"] is not None:
        if snapshot["workload"]["throughput_ops_s"] in (None, 0):
            errors.append("workload.energy_per_op_J: requires non-zero throughput_ops_s")
        if calibration["power"] not in {"activity_based", "post_route", "measured"}:
            errors.append("workload.energy_per_op_J: requires activity_based or stronger power evidence")

    for item in snapshot["observations"]:
        has_technology_metric = any(item[x] is not None for x in ("technology_mapped_area_um2", "critical_path_ns", "slack_ns"))
        if has_technology_metric and item["calibration"] not in {"technology_mapped", "placed", "post_route", "measured"}:
            errors.append(f"observations.{item['name']}: technology metrics require technology_mapped or stronger calibration")
        if item["calibration"] == "synthesis_generic" and item["technology_mapped_area_um2"] is not None:
            errors.append(f"observations.{item['name']}: generic synthesis cannot claim technology area")
        if item["calibration"] != "synthesis_generic" and calibration["synthesis"] == "synthesis_generic":
            errors.append(f"calibration.synthesis: cannot be weaker than observation {item['name']}")

    if snapshot["thermal"]["calibration"] != calibration["thermal"]:
        errors.append("thermal.calibration: must match top-level thermal calibration")
    if snapshot["workload"]["calibration"] != calibration["workload"]:
        errors.append("workload.calibration: must match top-level workload calibration")
    for item in snapshot["block_metrics"]:
        if item["calibration"] != calibration["physical"]:
            errors.append(f"block_metrics.{item['instance']}.calibration: must match top-level physical calibration")
    for name, category in snapshot["categories"].items():
        if category.get("blocks"):
            if category.get("physical_calibration") != calibration["physical"]:
                errors.append(f"categories.{name}.physical_calibration: must match top-level physical calibration")
            if category.get("power_calibration") != calibration["power"]:
                errors.append(f"categories.{name}.power_calibration: must match top-level power calibration")

    for source in snapshot["source_files"]:
        if len(source["sha256"]) != 64:
            errors.append(f"source_files.{source['role']}: invalid SHA-256 length")
        if source["bytes"] <= 0:
            errors.append(f"source_files.{source['role']}: evidence file is empty")

    for path, value in _walk_metrics(snapshot):
        if value is not None and not _finite(value):
            errors.append(f"{path}: must be finite or null")
    return errors


def require_valid_snapshot(snapshot: dict) -> None:
    errors = validate_snapshot(snapshot)
    if errors:
        raise EvidenceContractError("Evidence Contract v2 validation failed:\n- " + "\n- ".join(errors))


def _walk_metrics(snapshot: dict):
    keys = {
        "generic_cells", "generic_topological_path_length", "technology_mapped_area_um2",
        "mapped_floorplan_area_um2", "mapped_area_um2", "critical_path_ns", "slack_ns",
        "dynamic_power_W", "leakage_power_W", "total_power_W", "power_density_W_mm2",
        "peak_temperature_K", "peak_delta_K", "operation_count", "latency_cycles",
        "clock_period_ns", "throughput_ops_s", "energy_per_op_J", "bytes",
    }
    def visit(value, prefix):
        if isinstance(value, dict):
            for key, child in value.items():
                child_path = f"{prefix}.{key}" if prefix else key
                if key in keys:
                    yield child_path, child
                elif isinstance(child, (dict, list)):
                    yield from visit(child, child_path)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                yield from visit(child, f"{prefix}[{index}]")
    yield from visit(snapshot, "")
