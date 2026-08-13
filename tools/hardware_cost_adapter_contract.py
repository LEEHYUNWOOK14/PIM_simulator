#!/usr/bin/env python3
"""Validate and combine the five hardware-cost adapter output axes."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import subprocess
from pathlib import Path

from jsonschema import Draft202012Validator

from hardware_cost_evidence_contract import require_valid_snapshot
from physical_feasibility_contract import pending_physical_feasibility


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "hardware_cost" / "regression" / "adapter_output_schema.json"
AXES = ("area", "timing", "power", "workload", "thermal")
CATEGORIES = ("bf16_fp16", "normalization_rounding", "accumulator_reduction", "buffer_register", "control_routing")
AXIS_CALIBRATIONS = {
    "area": {"synthetic", "technology_mapped", "placed", "post_route", "measured"},
    "timing": {"not_available", "synthetic", "technology_mapped", "placed", "post_route", "measured"},
    "power": {"synthetic", "activity_based", "post_route", "measured"},
    "workload": {"pending", "workload_model", "measured"},
    "thermal": {"synthetic_architectural", "activity_based", "post_route", "measured"},
}


class AdapterContractError(ValueError):
    pass


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def locator(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        return str(path.resolve())


def _close(a, b, tolerance=1e-9):
    return math.isclose(float(a), float(b), rel_tol=tolerance, abs_tol=1e-12)


def validate_adapter(doc: dict) -> list[str]:
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    errors = [
        f"{'.'.join(str(x) for x in e.absolute_path) or '<root>'}: {e.message}"
        for e in sorted(Draft202012Validator(schema).iter_errors(doc), key=lambda e: list(e.absolute_path))
    ]
    if errors:
        return errors
    axis, calibration, metrics = doc["axis"], doc["calibration"], doc["metrics"]
    if calibration not in AXIS_CALIBRATIONS[axis]:
        errors.append(f"calibration {calibration!r} is invalid for {axis} adapter")
    if doc["status"] == "PASS":
        if not doc["tool"]["name"] or not doc["tool"]["version"]:
            errors.append("PASS adapter requires tool name and version")
        for source in doc["source_evidence"]:
            if source["sha256"] is None or source["bytes"] is None:
                errors.append("PASS adapter source evidence requires SHA-256 and byte count")
                continue
            source_path = Path(source["path"])
            source_path = source_path if source_path.is_absolute() else ROOT / source_path
            if not source_path.is_file():
                errors.append(f"source evidence does not exist: {source['path']}")
            elif digest(source_path) != source["sha256"] or source_path.stat().st_size != source["bytes"]:
                errors.append(f"source evidence hash/size mismatch: {source['path']}")
    if axis in {"area", "power"} and set(metrics["categories"]) != set(CATEGORIES):
        errors.append(f"{axis}.metrics.categories must contain exactly the five cost categories")
    if axis == "area" and metrics["mapped_floorplan_area_um2"] is not None:
        total = sum(x["mapped_area_um2"] or 0 for x in metrics["categories"].values())
        if not _close(total, metrics["mapped_floorplan_area_um2"]):
            errors.append("area category sum does not conserve mapped floorplan area")
    if axis == "power" and metrics["total_power_W"] is not None:
        if not _close(metrics["dynamic_power_W"] + metrics["leakage_power_W"], metrics["total_power_W"]):
            errors.append("dynamic plus leakage power does not equal total power")
        category_total = sum(x["total_power_W"] or 0 for x in metrics["categories"].values())
        block_total = sum(x["total_power_W"] for x in metrics["blocks"])
        if not _close(category_total, metrics["total_power_W"]):
            errors.append("power category sum does not conserve total power")
        if not _close(block_total, metrics["total_power_W"]):
            errors.append("power block sum does not conserve total power")
        for category, values in metrics["categories"].items():
            if not _close((values["dynamic_power_W"] or 0) + (values["leakage_power_W"] or 0), values["total_power_W"] or 0):
                errors.append(f"power category {category} does not conserve dynamic plus leakage power")
    if axis == "timing":
        if calibration == "not_available" and any(metrics[k] is not None for k in ("critical_path_ns", "slack_ns")):
            errors.append("unavailable timing must contain null metrics")
        if calibration != "not_available" and metrics["critical_path_ns"] is None and metrics["slack_ns"] is None:
            errors.append("available timing requires critical path or slack")
        if calibration != "not_available" and doc["operating_point"]["clock_constraint_ns"] is None:
            errors.append("available timing requires clock_constraint_ns")
    if axis == "workload" and calibration == "pending" and metrics["throughput_ops_s"] is not None:
        errors.append("pending workload cannot provide throughput")
    if axis == "workload" and calibration != "pending" and doc["operating_point"]["workload_trace_id"] is None:
        errors.append("available workload requires workload_trace_id")
    if axis == "power" and calibration in {"activity_based", "post_route", "measured"}:
        for key in ("voltage_V", "temperature_C", "workload_trace_id"):
            if doc["operating_point"][key] is None:
                errors.append(f"{calibration} power requires {key}")
    if axis in {"area", "timing"} and calibration in {"technology_mapped", "placed", "post_route", "measured"}:
        for key in ("pdk", "library", "process_corner", "voltage_V", "temperature_C"):
            if doc["operating_point"][key] is None:
                errors.append(f"{calibration} {axis} requires {key}")
    if axis == "thermal":
        if metrics["peak_temperature_K"] is not None and metrics["peak_delta_K"] is not None:
            ambient = doc["operating_point"].get("temperature_C")
            if ambient is not None and not _close(metrics["peak_temperature_K"] - (ambient + 273.15), metrics["peak_delta_K"], 1e-7):
                errors.append("thermal peak delta is inconsistent with operating-point ambient")
        if calibration in {"activity_based", "post_route", "measured"} and doc["operating_point"]["temperature_C"] is None:
            errors.append(f"{calibration} thermal evidence requires temperature_C")
    if calibration in {"synthetic", "synthetic_architectural", "synthesis_generic", "workload_model"} and doc["claim_class"] == "measured":
        errors.append("synthetic/modeled calibration cannot claim measured evidence")
    return errors


def require_valid_adapter(doc: dict) -> None:
    errors = validate_adapter(doc)
    if errors:
        raise AdapterContractError("adapter validation failed:\n- " + "\n- ".join(errors))


def load_adapter(path: Path) -> dict:
    doc = json.loads(path.read_text(encoding="utf-8"))
    require_valid_adapter(doc)
    return doc


def _git_info():
    def run(*args):
        return subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True, check=True).stdout.strip()
    return run("rev-parse", "HEAD"), bool(run("status", "--porcelain"))


def _merge_operating_point(adapters: dict) -> dict:
    result = {key: None for key in ("pdk", "library", "process_corner", "voltage_V", "temperature_C", "clock_constraint_ns", "workload_trace_id")}
    for adapter in adapters.values():
        for key, value in adapter["operating_point"].items():
            if value is None:
                continue
            if result[key] is not None and result[key] != value:
                raise AdapterContractError(f"operating-point conflict for {key}: {result[key]!r} != {value!r}")
            result[key] = value
    return result


def build_snapshot(adapter_paths, captured_at, output_path=None):
    paths = [Path(x) if Path(x).is_absolute() else ROOT / x for x in adapter_paths]
    adapters = {}
    for path in paths:
        doc = load_adapter(path)
        if doc["axis"] in adapters:
            raise AdapterContractError(f"duplicate adapter axis: {doc['axis']}")
        adapters[doc["axis"]] = doc
    if set(adapters) != set(AXES):
        raise AdapterContractError(f"adapter bundle must contain exactly {list(AXES)}")
    candidates = [doc["candidate"] for doc in adapters.values()]
    if any(candidate != candidates[0] for candidate in candidates[1:]):
        raise AdapterContractError("candidate identity or parameters differ across adapters")

    area, timing, power, workload, thermal = (adapters[x] for x in AXES)
    candidate = candidates[0]
    area_metrics, power_metrics = area["metrics"], power["metrics"]
    if set(area_metrics["categories"]) != set(power_metrics["categories"]):
        raise AdapterContractError("area and power category sets differ")
    for category in CATEGORIES:
        area_value = area_metrics["categories"][category]["mapped_area_um2"]
        power_area = power_metrics["categories"][category]["mapped_area_um2"]
        if area_value is not None and power_area is not None and not _close(area_value, power_area):
            raise AdapterContractError(f"area/power mapped-area mismatch for {category}")

    commit, dirty = _git_info()
    source_files = [{
        "role": f"adapter:{doc['axis']}", "path": locator(path), "sha256": digest(path), "bytes": path.stat().st_size,
        "claim_class": doc["claim_class"], "tool": doc["tool"]["name"], "tool_version": doc["tool"]["version"],
    } for path, doc in zip(paths, [json.loads(p.read_text(encoding="utf-8")) for p in paths])]
    categories = {}
    for name in CATEGORIES:
        a, p = area_metrics["categories"][name], power_metrics["categories"][name]
        blocks = [x["instance"] for x in power_metrics["blocks"] if x["category"] == name]
        mapped_area = a["mapped_area_um2"] or 0.0
        total_power = p["total_power_W"] or 0.0
        categories[name] = {
            "mapped_area_um2": mapped_area, "dynamic_power_W": p["dynamic_power_W"] or 0.0,
            "leakage_power_W": p["leakage_power_W"] or 0.0, "total_power_W": total_power,
            "blocks": blocks, "synthesis_observations": [],
            "power_density_W_mm2": total_power / (mapped_area * 1e-6) if mapped_area else None,
            "physical_data_available": bool(blocks), "physical_calibration": area["calibration"] if blocks else "not_available",
            "power_calibration": power["calibration"] if blocks else "not_available",
        }
    primary_category = area_metrics["primary_category"]
    observation = {
        "name": f"{candidate['id']}_primary", "precision": area_metrics["precision"], "category": primary_category,
        "generic_cells": area_metrics["generic_cells"] or 0,
        "generic_topological_path_length": area_metrics["generic_topological_path_length"] or 0,
        "technology_mapped_area_um2": area_metrics["technology_mapped_area_um2"],
        "critical_path_ns": None, "slack_ns": None,
        "calibration": "synthesis_generic" if area["calibration"] == "synthetic" else area["calibration"],
        "claim_class": area["claim_class"], "evidence": next(x["path"] for x in source_files if x["role"] == "adapter:area"),
        "upstream_evidence": {"adapter_sources": area["source_evidence"]},
        "warning": "Synthetic/generic observations are proxies unless technology calibration is explicitly declared.",
    }
    categories[primary_category]["synthesis_observations"].append({key: observation[key] for key in ("name", "precision", "generic_cells", "generic_topological_path_length", "calibration")})
    block_metrics = []
    for block in power_metrics["blocks"]:
        mapped_area = block["mapped_area_um2"]
        block_metrics.append({
            **block,
            "target": block.get("target", {"stack": 0, "layer": "logic", "die": -1, "channel": -1, "bank": -1}),
            "power_density_W_mm2": block["total_power_W"] / (mapped_area * 1e-6) if mapped_area else None,
            "calibration": area["calibration"], "claim_class": power["claim_class"],
        })
    throughput = workload["metrics"]["throughput_ops_s"]
    energy_eligible = power["calibration"] in {"activity_based", "post_route", "measured"}
    energy = power_metrics["total_power_W"] / throughput if throughput and energy_eligible else None
    toolchain = {
        "capture_tool": "hardware_cost_adapter_contract.py", "capture_tool_version": "1",
        "synthesis_tool": area["tool"]["name"], "synthesis_tool_version": area["tool"]["version"],
        "physical_tool": area["tool"]["name"] if area["calibration"] in {"placed", "post_route", "measured"} else None,
        "physical_tool_version": area["tool"]["version"] if area["calibration"] in {"placed", "post_route", "measured"} else None,
        "power_tool": power["tool"]["name"], "power_tool_version": power["tool"]["version"],
        "thermal_tool": thermal["tool"]["name"], "thermal_tool_version": thermal["tool"]["version"],
    }
    snapshot = {
        "schema_version": 2,
        "evidence_contract": {"contract_version": 2, "status": "PROVISIONAL", "claim_boundary": "Synthetic candidate comparison fixture; not silicon or signoff evidence.", "candidate_parameters": candidate["parameters"], "toolchain": toolchain, "operating_point": _merge_operating_point(adapters)},
        "revision": {"id": candidate["id"], "label": candidate["label"], "git_commit": commit, "working_tree_dirty": dirty, "captured_at": captured_at},
        "parameter_status": {"final_architecture_parameters_selected": False, "reason": "Candidate comparison only; architecture selection remains external."},
        "calibration": {"synthesis": observation["calibration"], "physical": area["calibration"], "power": power["calibration"], "thermal": thermal["calibration"], "timing": timing["calibration"], "workload": workload["calibration"]},
        "observations": [observation], "block_metrics": block_metrics,
        "physical_totals": {"primary_observation": observation["name"], "generic_cells": observation["generic_cells"], "technology_mapped_area_um2": area_metrics["technology_mapped_area_um2"], "mapped_floorplan_area_um2": area_metrics["mapped_floorplan_area_um2"], "dynamic_power_W": power_metrics["dynamic_power_W"], "leakage_power_W": power_metrics["leakage_power_W"], "total_power_W": power_metrics["total_power_W"], "critical_path_ns": timing["metrics"]["critical_path_ns"], "slack_ns": timing["metrics"]["slack_ns"], "note": "Assembled from five independently validated adapters."},
        "physical_feasibility": pending_physical_feasibility("Synthetic adapter candidate has no physical-feasibility evidence."),
        "thermal": {**thermal["metrics"], "calibration": thermal["calibration"], "claim_class": thermal["claim_class"]},
        "workload": {"status": "pending" if workload["calibration"] == "pending" else "available", **workload["metrics"], "energy_per_op_J": energy, "calibration": workload["calibration"], "claim_class": workload["claim_class"], "note": "Energy/op is emitted only with activity-based or stronger power."},
        "categories": categories, "source_files": source_files,
        "notes": ["Five-axis common adapter contract bundle.", "Synthetic fixtures validate plumbing and comparison behavior only."],
    }
    require_valid_snapshot(snapshot)
    if output_path:
        output = Path(output_path) if Path(output_path).is_absolute() else ROOT / output_path
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(snapshot, indent=2), encoding="utf-8")
    return snapshot


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adapters", nargs=5, required=True)
    parser.add_argument("--captured-at", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        snapshot = build_snapshot(args.adapters, args.captured_at, args.output)
    except (AdapterContractError, ValueError, KeyError, OSError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}")
        return 2
    print(f"HARDWARE_COST_ADAPTER_BUNDLE PASS candidate={snapshot['revision']['id']} output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
