#!/usr/bin/env python3
"""Validation rules for the lightweight physical-feasibility gate."""
from __future__ import annotations

import hashlib
import json
import math
import re
from functools import lru_cache
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "hardware_cost" / "regression" / "physical_feasibility_schema.json"
GATES = ("PF-0", "PF-1", "PF-2", "PF-3", "PF-4")
ROUTING_CLAIM = re.compile(r"\brouting feasible\b|\broutab(?:le|ility)\b|\b(?:global[- ]?)?routing feasibility\b", re.IGNORECASE)
SAFE_ROUTING_QUALIFIER = re.compile(
    r"\b(?:remains? unestablished|is not established|has not been established|PF-4[^.;]*pending|"
    r"must remain unclaimed|no affirmative|cannot (?:be )?(?:claimed|established)|"
    r"does not establish|not routable|routing (?:is )?unavailable)\b",
    re.IGNORECASE,
)


class PhysicalFeasibilityError(ValueError):
    pass


def pending_physical_feasibility(reason: str = "Physical-feasibility evidence has not been attached to this revision.") -> dict:
    gate = lambda criterion: {"status": "PENDING", "criterion": criterion, "evidence": [], "blockers": [reason]}
    empty_mapping = {
        "status": "PENDING", "calibration": "unavailable", "top": None, "completed": False,
        "mapped_cells": None, "mapped_area_um2": None,
        "sequential_area_um2": None, "unmapped_cells": None, "blackboxes": None,
        "inferred_latches": None, "combinational_loops": None, "clock_period_ns": None,
        "critical_path_ns": None, "worst_slack_ns": None, "timing_target_met": None,
        "reference_clock_period_ns": None, "reference_timing_target_met": None,
        "unconstrained_path_count": None, "critical_startpoint": None, "critical_endpoint": None,
    }
    return {
        "schema_version": 1, "status": "PENDING", "rtl_freeze_allowed": False,
        "production_signoff": "NOT_TARGETED",
        "status_matrix": {"RTL_FEASIBILITY": "PENDING", "LOGICAL_SYNTHESIS": "PENDING",
                          "ADAPTER_TECH_MAPPING": "PENDING", "INTEGRATED_TECH_MAPPING": "PENDING",
                          "COARSE_PLACEMENT": "PENDING", "GLOBAL_ROUTING": "PENDING",
                          "PHYSICAL_FEASIBILITY": "PENDING", "PRODUCTION_SIGNOFF": "NOT_TARGETED"},
        "claim_boundary": "No physical-feasibility claim is available for this revision.", "calibration": "unavailable",
        "claim_class": "assumed",
        "toolchain": {"pdk": None, "library": None, "process_corner": None, "voltage_V": None,
                      "temperature_C": None, "yosys": None, "openroad": None},
        "revision_coherence": {"status": "PENDING", "integrated_netlist_sha256": None,
                               "integrated_sta_matches_netlist": None, "placement_log_sha256": None,
                               "placement_newer_than_mapping": None, "postrepair_fanout_matches_placement": None,
                               "global_route_matches_placement": None,
                               "global_route_newer_than_mapping": None, "stale_evidence": []},
        "gates": {
            "PF-0": gate("RTL feasibility evidence is required."),
            "PF-1": gate("Standalone adapter technology mapping is required."),
            "PF-2": gate("Integrated PCU plus adapter mapping and STA are required."),
            "PF-3": gate("Coarse legal placement is required."),
            "PF-4": gate("Global routing and congestion evidence are required."),
        },
        "adapter_mapping": dict(empty_mapping), "integrated_mapping": dict(empty_mapping),
        "placement": {"status": "PENDING", "calibration": "unavailable", "completed": False,
                      "core_area_um2": None, "movable_area_um2": None,
                      "fixed_area_um2": None, "utilization_pct": None, "initial_violations": None,
                      "final_violations": None, "average_displacement_um": None, "max_displacement_um": None},
        "global_routing": {"status": "PENDING", "calibration": "unavailable", "completed": False,
                           "route_revision": None, "pin_model": None, "signal_layers": None,
                           "congestion_iterations": None, "global_router": None,
                           "openroad_exit_code": None, "execution_clean": None,
                           "prior_route_comparison": {"revision": None, "congestion_remaining": None,
                                                      "congestion_violation_count": None,
                                                      "residual_reduction_pct": None},
                           "overflow_count": None, "max_layer_usage_pct": None,
                           "congestion_violation_count": None, "max_local_overuse": None,
                           "congestion_remaining": None,
                           "routed_nets": None,
                           "severe_congestion": None, "congestion_report_available": False,
                           "guide_available": False, "fanout_skip_threshold": None,
                           "skipped_large_fanout_nets": [], "all_skipped_nets_allowlisted": None,
                           "max_observed_fanout": None, "high_fanout_nets": [],
                           "congestion_hotspots": {
                               "analysis_scope": "captured_congestion_report",
                               "captured_violation_blocks": 0,
                               "direction_block_counts": {}, "layer_block_counts": {},
                               "category_block_counts": {}, "top_bank_source_mentions": [],
                               "top_500um_tiles": [],
                           }},
        "structural": {"status": "PENDING", "unmapped_cells": None, "unresolved_blackboxes": None,
                       "unintended_latches": None, "combinational_loops": None, "unconstrained_paths": None},
        "fanout": {"status": "PENDING", "max_fanout": None, "max_fanout_net": None, "source_stage": None,
                   "repair_area_increase_pct": None, "repair_resized_instances": None,
                   "repair_inserted_buffers": None, "repair_repaired_nets": None,
                   "remaining_slew_violations": None, "remaining_fanout_violations": None,
                   "remaining_capacitance_violations": None},
        "wide_interface": {"adapter_port_bits": None, "generic_wire_bits": None,
                           "generic_wire_bits_is_direct_congestion_metric": False,
                           "largest_interface_bits": None,
                           "largest_interface_name": None, "maximum_fanin": None,
                           "critical_cone_cell_count": None, "logic_depth": None,
                           "critical_path_cell_sequence": [], "risk": "UNAVAILABLE"},
        "buffer_implementation": {"logical_bits": None, "implementation_type": None,
                                  "memory_macro_inferred": None, "mapped_register_count": None,
                                  "top_sequential_cells": None, "mapped_area_um2": None,
                                  "share_of_adapter_area_pct": None, "share_of_integrated_area_pct": None,
                                  "risk": "UNAVAILABLE"},
        "logic_die_budget": {"assumed_usable_area_um2": None, "mapped_area_um2": None,
                             "mapped_utilization_pct": None, "placed_core_area_um2": None,
                             "placed_footprint_utilization_pct": None, "within_budget": None},
        "evidence": [], "blockers": [reason], "risks": [], "notes": [],
    }


@lru_cache(maxsize=64)
def _digest_cached(path_text: str, size: int, mtime_ns: int) -> str:
    value = hashlib.sha256()
    with Path(path_text).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def digest(path: Path) -> str:
    resolved = path.resolve()
    stat = resolved.stat()
    return _digest_cached(str(resolved), stat.st_size, stat.st_mtime_ns)


def validate_physical_feasibility(document: dict, verify_sources: bool = True) -> list[str]:
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    errors = [
        f"{'.'.join(str(x) for x in error.absolute_path) or '<root>'}: {error.message}"
        for error in sorted(Draft202012Validator(schema).iter_errors(document), key=lambda item: list(item.absolute_path))
    ]
    if errors:
        return errors

    gate_statuses = [document["gates"][name]["status"] for name in GATES]
    if document["status"] == "PASS" and any(status != "PASS" for status in gate_statuses):
        errors.append("status: PASS requires PF-0 through PF-4 to PASS")
    if document["gates"]["PF-4"]["status"] != "PASS":
        boundary = document["claim_boundary"]
        if ROUTING_CLAIM.search(boundary) and not SAFE_ROUTING_QUALIFIER.search(boundary):
            errors.append("claim_boundary: affirmative routing feasibility requires PF-4 PASS")
    matrix = document["status_matrix"]
    expected_matrix = {
        "ADAPTER_TECH_MAPPING": document["gates"]["PF-1"]["status"],
        "INTEGRATED_TECH_MAPPING": document["gates"]["PF-2"]["status"],
        "COARSE_PLACEMENT": document["gates"]["PF-3"]["status"],
        "GLOBAL_ROUTING": document["gates"]["PF-4"]["status"],
        "PHYSICAL_FEASIBILITY": document["status"],
        "PRODUCTION_SIGNOFF": document["production_signoff"],
    }
    for key, value in expected_matrix.items():
        if matrix[key] != value:
            errors.append(f"status_matrix.{key}: inconsistent with gate result")
    if document["rtl_freeze_allowed"]:
        if document["status"] != "PASS":
            errors.append("rtl_freeze_allowed: requires overall PASS")
        if document["integrated_mapping"]["unconstrained_path_count"] != 0:
            errors.append("rtl_freeze_allowed: integrated timing must report zero unconstrained paths")
        if document["global_routing"]["overflow_count"] != 0:
            errors.append("rtl_freeze_allowed: global routing must report zero overflow")
        if document["revision_coherence"]["status"] != "PASS":
            errors.append("rtl_freeze_allowed: requires coherent evidence from one mapped revision")

    for name in ("adapter_mapping", "integrated_mapping"):
        mapping = document[name]
        if mapping["completed"]:
            for metric in ("mapped_cells", "mapped_area_um2", "unmapped_cells", "blackboxes", "inferred_latches", "combinational_loops"):
                if mapping[metric] is None:
                    errors.append(f"{name}.{metric}: completed mapping requires a value")
            for metric in ("unmapped_cells", "blackboxes", "inferred_latches", "combinational_loops"):
                if mapping[metric] not in (None, 0):
                    errors.append(f"{name}.{metric}: structural feasibility requires zero")
        if mapping["worst_slack_ns"] is not None:
            expected = mapping["worst_slack_ns"] >= 0
            if mapping["timing_target_met"] is not expected:
                errors.append(f"{name}.timing_target_met: inconsistent with worst_slack_ns")
        if mapping["critical_path_ns"] is not None and mapping["reference_clock_period_ns"] is not None:
            expected = mapping["critical_path_ns"] <= mapping["reference_clock_period_ns"]
            if mapping["reference_timing_target_met"] is not expected:
                errors.append(f"{name}.reference_timing_target_met: inconsistent with critical path and reference period")

    placement = document["placement"]
    if document["gates"]["PF-3"]["status"] == "PASS":
        if not placement["completed"] or placement["final_violations"] != 0:
            errors.append("gates.PF-3: PASS requires completed legal placement with zero final violations")
    routing = document["global_routing"]
    hotspots = routing["congestion_hotspots"]
    if (routing["congestion_violation_count"] is not None
            and hotspots["captured_violation_blocks"] != routing["congestion_violation_count"]):
        errors.append("global_routing.congestion_hotspots: captured block count must match congestion_violation_count")
    if document["gates"]["PF-4"]["status"] == "PASS":
        if routing["execution_clean"] is not True or routing["openroad_exit_code"] != 0:
            errors.append("gates.PF-4: PASS requires a clean OpenROAD exit code of zero")
        if not routing["completed"] or not routing["congestion_report_available"] or not routing["guide_available"]:
            errors.append("gates.PF-4: PASS requires completed routing, guide, and congestion report")
        if routing["overflow_count"] != 0:
            errors.append("gates.PF-4: PASS requires zero routing overflow")
        if routing["severe_congestion"] is not False:
            errors.append("gates.PF-4: PASS requires explicit absence of severe congestion")
        if routing["all_skipped_nets_allowlisted"] is not True:
            errors.append("gates.PF-4: PASS requires every skipped high-fanout net to be an explicit clock/reset/constant exception")

    budget = document["logic_die_budget"]
    if budget["mapped_area_um2"] is not None and budget["assumed_usable_area_um2"]:
        expected = 100.0 * budget["mapped_area_um2"] / budget["assumed_usable_area_um2"]
        if not math.isclose(expected, budget["mapped_utilization_pct"], rel_tol=1e-9, abs_tol=1e-9):
            errors.append("logic_die_budget.mapped_utilization_pct: inconsistent with area ratio")

    if verify_sources:
        for source in document["evidence"]:
            evidence = Path(source["path"])
            evidence = evidence if evidence.is_absolute() else ROOT / evidence
            if not evidence.is_file():
                errors.append(f"evidence.{source['role']}: file does not exist")
            elif source["sha256"] != digest(evidence) or source["bytes"] != evidence.stat().st_size:
                errors.append(f"evidence.{source['role']}: SHA-256 or size mismatch")
    return errors


def require_valid_physical_feasibility(document: dict, verify_sources: bool = True) -> None:
    errors = validate_physical_feasibility(document, verify_sources)
    if errors:
        raise PhysicalFeasibilityError("physical-feasibility validation failed:\n- " + "\n- ".join(errors))
